import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../providers/iptv_provider.dart';
import '../services/parental_control_service.dart';
import '../services/section_catalog_service.dart';
import '../services/xtream_live_fast_service.dart';
import '../widgets/channel_logo_image.dart';
import 'player_screen.dart';

class FilteredLiveScreen extends StatefulWidget {
  final Playlist playlist;
  final String title;
  final List<String> keywords;
  final IconData icon;
  final bool requireParentalUnlock;

  const FilteredLiveScreen({
    super.key,
    required this.playlist,
    required this.title,
    required this.keywords,
    required this.icon,
    this.requireParentalUnlock = false,
  });

  @override
  State<FilteredLiveScreen> createState() => _FilteredLiveScreenState();
}

class _FilteredLiveScreenState extends State<FilteredLiveScreen> {
  final ParentalControlService _parental = ParentalControlService.instance;
  late Future<List<Channel>> _future;
  List<Channel> _allChannels = const <Channel>[];
  bool _openingPlayer = false;

  @override
  void initState() {
    super.initState();
    _parental.addListener(_refreshVisibility);
    _future = _load();
  }

  @override
  void dispose() {
    _parental.removeListener(_refreshVisibility);
    super.dispose();
  }

  void _refreshVisibility() {
    if (!mounted) return;
    if (widget.requireParentalUnlock && _parental.isLocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return;
    }
    final all = _allChannels;
    setState(() {
      if (all.isNotEmpty) _future = Future.value(_filtered(all));
    });
  }

  Future<List<Channel>> _load() async {
    await _parental.init();
    List<Channel> channels;
    if (widget.playlist.sourceType == PlaylistSourceType.xtream) {
      final service = XtreamLiveFastService.instance;
      final cached = await service.loadCached(widget.playlist.source);
      if (cached != null && cached.channels.isNotEmpty) {
        channels = cached.channels;
        unawaited(_refreshXtream());
      } else {
        final fresh = await service.refresh(widget.playlist.source);
        channels = fresh.channels;
      }
    } else {
      final service = SectionCatalogService.instance;
      final cached = await service.loadCached(
        widget.playlist,
        TvSectionKind.live,
      );
      if (cached != null && cached.channels.isNotEmpty) {
        channels = cached.channels;
        unawaited(service.refreshIfStale(
          widget.playlist,
          kind: TvSectionKind.live,
        ));
      } else {
        final fresh = await service.loadOrRefresh(
          widget.playlist,
          TvSectionKind.live,
        );
        channels = fresh.channels;
      }
    }
    _allChannels = List<Channel>.unmodifiable(channels);
    return _filtered(_allChannels);
  }

  Future<void> _refreshXtream() async {
    try {
      final fresh = await XtreamLiveFastService.instance.refresh(
        widget.playlist.source,
      );
      if (!mounted || fresh.channels.isEmpty) return;
      _allChannels = List<Channel>.unmodifiable(fresh.channels);
      final visible = _filtered(_allChannels);
      setState(() => _future = Future.value(visible));
    } catch (_) {}
  }

  List<Channel> _filtered(Iterable<Channel> channels) {
    final keywords = widget.keywords
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    final result = <Channel>[];
    for (final channel in channels) {
      if (!_parental.canShowChannel(channel)) continue;
      final haystack = '${channel.group ?? ''} ${channel.name}'.toLowerCase();
      if (keywords.any(haystack.contains)) result.add(channel);
    }
    return List<Channel>.unmodifiable(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08111C),
        surfaceTintColor: Colors.transparent,
        titleSpacing: 8,
        title: Row(
          children: [
            Icon(widget.icon, color: const Color(0xFF54D7FF), size: 22),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  widget.playlist.name,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<Channel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              snapshot.data == null) {
            return const _Loading();
          }
          if (snapshot.hasError && snapshot.data == null) {
            return _Message(
              icon: Icons.wifi_off_rounded,
              title: 'No se pudo cargar el contenido',
              subtitle: 'Revisá la conexión e intentá nuevamente.',
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final channels = snapshot.data ?? const <Channel>[];
          if (channels.isEmpty) {
            return _Message(
              icon: Icons.search_off_rounded,
              title: 'No hay contenido disponible',
              subtitle:
                  'Esta lista no contiene canales que correspondan a ${widget.title.toLowerCase()}.',
              onRetry: () => setState(() => _future = _load()),
            );
          }
          return _ChannelList(
            channels: channels,
            onOpen: (index) => unawaited(_openPlayer(channels, index)),
          );
        },
      ),
    );
  }

  Future<void> _openPlayer(List<Channel> channels, int index) async {
    if (_openingPlayer || index < 0 || index >= channels.length) return;
    if (widget.requireParentalUnlock && _parental.isLocked) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    _openingPlayer = true;
    try {
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
    } finally {
      _openingPlayer = false;
    }
  }
}

class _ChannelList extends StatelessWidget {
  final List<Channel> channels;
  final ValueChanged<int> onOpen;

  const _ChannelList({required this.channels, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
      itemCount: channels.length,
      itemBuilder: (context, index) => _ChannelTile(
        channel: channels[index],
        autofocus: index == 0,
        onPressed: () => onOpen(index),
      ),
    );
  }
}

class _ChannelTile extends StatefulWidget {
  final Channel channel;
  final bool autofocus;
  final VoidCallback onPressed;

  const _ChannelTile({
    required this.channel,
    required this.autofocus,
    required this.onPressed,
  });

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _focused ? const Color(0xFF11243A) : const Color(0xB30A1422),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused
              ? const Color(0xFF54D7FF)
              : Colors.white.withValues(alpha: .06),
          width: _focused ? 1.7 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: widget.autofocus,
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onPressed,
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                const SizedBox(width: 12),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: ChannelLogoImage(
                    channel: widget.channel,
                    fit: BoxFit.contain,
                    cacheWidth: 96,
                    cacheHeight: 96,
                    priority: _focused ? 10 : 1,
                    fallback: const Center(
                      child: Icon(
                        Icons.live_tv_rounded,
                        color: Colors.white30,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if ((widget.channel.group ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          widget.channel.group!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.play_arrow_rounded,
                  color: _focused ? const Color(0xFF54D7FF) : Colors.white24,
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF54D7FF),
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Cargando canales…',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 46, color: Colors.white30),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                autofocus: true,
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
