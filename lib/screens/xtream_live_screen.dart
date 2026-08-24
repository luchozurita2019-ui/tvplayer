import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../providers/iptv_provider.dart';
import '../services/artwork_cache_service.dart';
import '../services/section_catalog_service.dart';
import '../services/xtream_live_fast_service.dart';
import '../widgets/cached_artwork_image.dart';
import 'player_screen.dart';

class XtreamLiveScreen extends StatefulWidget {
  final Playlist playlist;
  const XtreamLiveScreen({super.key, required this.playlist});

  @override
  State<XtreamLiveScreen> createState() => _XtreamLiveScreenState();
}

class _XtreamLiveScreenState extends State<XtreamLiveScreen> {
  static const Duration _cacheFreshFor = Duration(minutes: 3);

  late Future<_LiveData> _future;
  String? _category;
  String _status = 'Cargando TV en vivo…';

  @override
  void initState() {
    super.initState();
    unawaited(ArtworkCacheService.instance.switchProvider(widget.playlist.id));
    _future = _loadInitial();
  }

  @override
  void dispose() {
    unawaited(ArtworkCacheService.instance.clearBrowsingSession());
    super.dispose();
  }

  Future<_LiveData> _loadInitial() async {
    if (widget.playlist.sourceType == PlaylistSourceType.xtream) {
      final service = XtreamLiveFastService.instance;
      final cached = await service.loadCached(widget.playlist.source);
      if (cached != null && cached.channels.isNotEmpty) {
        final channels = _normalizeXtreamChannels(cached.channels);
        if (DateTime.now().difference(cached.savedAt) >= _cacheFreshFor) {
          unawaited(_refreshXtream());
        }
        return _LiveData(channels);
      }
      final fresh = await service.refresh(
        widget.playlist.source,
        onProgress: (p) => _setStatus(p.label),
      );
      return _LiveData(_normalizeXtreamChannels(fresh.channels));
    }

    final service = SectionCatalogService.instance;
    final cached = await service.loadCached(
      widget.playlist,
      TvSectionKind.live,
    );
    if (cached != null && cached.channels.isNotEmpty) {
      unawaited(_refreshM3u());
      return _LiveData(cached.channels);
    }
    final fresh = await service.loadOrRefresh(
      widget.playlist,
      TvSectionKind.live,
    );
    return _LiveData(fresh.channels);
  }

  Future<void> _refreshXtream() async {
    try {
      final fresh = await XtreamLiveFastService.instance.refresh(
        widget.playlist.source,
        onProgress: (p) => _setStatus(p.label),
      );
      if (!mounted) return;
      setState(
        () => _future = Future.value(
          _LiveData(_normalizeXtreamChannels(fresh.channels)),
        ),
      );
    } catch (_) {}
  }

  Future<void> _refreshM3u() async {
    try {
      final all = await SectionCatalogService.instance.refreshIfStale(
        widget.playlist,
      );
      if (all == null) return;
      final fresh = all[TvSectionKind.live];
      if (!mounted || fresh == null || fresh.channels.isEmpty) return;
      setState(() => _future = Future.value(_LiveData(fresh.channels)));
    } catch (_) {}
  }

  List<Channel> _normalizeXtreamChannels(List<Channel> channels) {
    final base = _xtreamBaseUri(widget.playlist.source);
    if (base == null) return channels;
    return channels
        .map(
          (channel) => Channel(
            name: channel.name,
            url: channel.url,
            logoUrl: _resolveArtwork(base, channel.logoUrl),
            group: channel.group,
            tvgId: channel.tvgId,
            httpUserAgent: channel.httpUserAgent,
            httpReferrer: channel.httpReferrer,
            httpHeaders: channel.httpHeaders,
          ),
        )
        .toList(growable: false);
  }

  Uri? _xtreamBaseUri(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return null;
    var path = uri.path;
    final lower = path.toLowerCase();
    for (final suffix in ['/get.php', '/player_api.php']) {
      if (lower.endsWith(suffix)) {
        path = path.substring(0, path.length - suffix.length);
        break;
      }
    }
    if (path.isEmpty) path = '/';
    return uri.replace(path: path, query: '', fragment: '');
  }

  String? _resolveArtwork(Uri base, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty || value.toLowerCase() == 'null' || value == '0')
      return null;
    if (value.startsWith('//')) return '${base.scheme}:$value';
    final parsed = Uri.tryParse(value);
    if (parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty) return parsed.toString();
    return base.resolve(value).toString();
  }

  void _setStatus(String value) {
    if (!mounted || value == _status) return;
    setState(() => _status = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05090F),
      appBar: AppBar(
        titleSpacing: 24,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TV EN VIVO',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              widget.playlist.name,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
      body: FutureBuilder<_LiveData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _Loading(message: _status);
          }
          if (snapshot.hasError) {
            return _ErrorView(
              message: 'No se pudo cargar la TV en vivo.',
              onRetry: () => setState(() => _future = _loadInitial()),
            );
          }
          final data = snapshot.data!;
          if (data.channels.isEmpty) {
            return _ErrorView(
              message: 'Esta lista no contiene canales de TV en vivo.',
              onRetry: () => setState(() => _future = _loadInitial()),
            );
          }
          return _buildCatalog(data);
        },
      ),
    );
  }

  Widget _buildCatalog(_LiveData data) {
    final categories = data.categories;
    final visible = _category == null
        ? data.channels
        : data.channels
            .where((item) => item.group == _category)
            .toList(growable: false);

    return Row(
      children: [
        SizedBox(
          width: 260,
          child: ColoredBox(
            color: const Color(0xFF08111B),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
              itemCount: categories.length + 1,
              itemBuilder: (context, index) {
                final category = index == 0 ? null : categories[index - 1];
                final selected = category == _category;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: ListTile(
                    autofocus: index == 0,
                    selected: selected,
                    minTileHeight: 50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                    selectedTileColor:
                        const Color(0xFF1677FF).withValues(alpha: .18),
                    title: Text(
                      category ?? 'Todos',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    onTap: () => setState(() => _category = category),
                  ),
                );
              },
            ),
          ),
        ),
        Container(width: 1, color: Colors.white10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                child: Text(
                  '${_category ?? 'Todos'}  ·  ${visible.length} canales',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 0, 24, 24),
                  scrollCacheExtent: const ScrollCacheExtent.pixels(80),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final channel = visible[index];
                    return _ChannelRow(
                      channel: channel,
                      autofocus: index == 0,
                      onTap: () => _openPlayer(visible, index),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openPlayer(List<Channel> channels, int index) async {
    final provider = context.read<IptvProvider>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          channel: channels[index],
          playlist: channels,
          initialIndex: index,
          settings: provider.playbackSettings,
          isLiveContent: true,
        ),
      ),
    );
  }
}

class _ChannelRow extends StatefulWidget {
  final Channel channel;
  final bool autofocus;
  final VoidCallback onTap;
  const _ChannelRow({
    required this.channel,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<_ChannelRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: _focused ? const Color(0xFF10283B) : const Color(0xFF0A141E),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(10),
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onTap,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                const SizedBox(width: 12),
                SizedBox(
                  width: 42,
                  height: 42,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedArtworkImage(
                      url: widget.channel.logoUrl,
                      fit: BoxFit.contain,
                      cacheWidth: 84,
                      cacheHeight: 84,
                      prefetchExtent: 0,
                      fallback: Container(
                        alignment: Alignment.center,
                        color: Colors.white.withValues(alpha: .04),
                        child: Text(
                          _initials(widget.channel.name),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if ((widget.channel.group ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: Text(
                      widget.channel.group!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String value) {
    final words =
        value.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).take(2);
    final text = words.map((e) => e.substring(0, 1).toUpperCase()).join();
    return text.isEmpty ? 'TV' : text;
  }
}

class _LiveData {
  final List<Channel> channels;
  const _LiveData(this.channels);

  List<String> get categories {
    final seen = <String>{};
    final values = <String>[];
    for (final channel in channels) {
      final group = channel.group?.trim();
      if (group == null || group.isEmpty) continue;
      if (seen.add(group)) values.add(group);
    }
    return values;
  }
}

class _Loading extends StatelessWidget {
  final String message;
  const _Loading({required this.message});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 14),
            Text(message, style: const TextStyle(color: Colors.white60)),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tv_off_outlined, size: 44, color: Colors.white38),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      );
}
