import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../providers/iptv_provider.dart';
import '../services/artwork_cache_service.dart';
import '../services/remote_access_guard.dart';
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
        if (DateTime.now().difference(cached.savedAt) >= _cacheFreshFor) {
          unawaited(_refreshXtream());
        }
        return _LiveData(cached.channels, categories: cached.categories);
      }

      final fresh = await service.refresh(
        widget.playlist.source,
        onProgress: (p) => _setStatus(p.label),
      );
      if (fresh.channels.isEmpty) {
        throw const FormatException('Xtream no devolvió canales LIVE válidos.');
      }
      return _LiveData(fresh.channels, categories: fresh.categories);
    }

    return _loadM3uFallback();
  }

  Future<_LiveData> _loadM3uFallback() async {
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
      if (!mounted || fresh.channels.isEmpty) return;
      setState(
        () => _future = Future.value(
          _LiveData(fresh.channels, categories: fresh.categories),
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

  void _setStatus(String value) {
    if (!mounted || value == _status) return;
    setState(() => _status = value);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final blocked = remoteAccessBlockMessage(provider);
    if (blocked != null) {
      return _BlockedCatalog(message: blocked);
    }

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
          width: 220,
          child: ColoredBox(
            color: const Color(0xFF08111B),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
              itemCount: categories.length + 1,
              itemBuilder: (context, index) {
                final category = index == 0 ? null : categories[index - 1];
                final selected = category == _category;
                return _CategoryRow(
                  label: category ?? 'Todos',
                  selected: selected,
                  autofocus: index == 0,
                  onTap: () => setState(() => _category = category),
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  '${_category ?? 'Todos'}  ·  ${visible.length} canales',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 0, 20, 20),
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

class _CategoryRow extends StatefulWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  const _CategoryRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _focused || widget.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: highlighted ? const Color(0xFF12324A) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(9),
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: _focused ? const Color(0xFF58B9FF) : Colors.transparent,
              ),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
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
            height: 58,
            child: Row(
              children: [
                const SizedBox(width: 10),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedArtworkImage(
                      url: widget.channel.logoUrl,
                      fit: BoxFit.contain,
                      cacheWidth: 80,
                      cacheHeight: 80,
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
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if ((widget.channel.group ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      widget.channel.group!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
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
  final List<String> _storedCategories;

  const _LiveData(
    this.channels, {
    List<String> categories = const <String>[],
  }) : _storedCategories = categories;

  List<String> get categories {
    if (_storedCategories.isNotEmpty) return _storedCategories;
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

class _BlockedCatalog extends StatelessWidget {
  final String message;
  const _BlockedCatalog({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05090F),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 46),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}
