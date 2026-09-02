from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

def write(path, content):
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")

def replace_once(path, old, new):
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}")
    write(path, text.replace(old, new, 1))

replace_once("pubspec.yaml", "version: 1.3.4+26", "version: 1.3.5+27")
pubspec = read("pubspec.yaml")
marker = "# TV FULL PRO 1.3.5+27 premium-live-ui-v27"
if marker not in pubspec:
    write("pubspec.yaml", pubspec.rstrip() + "\n\n" + marker + "\n")

premium_path = "lib/widgets/tv_full_premium_ui.dart"
premium = read(premium_path)
anchor = """const Color tvFullViolet = Color(0xFF8A48FF);
const Color tvFullPanel = Color(0xD90A1220);
"""
insert = """const Color tvFullViolet = Color(0xFF8A48FF);
const Color tvFullPanel = Color(0xD90A1220);
const Color tvFullLiveRed = Color(0xFFFF304A);

class TvFullLiveBadge extends StatelessWidget {
  final bool compact;
  final String label;

  const TvFullLiveBadge({
    super.key,
    this.compact = false,
    this.label = 'EN VIVO',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: tvFullLiveRed.withValues(alpha: compact ? .10 : .13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: tvFullLiveRed.withValues(alpha: compact ? .66 : .82),
          width: compact ? .8 : 1,
        ),
        boxShadow: compact
            ? const []
            : [
                BoxShadow(
                  color: tvFullLiveRed.withValues(alpha: .30),
                  blurRadius: 14,
                  spreadRadius: .5,
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 5 : 7,
            height: compact ? 5 : 7,
            decoration: const BoxDecoration(
              color: tvFullLiveRed,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: compact ? 5 : 7),
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFFFFD9DE),
              fontSize: compact ? 9 : 11,
              fontWeight: FontWeight.w900,
              letterSpacing: .45,
            ),
          ),
        ],
      ),
    );
  }
}
"""
if "class TvFullLiveBadge" not in premium:
    if anchor not in premium:
        raise SystemExit("premium badge anchor missing")
    write(premium_path, premium.replace(anchor, insert, 1))

usage_service = r"""import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';

class LiveChannelUsageService {
  LiveChannelUsageService._();

  static final LiveChannelUsageService instance = LiveChannelUsageService._();

  static const String _storageKey = 'tvfull_live_usage_v1';
  static const int _maxRecords = 80;

  final Map<String, _LiveUsageRecord> _records = <String, _LiveUsageRecord>{};
  bool _loaded = false;
  Future<void>? _loading;

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    final pending = _loading;
    if (pending != null) return pending;
    final future = _load();
    _loading = future;
    return future;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final key = entry.key.toString();
            final value = entry.value;
            if (value is! Map) continue;
            final count = (value['count'] as num?)?.toInt() ?? 0;
            final last = (value['last'] as num?)?.toInt() ?? 0;
            if (count <= 0 || last <= 0) continue;
            _records[key] = _LiveUsageRecord(count: count, lastEpochMs: last);
          }
        }
      }
    } catch (_) {
      _records.clear();
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  Future<void> record(Channel channel) async {
    await ensureLoaded();
    final key = _keyFor(channel);
    final now = DateTime.now().millisecondsSinceEpoch;
    final previous = _records[key];
    _records[key] = _LiveUsageRecord(
      count: (previous?.count ?? 0) + 1,
      lastEpochMs: now,
    );
    _trim();
    await _persist();
  }

  List<Channel> featuredChannels(
    List<Channel> channels, {
    required bool Function(Channel channel) isFavorite,
    int limit = 7,
  }) {
    if (channels.isEmpty || limit <= 0) return const <Channel>[];

    final sports = channels.where(isSportsChannel).toList(growable: false);
    final primary =
        sports.isEmpty ? List<Channel>.from(channels) : List<Channel>.from(sports);
    primary.sort(
      (a, b) => _score(b, isFavorite).compareTo(_score(a, isFavorite)),
    );

    final result = <Channel>[];
    final seen = <String>{};
    for (final channel in primary) {
      if (seen.add(channel.uniqueKey)) result.add(channel);
      if (result.length >= limit) return result;
    }

    final fallback = List<Channel>.from(channels)
      ..sort(
        (a, b) => _score(b, isFavorite).compareTo(_score(a, isFavorite)),
      );
    for (final channel in fallback) {
      if (seen.add(channel.uniqueKey)) result.add(channel);
      if (result.length >= limit) break;
    }
    return result;
  }

  List<Channel> recentChannels(List<Channel> channels, {int limit = 7}) {
    if (channels.isEmpty || limit <= 0) return const <Channel>[];
    final values =
        channels.where((channel) => _recordFor(channel) != null).toList();
    values.sort((a, b) {
      final aLast = _recordFor(a)?.lastEpochMs ?? 0;
      final bLast = _recordFor(b)?.lastEpochMs ?? 0;
      return bLast.compareTo(aLast);
    });
    if (values.length <= limit) return values;
    return values.sublist(0, limit);
  }

  static bool isSportsChannel(Channel channel) {
    final value = '${channel.group ?? ''} ${channel.name}'.toLowerCase();
    const keywords = <String>[
      'deporte',
      'sport',
      'futbol',
      'fútbol',
      'football',
      'soccer',
      'liga',
      'copa',
      'champion',
      'partido',
      'racing',
      'motor',
      'tenis',
      'tennis',
      'basket',
    ];
    for (final keyword in keywords) {
      if (value.contains(keyword)) return true;
    }
    return false;
  }

  int _score(Channel channel, bool Function(Channel) isFavorite) {
    final record = _recordFor(channel);
    var score = 0;
    if (isFavorite(channel)) score += 120000;
    if (isSportsChannel(channel)) score += 40000;
    if (record != null) {
      score += record.count.clamp(0, 500) * 900;
      final age = DateTime.now().millisecondsSinceEpoch - record.lastEpochMs;
      if (age < const Duration(days: 1).inMilliseconds) {
        score += 16000;
      } else if (age < const Duration(days: 7).inMilliseconds) {
        score += 8000;
      } else if (age < const Duration(days: 30).inMilliseconds) {
        score += 3000;
      }
    }
    return score;
  }

  _LiveUsageRecord? _recordFor(Channel channel) => _records[_keyFor(channel)];

  String _keyFor(Channel channel) {
    final digest = sha1.convert(utf8.encode(channel.uniqueKey)).toString();
    return digest.substring(0, 20);
  }

  void _trim() {
    if (_records.length <= _maxRecords) return;
    final entries = _records.entries.toList()
      ..sort((a, b) => b.value.lastEpochMs.compareTo(a.value.lastEpochMs));
    _records
      ..clear()
      ..addEntries(entries.take(_maxRecords));
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = <String, Map<String, int>>{};
      for (final entry in _records.entries) {
        encoded[entry.key] = <String, int>{
          'count': entry.value.count,
          'last': entry.value.lastEpochMs,
        };
      }
      await prefs.setString(_storageKey, jsonEncode(encoded));
    } catch (_) {}
  }
}

class _LiveUsageRecord {
  final int count;
  final int lastEpochMs;

  const _LiveUsageRecord({
    required this.count,
    required this.lastEpochMs,
  });
}
"""
write("lib/services/live_channel_usage_service.dart", usage_service)

premium_catalog = r"""import 'dart:async';

import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../services/device_performance_service.dart';
import '../services/live_channel_usage_service.dart';
import 'channel_logo_image.dart';
import 'tv_catalog_category_row.dart';
import 'tv_full_premium_ui.dart';

class TvLivePremiumCatalog extends StatefulWidget {
  final List<Channel> channels;
  final List<String> categories;
  final String? selectedCategory;
  final String query;
  final bool showSearchField;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Channel> onPlay;
  final bool Function(Channel channel) isFavorite;
  final ValueChanged<Channel> onFavoriteToggle;

  const TvLivePremiumCatalog({
    super.key,
    required this.channels,
    required this.categories,
    required this.selectedCategory,
    required this.query,
    required this.onCategorySelected,
    required this.onQueryChanged,
    required this.onPlay,
    required this.isFavorite,
    required this.onFavoriteToggle,
    this.showSearchField = true,
  });

  @override
  State<TvLivePremiumCatalog> createState() => _TvLivePremiumCatalogState();
}

class _TvLivePremiumCatalogState extends State<TvLivePremiumCatalog> {
  final LiveChannelUsageService _usage = LiveChannelUsageService.instance;
  Channel? _focusedChannel;

  @override
  void initState() {
    super.initState();
    unawaited(_usage.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    }));
  }

  @override
  void didUpdateWidget(covariant TvLivePremiumCatalog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focused = _focusedChannel;
    if (focused != null &&
        !widget.channels.any((item) => item.uniqueKey == focused.uniqueKey)) {
      _focusedChannel = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final featured = widget.query.trim().isEmpty
        ? _usage.featuredChannels(
            widget.channels,
            isFavorite: widget.isFavorite,
            limit: 7,
          )
        : const <Channel>[];
    final hero = _focusedChannel ??
        (featured.isNotEmpty
            ? featured.first
            : (widget.channels.isNotEmpty ? widget.channels.first : null));

    return Row(
      children: [
        SizedBox(
          width: 210,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xF00A1320), Color(0xF0050A12)],
              ),
              border: Border(
                right: BorderSide(color: Color(0x3039C5FF), width: 1),
              ),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 18),
              itemCount: widget.categories.length + 1,
              itemBuilder: (context, index) {
                final category =
                    index == 0 ? null : widget.categories[index - 1];
                return TvCatalogCategoryRow(
                  label: category ?? 'Todos',
                  selected: category == widget.selectedCategory,
                  primary: index == 0,
                  autofocus: index == 0,
                  onTap: () => widget.onCategorySelected(category),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _toolbar(),
                if (hero != null) ...[
                  const SizedBox(height: 8),
                  _hero(hero),
                ],
                if (featured.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const _SectionTitle(
                    title: 'Canales destacados',
                    subtitle: 'Partidos y deportes · favoritos y más usados',
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 68,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: featured.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final channel = featured[index];
                        return _FeaturedChannelCard(
                          channel: channel,
                          onFocus: () =>
                              setState(() => _focusedChannel = channel),
                          onPlay: () => widget.onPlay(channel),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _SectionTitle(
                  title: widget.selectedCategory ?? 'Todos los canales',
                  subtitle: '${widget.channels.length} canales disponibles',
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: widget.channels.isEmpty
                      ? const Center(
                          child: Text(
                            'No se encontraron canales.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : GridView.builder(
                          key: ValueKey<String>(
                            'premium-live:${widget.selectedCategory ?? 'all'}:${widget.query}',
                          ),
                          padding: const EdgeInsets.only(bottom: 8),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 310,
                            mainAxisExtent: 66,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: widget.channels.length,
                          itemBuilder: (context, index) {
                            final channel = widget.channels[index];
                            return _LiveChannelCard(
                              channel: channel,
                              onFocus: () =>
                                  setState(() => _focusedChannel = channel),
                              onPlay: () => widget.onPlay(channel),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _toolbar() {
    return Row(
      children: [
        const Icon(Icons.live_tv_rounded, size: 21, color: tvFullCyan),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            widget.selectedCategory == null
                ? 'TV EN VIVO'
                : 'TV EN VIVO  ·  ${widget.selectedCategory}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: .35,
            ),
          ),
        ),
        if (widget.showSearchField)
          SizedBox(
            width: 250,
            height: 38,
            child: TextFormField(
              initialValue: widget.query,
              decoration: InputDecoration(
                hintText: 'Buscar canal…',
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                isDense: true,
                filled: true,
                fillColor: Colors.white.withValues(alpha: .035),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: .12),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: .10),
                  ),
                ),
              ),
              onChanged: widget.onQueryChanged,
            ),
          ),
      ],
    );
  }

  Widget _hero(Channel channel) {
    final group = channel.group?.trim();
    return Container(
      height: 145,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xF0121D35),
            Color(0xF0091020),
            Color(0xF0040911),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -38,
            child: IgnorePointer(
              child: Icon(
                Icons.live_tv_rounded,
                size: 210,
                color: tvFullCyan.withValues(alpha: .035),
              ),
            ),
          ),
          Positioned(
            right: 34,
            bottom: -48,
            child: IgnorePointer(
              child: Container(
                width: 210,
                height: 105,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: tvFullViolet.withValues(alpha: .12),
                      blurRadius: 46,
                      spreadRadius: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: tvFullCyan.withValues(alpha: .38),
                    ),
                  ),
                  child: ChannelLogoImage(
                    channel: channel,
                    fit: BoxFit.contain,
                    cacheWidth: 184,
                    cacheHeight: 184,
                    priority: 110,
                    prefetchExtent: 0,
                    fallback: const Icon(
                      Icons.live_tv_rounded,
                      size: 40,
                      color: Colors.white54,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const TvFullLiveBadge(),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        group == null || group.isEmpty
                            ? 'Señal en vivo · navegación rápida'
                            : '$group · señal en vivo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () => widget.onPlay(channel),
                            icon: const Icon(Icons.play_arrow_rounded, size: 20),
                            label: const Text('Ver ahora'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () {
                              widget.onFavoriteToggle(channel);
                              setState(() {});
                            },
                            icon: Icon(
                              widget.isFavorite(channel)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 18,
                            ),
                            label: Text(
                              widget.isFavorite(channel)
                                  ? 'Favorito'
                                  : 'Agregar a favoritos',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 16, color: tvFullCyan),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 10.5),
          ),
        ),
      ],
    );
  }
}

class _FeaturedChannelCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback onFocus;
  final VoidCallback onPlay;

  const _FeaturedChannelCard({
    required this.channel,
    required this.onFocus,
    required this.onPlay,
  });

  @override
  State<_FeaturedChannelCard> createState() => _FeaturedChannelCardState();
}

class _FeaturedChannelCardState extends State<_FeaturedChannelCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    return AnimatedContainer(
      duration: Duration(milliseconds: lowRam ? 60 : 100),
      width: 205,
      decoration: tvFullGlassDecoration(
        focused: _focused,
        radius: 12,
        accent: tvFullCyan,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onFocusChange: (value) {
            if (value) widget.onFocus();
            setState(() => _focused = value);
          },
          onTap: widget.onPlay,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: ChannelLogoImage(
                    channel: widget.channel,
                    fit: BoxFit.contain,
                    cacheWidth: 84,
                    cacheHeight: 84,
                    priority: _focused ? 100 : 50,
                    prefetchExtent: 0,
                    fallback: const Icon(Icons.live_tv_rounded, size: 22),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              _focused ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Row(
                        children: [
                          Icon(Icons.circle, size: 5, color: tvFullLiveRed),
                          SizedBox(width: 4),
                          Text(
                            'EN VIVO',
                            style: TextStyle(
                              color: Color(0xFFFF8998),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveChannelCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback onFocus;
  final VoidCallback onPlay;

  const _LiveChannelCard({
    required this.channel,
    required this.onFocus,
    required this.onPlay,
  });

  @override
  State<_LiveChannelCard> createState() => _LiveChannelCardState();
}

class _LiveChannelCardState extends State<_LiveChannelCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    return AnimatedContainer(
      duration: Duration(milliseconds: lowRam ? 55 : 95),
      decoration: tvFullGlassDecoration(
        focused: _focused,
        radius: 11,
        accent: tvFullCyan,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onFocusChange: (value) {
            if (value) widget.onFocus();
            setState(() => _focused = value);
          },
          onTap: widget.onPlay,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: ChannelLogoImage(
                    channel: widget.channel,
                    fit: BoxFit.contain,
                    cacheWidth: 80,
                    cacheHeight: 80,
                    priority: _focused ? 100 : 25,
                    prefetchExtent: 0,
                    fallback: const Icon(Icons.live_tv_rounded, size: 21),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              _focused ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.circle,
                            size: 5,
                            color: tvFullLiveRed,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'VIVO',
                            style: TextStyle(
                              color: Color(0xFFFF8998),
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if ((widget.channel.group ?? '').trim().isNotEmpty) ...[
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                widget.channel.group!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 8.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
"""
write("lib/widgets/tv_live_premium_catalog.dart", premium_catalog)

channel_path = "lib/screens/channel_list_screen.dart"
channel = read(channel_path)
if "tv_live_premium_catalog.dart" not in channel:
    channel = channel.replace(
        "import '../widgets/parental_lock_button.dart';\n",
        "import '../widgets/parental_lock_button.dart';\nimport '../widgets/tv_live_premium_catalog.dart';\n",
        1,
    )
write(channel_path, channel)

replace_once(
    channel_path,
    """              onPlay: (channel) =>
                  _openChannel(context, channels, channel, provider),
            );""",
    """              onPlay: (channel) =>
                  _openChannel(context, channels, channel, provider),
              isFavorite: provider.isFavorite,
              onFavoriteToggle: provider.toggleFavorite,
            );""",
)

replace_once(
    channel_path,
    """    } finally {
      _openingPlayer = false;
      ArtworkCacheService.instance.resumeBrowsing();
    }
  }
}""",
    """    } finally {
      _openingPlayer = false;
      ArtworkCacheService.instance.resumeBrowsing();
      if (mounted) setState(() {});
    }
  }
}""",
)

replace_once(
    channel_path,
    """  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Channel> onPlay;

  const _TvCatalogLayout({""",
    """  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Channel> onPlay;
  final bool Function(Channel channel) isFavorite;
  final ValueChanged<Channel> onFavoriteToggle;

  const _TvCatalogLayout({""",
)

replace_once(
    channel_path,
    """    required this.onQueryChanged,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Row(""",
    """    required this.onQueryChanged,
    required this.onPlay,
    required this.isFavorite,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (mode == _CatalogMode.live) {
      return TvLivePremiumCatalog(
        channels: channels,
        categories: groups,
        selectedCategory: selectedGroup,
        query: query,
        showSearchField: true,
        onCategorySelected: onGroupSelected,
        onQueryChanged: onQueryChanged,
        onPlay: onPlay,
        isFavorite: isFavorite,
        onFavoriteToggle: onFavoriteToggle,
      );
    }

    return Row(""",
)

xtream_path = "lib/screens/xtream_live_screen.dart"
xtream = read(xtream_path)
if "tv_live_premium_catalog.dart" not in xtream:
    xtream = xtream.replace(
        "import '../widgets/tv_full_premium_ui.dart';\n",
        "import '../widgets/tv_full_premium_ui.dart';\nimport '../widgets/tv_live_premium_catalog.dart';\n",
        1,
    )
write(xtream_path, xtream)

replace_once(
    xtream_path,
    """    final visible =
        _searchOpen ? index.search(_query) : index.forCategory(_category);

    return Row(""",
    """    final visible =
        _searchOpen ? index.search(_query) : index.forCategory(_category);

    if (!_searchOpen) {
      final provider = context.read<IptvProvider>();
      return TvLivePremiumCatalog(
        channels: visible,
        categories: categories,
        selectedCategory: _category,
        query: _query,
        showSearchField: false,
        onCategorySelected: (category) {
          setState(() => _category = category);
          _resetCatalogScroll();
        },
        onQueryChanged: (_) {},
        onPlay: (channel) {
          final channelIndex = visible.indexOf(channel);
          if (channelIndex >= 0) {
            unawaited(_openPlayer(visible, channelIndex));
          }
        },
        isFavorite: provider.isFavorite,
        onFavoriteToggle: provider.toggleFavorite,
      );
    }

    return Row(""",
)

replace_once(
    xtream_path,
    """    } finally {
      _openingPlayer = false;
    }
  }
}""",
    """    } finally {
      _openingPlayer = false;
      if (mounted) setState(() {});
    }
  }
}""",
)

player_path = "lib/screens/android_media3_texture_player_screen.dart"
player = read(player_path)
if "live_channel_usage_service.dart" not in player:
    player = player.replace(
        "import '../services/device_performance_service.dart';\n",
        "import '../services/device_performance_service.dart';\nimport '../services/live_channel_usage_service.dart';\n",
        1,
    )
if "tv_full_premium_ui.dart" not in player:
    player = player.replace(
        "import '../widgets/channel_logo_image.dart';\n",
        "import '../widgets/channel_logo_image.dart';\nimport '../widgets/tv_full_premium_ui.dart';\n",
        1,
    )
write(player_path, player)

replace_once(
    player_path,
    """  final ChannelHealthService _health = ChannelHealthService.instance;
  StreamSubscription<dynamic>? _eventSub;""",
    """  final ChannelHealthService _health = ChannelHealthService.instance;
  final LiveChannelUsageService _usage = LiveChannelUsageService.instance;
  StreamSubscription<dynamic>? _eventSub;""",
)

replace_once(
    player_path,
    """    _health.markHealthy(_channel, slow: slow);
    _healthRecordedGeneration = _openGeneration;
  }""",
    """    _health.markHealthy(_channel, slow: slow);
    _healthRecordedGeneration = _openGeneration;
    unawaited(_usage.record(_channel));
  }""",
)

player = read(player_path)
start = player.find("  Widget _liveHud() => SafeArea(")
end = player.find("\n  Widget _channelDrawer() => Align(", start)
if start < 0 or end < 0:
    raise SystemExit("player HUD markers missing")
new_hud = r"""  Widget _liveHud() => SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 108,
            padding: const EdgeInsets.fromLTRB(22, 30, 22, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00000000),
                  Color(0x3502080F),
                  Color(0xA802060B),
                ],
                stops: [0, .42, 1],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .24),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: tvFullCyan.withValues(alpha: .40),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: tvFullCyan.withValues(alpha: .10),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: ChannelLogoImage(
                    channel: _channel,
                    fit: BoxFit.contain,
                    cacheWidth: 124,
                    cacheHeight: 124,
                    priority: 120,
                    prefetchExtent: 0,
                    fallback: const Icon(
                      Icons.live_tv_rounded,
                      size: 31,
                      color: Colors.white70,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _channel.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black87,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const TvFullLiveBadge(),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          (_channel.group ?? '').trim().isEmpty
                              ? 'TV en vivo'
                              : _channel.group!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 6),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_hasMultipleAudioTracks)
                  _LiveHudAction(
                    icon: Icons.language_rounded,
                    label: 'Audio',
                    onTap: () => unawaited(_showAudioPicker()),
                  ),
                if (_hasMultipleAudioTracks) const SizedBox(width: 8),
                _LiveHudAction(
                  icon: Icons.grid_view_rounded,
                  label: 'Canales',
                  onTap: _openChannelList,
                ),
                const SizedBox(width: 12),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '← → cambiar   ·   ↓ canales',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(color: Colors.black87, blurRadius: 6),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

"""
write(player_path, player[:start] + new_hud + player[end:])

player = read(player_path)
action_anchor = "\nclass _LiveErrorButton extends StatefulWidget {"
if "class _LiveHudAction" not in player:
    action_class = r"""class _LiveHudAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LiveHudAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: .10),
        side: BorderSide(color: Colors.white.withValues(alpha: .18)),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 17, color: tvFullCyan),
      label: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

"""
    if action_anchor not in player:
        raise SystemExit("HUD action anchor missing")
    write(
        player_path,
        player.replace(
            action_anchor,
            "\n" + action_class + "class _LiveErrorButton extends StatefulWidget {",
            1,
        ),
    )

test = r"""import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/services/live_channel_usage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('destacados prioriza señales deportivas sin nombres hardcodeados',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LiveChannelUsageService.instance.ensureLoaded();

    const general = Channel(
      name: 'Canal General',
      url: 'https://example.test/general',
      group: 'Entretenimiento',
    );
    const sports = Channel(
      name: 'Futbol Central',
      url: 'https://example.test/sports',
      group: 'Deportes',
    );

    expect(LiveChannelUsageService.isSportsChannel(sports), isTrue);
    expect(LiveChannelUsageService.isSportsChannel(general), isFalse);

    final featured = LiveChannelUsageService.instance.featuredChannels(
      const <Channel>[general, sports],
      isFavorite: (_) => false,
      limit: 2,
    );

    expect(featured.first, sports);
  });
}
"""
write("test/live_channel_usage_service_test.dart", test)

print("TV FULL PRO premium LIVE v27 patch applied.")
