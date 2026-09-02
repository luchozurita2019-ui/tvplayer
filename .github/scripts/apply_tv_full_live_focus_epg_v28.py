from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

service = r'''import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
import 'xtream_fast_catalog_service.dart';
import 'xtream_http_client.dart';

class LiveProgram {
  final String title;
  final String? description;
  final DateTime? start;
  final DateTime? end;

  const LiveProgram({
    required this.title,
    this.description,
    this.start,
    this.end,
  });
}

class LiveProgramGuide {
  final LiveProgram? now;
  final LiveProgram? next;

  const LiveProgramGuide({this.now, this.next});

  bool get hasPrograms => now != null || next != null;
}

typedef LiveProgramGuideLoader = Future<LiveProgramGuide?> Function(
  Channel channel,
);

class LiveEpgService {
  LiveEpgService._();

  static final LiveEpgService instance = LiveEpgService._();

  static const Duration _timeout = Duration(seconds: 5);
  static const Duration _cacheFreshFor = Duration(minutes: 3);
  static const int _maxCacheEntries = 24;

  final Map<String, _LiveEpgCacheEntry> _cache =
      <String, _LiveEpgCacheEntry>{};
  final Map<String, Future<LiveProgramGuide?>> _pending =
      <String, Future<LiveProgramGuide?>>{};

  Future<LiveProgramGuide?> loadXtreamNowNext(
    String playlistUrl,
    Channel channel,
  ) async {
    final source = playlistUrl.trim();
    if (source.isEmpty) return null;
    final streamId = _streamIdFromChannel(channel);
    if (streamId == null) return null;

    final key = '$source|$streamId';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.savedAt) < _cacheFreshFor) {
      return cached.guide;
    }

    final existing = _pending[key];
    if (existing != null) return existing;

    final future = _fetchXtream(source, streamId);
    _pending[key] = future;
    try {
      final guide = await future;
      _remember(key, guide);
      return guide;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  Future<LiveProgramGuide?> _fetchXtream(
    String playlistUrl,
    String streamId,
  ) async {
    try {
      final connection = await XtreamFastCatalogService.instance
          .connectionForPlaylist(playlistUrl);
      final uri = _endpoint(
        connection.apiServer,
        username: connection.username,
        password: connection.password,
        streamId: streamId,
      );
      final http.Client client = XtreamHttpClient.instance;
      final response = await client
          .get(uri, headers: XtreamHttpClient.jsonHeaders)
          .timeout(_timeout);
      if (response.statusCode != 200 || response.body.isEmpty) return null;
      final decoded = jsonDecode(response.body);
      return parseXtreamEpgPayload(decoded);
    } catch (_) {
      return null;
    }
  }

  Uri _endpoint(
    Uri apiServer, {
    required String username,
    required String password,
    required String streamId,
  }) {
    var prefix = apiServer.path;
    if (prefix.endsWith('/')) prefix = prefix.substring(0, prefix.length - 1);
    final path = prefix.isEmpty ? '/player_api.php' : '$prefix/player_api.php';
    return apiServer.replace(
      path: path,
      queryParameters: <String, String>{
        'username': username,
        'password': password,
        'action': 'get_short_epg',
        'stream_id': streamId,
        'limit': '2',
      },
      fragment: '',
    );
  }

  String? _streamIdFromChannel(Channel channel) {
    final uri = Uri.tryParse(channel.url.trim());
    if (uri == null || uri.pathSegments.isEmpty) return null;
    for (final segment in uri.pathSegments.reversed) {
      final match = RegExp(r'^(\d+)(?:\.[A-Za-z0-9]+)?$').firstMatch(segment);
      if (match != null) return match.group(1);
    }
    return null;
  }

  void _remember(String key, LiveProgramGuide? guide) {
    _cache.remove(key);
    _cache[key] = _LiveEpgCacheEntry(guide: guide, savedAt: DateTime.now());
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
}

LiveProgramGuide? parseXtreamEpgPayload(
  Object? decoded, {
  DateTime? clock,
}) {
  Object? rawListings = decoded;
  if (decoded is Map) {
    rawListings = decoded['epg_listings'] ?? decoded['listings'];
  }
  if (rawListings is! List || rawListings.isEmpty) return null;

  final programs = <LiveProgram>[];
  for (final raw in rawListings) {
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    final title = _decodeXtreamText(item['title'] ?? item['name']);
    if (title.isEmpty) continue;
    programs.add(
      LiveProgram(
        title: title,
        description: _nullableText(
          _decodeXtreamText(item['description'] ?? item['desc']),
        ),
        start: _readProgramTime(
          item,
          const <String>['start_timestamp', 'start', 'start_time'],
        ),
        end: _readProgramTime(
          item,
          const <String>['stop_timestamp', 'end_timestamp', 'stop', 'end'],
        ),
      ),
    );
  }
  if (programs.isEmpty) return null;

  programs.sort((a, b) {
    final left = a.start;
    final right = b.start;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  });

  if (programs.every((item) => item.start == null && item.end == null)) {
    return LiveProgramGuide(
      now: programs.first,
      next: programs.length > 1 ? programs[1] : null,
    );
  }

  final nowTime = clock ?? DateTime.now();
  LiveProgram? current;
  for (final program in programs) {
    final start = program.start;
    final end = program.end;
    if (start == null || end == null) continue;
    if (!nowTime.isBefore(start) && nowTime.isBefore(end)) {
      current = program;
      break;
    }
  }

  LiveProgram? upcoming;
  if (current != null) {
    final currentIndex = programs.indexOf(current);
    for (var index = currentIndex + 1; index < programs.length; index++) {
      if (programs[index].title.isNotEmpty) {
        upcoming = programs[index];
        break;
      }
    }
  } else {
    for (final program in programs) {
      final start = program.start;
      if (start != null && start.isAfter(nowTime)) {
        upcoming = program;
        break;
      }
    }
  }

  final guide = LiveProgramGuide(now: current, next: upcoming);
  return guide.hasPrograms ? guide : null;
}

DateTime? _readProgramTime(Map<String, dynamic> item, List<String> keys) {
  for (final key in keys) {
    final raw = item[key];
    if (raw == null) continue;
    if (raw is num) {
      final value = raw.toInt();
      if (value <= 0) continue;
      final millis = value < 100000000000 ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    final text = raw.toString().trim();
    if (text.isEmpty || text == '0' || text == 'null') continue;
    final numeric = int.tryParse(text);
    if (numeric != null && numeric > 0) {
      final millis = numeric < 100000000000 ? numeric * 1000 : numeric;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed.toLocal();
  }
  return null;
}

String _decodeXtreamText(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty || value == 'null') return '';
  final compact = value.replaceAll(RegExp(r'\s+'), '');
  final looksEncoded = compact.length >= 8 &&
      RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(compact) &&
      (compact.contains('=') || compact.length >= 16);
  if (!looksEncoded) return value;
  try {
    final missingPadding = compact.length % 4;
    final padded = missingPadding == 0
        ? compact
        : compact.padRight(compact.length + (4 - missingPadding), '=');
    final decoded = utf8.decode(base64.decode(padded), allowMalformed: false).trim();
    if (decoded.isEmpty) return value;
    final printable = decoded.runes.where((rune) => rune >= 32 || rune == 10).length;
    if (printable * 100 < decoded.runes.length * 85) return value;
    return decoded;
  } catch (_) {
    return value;
  }
}

String? _nullableText(String value) => value.trim().isEmpty ? null : value.trim();

class _LiveEpgCacheEntry {
  final LiveProgramGuide? guide;
  final DateTime savedAt;

  const _LiveEpgCacheEntry({required this.guide, required this.savedAt});
}
'''

widget = r'''import 'dart:async';

import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../services/device_performance_service.dart';
import '../services/live_epg_service.dart';
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
  final LiveProgramGuideLoader? programGuideLoader;

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
    this.programGuideLoader,
  });

  @override
  State<TvLivePremiumCatalog> createState() => _TvLivePremiumCatalogState();
}

class _TvLivePremiumCatalogState extends State<TvLivePremiumCatalog> {
  Channel? _focusedChannel;
  LiveProgramGuide? _guide;
  Timer? _guideDebounce;
  int _guideGeneration = 0;
  bool _guideLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.channels.isNotEmpty && _focusedChannel == null) {
        _focusChannel(widget.channels.first);
      }
    });
  }

  @override
  void didUpdateWidget(covariant TvLivePremiumCatalog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focused = _focusedChannel;
    if (focused != null &&
        !widget.channels.any((item) => item.uniqueKey == focused.uniqueKey)) {
      if (widget.channels.isEmpty) {
        _guideDebounce?.cancel();
        _guideGeneration++;
        _focusedChannel = null;
        _guide = null;
        _guideLoading = false;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusChannel(widget.channels.first);
        });
      }
    } else if (!identical(oldWidget.programGuideLoader, widget.programGuideLoader) &&
        focused != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusChannel(focused, forceGuideRefresh: true);
      });
    }
  }

  @override
  void dispose() {
    _guideDebounce?.cancel();
    _guideGeneration++;
    super.dispose();
  }

  void _focusChannel(Channel channel, {bool forceGuideRefresh = false}) {
    final same = _focusedChannel?.uniqueKey == channel.uniqueKey;
    if (same && !forceGuideRefresh) return;

    _guideDebounce?.cancel();
    final generation = ++_guideGeneration;
    setState(() {
      _focusedChannel = channel;
      _guide = null;
      _guideLoading = false;
    });

    final loader = widget.programGuideLoader;
    if (loader == null) return;

    _guideDebounce = Timer(const Duration(milliseconds: 220), () async {
      if (!mounted || generation != _guideGeneration) return;
      setState(() => _guideLoading = true);
      LiveProgramGuide? result;
      try {
        result = await loader(channel);
      } catch (_) {
        result = null;
      }
      if (!mounted || generation != _guideGeneration) return;
      setState(() {
        _guide = result;
        _guideLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final hero = _focusedChannel ??
        (widget.channels.isNotEmpty ? widget.channels.first : null);

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
                              onFocus: () => _focusChannel(channel),
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
      height: 150,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xEC10192B), Color(0xEC070D17)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 11,
            child: Row(
              children: [
                Container(
                  width: 86,
                  height: 86,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: tvFullCyan.withValues(alpha: .28),
                    ),
                  ),
                  child: ChannelLogoImage(
                    channel: channel,
                    fit: BoxFit.contain,
                    cacheWidth: 172,
                    cacheHeight: 172,
                    priority: 110,
                    prefetchExtent: 0,
                    fallback: const Icon(
                      Icons.live_tv_rounded,
                      size: 38,
                      color: Colors.white54,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
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
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          const TvFullLiveBadge(compact: true),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        group == null || group.isEmpty
                            ? 'Señal en vivo'
                            : '$group · Señal en vivo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 35,
                        child: FilledButton.icon(
                          onPressed: () => widget.onPlay(channel),
                          icon: const Icon(Icons.play_arrow_rounded, size: 19),
                          label: const Text('Ver ahora'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            color: Colors.white.withValues(alpha: .10),
          ),
          Expanded(
            flex: 9,
            child: _ProgramGuidePanel(
              guide: _guide,
              loading: _guideLoading,
              enabled: widget.programGuideLoader != null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgramGuidePanel extends StatelessWidget {
  final LiveProgramGuide? guide;
  final bool loading;
  final bool enabled;

  const _ProgramGuidePanel({
    required this.guide,
    required this.loading,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final current = guide?.now;
    final next = guide?.next;
    if (!enabled) {
      return const _GuideFallback(message: 'Programación no disponible');
    }
    if (loading) {
      return const _GuideFallback(message: 'Consultando programación…');
    }
    if (current == null && next == null) {
      return const _GuideFallback(message: 'Programación no disponible');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'AHORA',
          style: TextStyle(
            color: tvFullCyan,
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            letterSpacing: .7,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          current?.title ?? 'Sin programa actual informado',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 3),
        Text(
          current == null ? 'Señal en vivo' : _formatRange(current),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 10.5),
        ),
        if ((current?.description ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            current!.description!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 9.5),
          ),
        ],
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DESPUÉS',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: .55,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                next == null
                    ? 'Sin próximo programa informado'
                    : '${next.title}  ·  ${_formatRange(next)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _formatRange(LiveProgram program) {
    final start = program.start;
    final end = program.end;
    if (start == null && end == null) return 'Horario no disponible';
    if (start == null) return 'Hasta ${_clock(end!)}';
    if (end == null) return 'Desde ${_clock(start)}';
    return '${_clock(start)} - ${_clock(end)}';
  }

  static String _clock(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _GuideFallback extends StatelessWidget {
  final String message;

  const _GuideFallback({required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'AHORA',
          style: TextStyle(
            color: tvFullCyan,
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            letterSpacing: .7,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'La señal se puede reproducir normalmente.',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white38, fontSize: 9.5),
        ),
      ],
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
                          if ((widget.channel.group ?? '')
                              .trim()
                              .isNotEmpty) ...[
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
'''

test = r'''import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/live_epg_service.dart';

void main() {
  test('Xtream short EPG maps current and next program', () {
    final now = DateTime.fromMillisecondsSinceEpoch(2000 * 1000);
    final payload = <String, dynamic>{
      'epg_listings': <Map<String, dynamic>>[
        <String, dynamic>{
          'title': base64.encode(utf8.encode('Partido en vivo')),
          'description': base64.encode(utf8.encode('Fecha principal')),
          'start_timestamp': '1900',
          'stop_timestamp': '2100',
        },
        <String, dynamic>{
          'title': 'Post partido',
          'start_timestamp': '2100',
          'stop_timestamp': '2200',
        },
      ],
    };

    final guide = parseXtreamEpgPayload(payload, clock: now);
    expect(guide, isNotNull);
    expect(guide!.now?.title, 'Partido en vivo');
    expect(guide.now?.description, 'Fecha principal');
    expect(guide.next?.title, 'Post partido');
  });

  test('Xtream short EPG gracefully handles missing data', () {
    expect(parseXtreamEpgPayload(<String, dynamic>{'epg_listings': []}), isNull);
    expect(parseXtreamEpgPayload(<String, dynamic>{}), isNull);
  });
}
'''

(ROOT / 'lib/services/live_epg_service.dart').write_text(service, encoding='utf-8')
(ROOT / 'lib/widgets/tv_live_premium_catalog.dart').write_text(widget, encoding='utf-8')
(ROOT / 'test/live_epg_service_test.dart').write_text(test, encoding='utf-8')

xtream_path = ROOT / 'lib/screens/xtream_live_screen.dart'
xtream = xtream_path.read_text(encoding='utf-8')
import_marker = "import '../services/device_performance_service.dart';\n"
import_line = "import '../services/live_epg_service.dart';\n"
if import_line not in xtream:
    if import_marker not in xtream:
        raise SystemExit('xtream import marker not found')
    xtream = xtream.replace(import_marker, import_marker + import_line, 1)

call_marker = "        onFavoriteToggle: provider.toggleFavorite,\n      );"
call_replacement = "        onFavoriteToggle: provider.toggleFavorite,\n        programGuideLoader: (channel) => LiveEpgService.instance\n            .loadXtreamNowNext(widget.playlist.source, channel),\n      );"
if 'programGuideLoader:' not in xtream:
    if call_marker not in xtream:
        raise SystemExit('Xtream premium catalog call marker not found')
    xtream = xtream.replace(call_marker, call_replacement, 1)
xtream_path.write_text(xtream, encoding='utf-8')

pubspec_path = ROOT / 'pubspec.yaml'
pubspec = pubspec_path.read_text(encoding='utf-8')
if 'version: 1.3.5+27' in pubspec:
    pubspec = pubspec.replace('version: 1.3.5+27', 'version: 1.3.6+28', 1)
elif 'version: 1.3.6+28' not in pubspec:
    raise SystemExit('Unexpected pubspec version')
marker = '# TV FULL PRO 1.3.6+28 live-focus-now-next-v28'
if marker not in pubspec:
    pubspec = pubspec.rstrip() + '\n\n' + marker + '\n'
pubspec_path.write_text(pubspec, encoding='utf-8')

print('Applied TV FULL PRO 1.3.6+28 focused LIVE hero + lazy Xtream now/next EPG')
