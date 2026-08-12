import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../services/artwork_cache_service.dart';
import '../services/content_classifier.dart';
import 'channel_list_screen.dart';
import 'xtream_live_screen.dart';
import 'xtream_movies_screen.dart';
import 'xtream_series_screen.dart';

const bool _androidTvBuild = bool.fromEnvironment('TV_FULL_ANDROID_TV');

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

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TV FULL',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = _androidTvBuild || constraints.maxWidth >= 900;
          final columns = _androidTvBuild
              ? (constraints.maxWidth >= 1500 ? 4 : 2)
              : constraints.maxWidth >= 1250
              ? 4
              : constraints.maxWidth >= 760
              ? 2
              : 1;

          return ListView(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 48 : 18,
              vertical: wide ? 34 : 20,
            ),
            children: [
              Text(
                '¿Qué querés ver?',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Contenido organizado automáticamente por TV FULL.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 28),
              GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
                childAspectRatio: columns == 1 ? 2.55 : 1.35,
                children: [
                  _ContentCard(
                    autofocus: _androidTvBuild,
                    icon: Icons.live_tv_rounded,
                    title: 'TV en vivo',
                    count: _buckets.count(IptvContentKind.live),
                    subtitleOverride: nativeXtream
                        ? 'TV Xtream nativa rápida'
                        : null,
                    enabledOverride: nativeXtream ? true : null,
                    accent: const Color(0xFF1677FF),
                    onTap: () => _openKind(context, IptvContentKind.live),
                  ),
                  _ContentCard(
                    icon: Icons.movie_creation_rounded,
                    title: 'Películas',
                    count: _buckets.count(IptvContentKind.movies),
                    subtitleOverride: nativeXtream
                        ? 'Catálogo Xtream con fichas'
                        : null,
                    enabledOverride: nativeXtream ? true : null,
                    accent: const Color(0xFF4C9DFF),
                    onTap: () => _openKind(context, IptvContentKind.movies),
                  ),
                  _ContentCard(
                    icon: Icons.video_library_rounded,
                    title: 'Series',
                    count: _buckets.count(IptvContentKind.series),
                    subtitleOverride: nativeXtream
                        ? 'Catálogo Xtream nativo'
                        : null,
                    enabledOverride: nativeXtream ? true : null,
                    accent: const Color(0xFF2D6DFF),
                    onTap: () => _openKind(context, IptvContentKind.series),
                  ),
                  _ContentCard(
                    icon: Icons.radio_rounded,
                    title: 'Radios',
                    count: _buckets.count(IptvContentKind.radios),
                    accent: const Color(0xFF5DB7FF),
                    onTap: () => _openKind(context, IptvContentKind.radios),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          nativeXtream
                              ? 'En fuentes Xtream, TV en vivo usa get_live_categories/get_live_streams con carga nativa rápida. Películas usa get_vod_streams/get_vod_info para fichas y reproducción. Series usa get_series/get_series_info y organiza temporadas y episodios.'
                              : 'TV FULL mantiene en TV en vivo los canales lineales aunque su categoría se llame Películas, Cine o Series. Sólo separa VOD/Series cuando la estructura del stream lo identifica como tal.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openKind(BuildContext context, IptvContentKind kind) {
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

class _ContentCard extends StatelessWidget {
  final bool autofocus;
  final IconData icon;
  final String title;
  final int count;
  final String? subtitleOverride;
  final bool? enabledOverride;
  final Color accent;
  final VoidCallback onTap;

  const _ContentCard({
    this.autofocus = false,
    required this.icon,
    required this.title,
    required this.count,
    this.subtitleOverride,
    this.enabledOverride,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = enabledOverride ?? count > 0;
    final subtitle =
        subtitleOverride ?? (count == 1 ? '1 elemento' : '$count elementos');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        autofocus: enabled && autofocus,
        focusColor: accent.withValues(alpha: 0.30),
        onFocusChange: (focused) {
          if (focused && _androidTvBuild) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Scrollable.ensureVisible(
                  context,
                  duration: const Duration(milliseconds: 160),
                  alignment: 0.4,
                );
              }
            });
          }
        },
        onTap: enabled ? onTap : null,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: enabled ? 0.24 : 0.08),
                Theme.of(context).colorScheme.surfaceContainerHigh,
              ],
            ),
          ),
          padding: const EdgeInsets.all(18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = !_androidTvBuild && constraints.maxWidth < 620;
              final iconWidget = Container(
                width: compact ? 58 : 72,
                height: compact ? 58 : 72,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: enabled ? 0.22 : 0.08),
                  borderRadius: BorderRadius.circular(compact ? 16 : 20),
                  border: Border.all(
                    color: accent.withValues(alpha: enabled ? 0.40 : 0.10),
                  ),
                ),
                child: Icon(
                  icon,
                  size: compact ? 34 : 42,
                  color: enabled ? Colors.white : Colors.white30,
                ),
              );

              final labels = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: compact
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: compact ? TextAlign.left : TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: enabled ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 20 : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: compact ? TextAlign.left : TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: enabled ? Colors.white70 : Colors.white30,
                    ),
                  ),
                ],
              );

              if (compact) {
                return Row(
                  children: [
                    iconWidget,
                    const SizedBox(width: 16),
                    Expanded(child: labels),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: enabled ? Colors.white54 : Colors.white12,
                    ),
                  ],
                );
              }

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [iconWidget, const SizedBox(height: 14), labels],
              );
            },
          ),
        ),
      ),
    );
  }
}
