import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../services/artwork_cache_service.dart';
import '../services/content_classifier.dart';
import 'channel_list_screen.dart';
import 'xtream_live_screen.dart';
import 'xtream_movies_screen.dart';
import 'xtream_series_screen.dart';

const _tvBlue = Color(0xFF1677FF);
const _tvBlueBright = Color(0xFF2D92FF);
const _tvBackground = Color(0xFF060B12);
const _tvPanel = Color(0xFF0C1725);
const _tvPanelFocus = Color(0xFF10243B);
const _tvBorder = Color(0xFF203149);
const _tvText = Color(0xFFF5F8FC);
const _tvMuted = Color(0xFF8D9CAF);

class SourceContentScreen extends StatefulWidget {
  final Playlist playlist;

  const SourceContentScreen({super.key, required this.playlist});

  @override
  State<SourceContentScreen> createState() => _SourceContentScreenState();
}

class _SourceContentScreenState extends State<SourceContentScreen> {
  late ContentBuckets _buckets;

  Playlist get playlist => widget.playlist;

  @override
  void initState() {
    super.initState();
    _buckets = ContentClassifier.partition(widget.playlist.channels);
  }

  @override
  void didUpdateWidget(covariant SourceContentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.playlist.channels, widget.playlist.channels) ||
        oldWidget.playlist.lastUpdated != widget.playlist.lastUpdated) {
      _buckets = ContentClassifier.partition(widget.playlist.channels);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nativeXtream = playlist.sourceType == PlaylistSourceType.xtream;

    final entries = <_ContentEntry>[
      _ContentEntry(
        icon: Icons.live_tv_rounded,
        title: 'TV en vivo',
        count: _buckets.count(IptvContentKind.live),
        subtitle: nativeXtream ? 'TV Xtream nativa' : null,
        enabledOverride: nativeXtream ? true : null,
        kind: IptvContentKind.live,
      ),
      _ContentEntry(
        icon: Icons.movie_creation_rounded,
        title: 'Películas',
        count: _buckets.count(IptvContentKind.movies),
        subtitle: nativeXtream ? 'Catálogo Xtream' : null,
        enabledOverride: nativeXtream ? true : null,
        kind: IptvContentKind.movies,
      ),
      _ContentEntry(
        icon: Icons.video_library_rounded,
        title: 'Series',
        count: _buckets.count(IptvContentKind.series),
        subtitle: nativeXtream ? 'Catálogo Xtream' : null,
        enabledOverride: nativeXtream ? true : null,
        kind: IptvContentKind.series,
      ),
      _ContentEntry(
        icon: Icons.radio_rounded,
        title: 'Radios',
        count: _buckets.count(IptvContentKind.radios),
        kind: IptvContentKind.radios,
      ),
    ];

    return Scaffold(
      backgroundColor: _tvBackground,
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: const Color(0xFF08111D),
        foregroundColor: _tvText,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 8,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 33,
              decoration: BoxDecoration(
                color: _tvBlue,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 25,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TV FULL PRO',
                    style: TextStyle(
                      color: _tvText,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _tvMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fourColumns = constraints.maxWidth >= 1000;
            final columns = fourColumns ? 4 : 2;
            final horizontal = constraints.maxWidth >= 1400 ? 48.0 : 28.0;
            final vertical = constraints.maxHeight >= 700 ? 34.0 : 22.0;

            return Padding(
              padding: EdgeInsets.fromLTRB(horizontal, vertical, horizontal, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Elegí qué querés ver',
                    style: TextStyle(
                      color: _tvText,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Contenido organizado para navegar rápido con el control remoto.',
                    style: TextStyle(color: _tvMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: GridView.builder(
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: fourColumns ? 1.25 : 2.15,
                      ),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _ContentCard(
                          icon: entry.icon,
                          title: entry.title,
                          count: entry.count,
                          subtitleOverride: entry.subtitle,
                          enabledOverride: entry.enabledOverride,
                          autofocus: index == 0,
                          onTap: () => _openKind(context, entry.kind),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _openKind(BuildContext context, IptvContentKind kind) {
    // Mantener exactamente la lógica estable: sólo limpiamos artwork temporal
    // antes de entrar a una nueva sección.
    ArtworkCacheService.instance.clearBrowsingSession();
    if (playlist.sourceType == PlaylistSourceType.xtream) {
      if (kind == IptvContentKind.live) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => XtreamLiveScreen(playlist: playlist),
          ),
        );
        return;
      }
      if (kind == IptvContentKind.movies) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => XtreamMoviesScreen(playlist: playlist),
          ),
        );
        return;
      }
      if (kind == IptvContentKind.series) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => XtreamSeriesScreen(playlist: playlist),
          ),
        );
        return;
      }
    }

    final channels = _buckets.forKind(kind);
    if (channels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No hay ${kind.label.toLowerCase()} en esta lista.'),
        ),
      );
      return;
    }

    final filtered = Playlist(
      id: '${playlist.id}::${kind.name}',
      name: '${playlist.name} · ${kind.label}',
      source: playlist.source,
      isRemote: false,
      channels: channels,
      lastUpdated: playlist.lastUpdated,
      sourceType: playlist.sourceType,
    );

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChannelListScreen(playlist: filtered)),
    );
  }
}

class _ContentEntry {
  final IconData icon;
  final String title;
  final int count;
  final String? subtitle;
  final bool? enabledOverride;
  final IptvContentKind kind;

  const _ContentEntry({
    required this.icon,
    required this.title,
    required this.count,
    required this.kind,
    this.subtitle,
    this.enabledOverride,
  });
}

class _ContentCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final int count;
  final String? subtitleOverride;
  final bool? enabledOverride;
  final VoidCallback onTap;
  final bool autofocus;

  const _ContentCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.onTap,
    this.subtitleOverride,
    this.enabledOverride,
    this.autofocus = false,
  });

  @override
  State<_ContentCard> createState() => _ContentCardState();
}

class _ContentCardState extends State<_ContentCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabledOverride ?? widget.count > 0;
    final subtitle = widget.subtitleOverride ??
        (widget.count == 1 ? '1 elemento' : '${widget.count} elementos');

    return RepaintBoundary(
      child: Material(
        color: _focused && enabled ? _tvPanelFocus : _tvPanel,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          autofocus: widget.autofocus,
          canRequestFocus: enabled,
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: enabled ? widget.onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _focused && enabled ? _tvBlueBright : _tvBorder,
                width: _focused ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 66,
                  height: 54,
                  decoration: BoxDecoration(
                    color: enabled
                        ? _tvBlue.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 31,
                    color: enabled ? _tvBlueBright : Colors.white24,
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: enabled ? _tvText : Colors.white30,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: enabled ? _tvMuted : Colors.white24,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
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
