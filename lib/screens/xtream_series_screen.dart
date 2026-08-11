import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../providers/iptv_provider.dart';
import '../services/xtream_series_service.dart';
import '../services/xtream_service.dart';
import '../widgets/cached_artwork_image.dart';
import 'player_screen.dart';

class XtreamSeriesScreen extends StatefulWidget {
  final Playlist playlist;

  const XtreamSeriesScreen({super.key, required this.playlist});

  @override
  State<XtreamSeriesScreen> createState() => _XtreamSeriesScreenState();
}

class _XtreamSeriesScreenState extends State<XtreamSeriesScreen> {
  late Future<_SeriesCatalogData> _future;
  String _query = '';
  String? _category;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SeriesCatalogData> _load() async {
    final connection =
        await XtreamService.reconnectFromPlaylistUrl(widget.playlist.source);
    final series = await XtreamSeriesService.fetchCatalog(connection);
    return _SeriesCatalogData(connection: connection, series: series);
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Series', style: TextStyle(fontWeight: FontWeight.w900)),
            Text(
              widget.playlist.name,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: FutureBuilder<_SeriesCatalogData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Cargando catálogo de series por Xtream…'),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return _SeriesError(
              message: snapshot.error.toString().replaceFirst('Exception: ', ''),
              onRetry: _retry,
            );
          }
          final data = snapshot.data!;
          if (data.series.isEmpty) {
            return _SeriesError(
              message:
                  'El servidor Xtream no devolvió series mediante get_series.',
              onRetry: _retry,
            );
          }
          return _buildCatalog(context, data);
        },
      ),
    );
  }

  Widget _buildCatalog(BuildContext context, _SeriesCatalogData data) {
    final categories = data.series
        .map((item) => item.category)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final normalized = _query.trim().toLowerCase();
    final visible = data.series.where((item) {
      if (_category != null && item.category != _category) return false;
      if (normalized.isEmpty) return true;
      return item.name.toLowerCase().contains(normalized) ||
          (item.genre?.toLowerCase().contains(normalized) ?? false) ||
          (item.category?.toLowerCase().contains(normalized) ?? false);
    }).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1500
            ? 7
            : width >= 1200
                ? 6
                : width >= 950
                    ? 5
                    : width >= 700
                        ? 4
                        : width >= 480
                            ? 3
                            : 2;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Buscar serie, género o categoría…',
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  if (categories.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: const Text('Todas'),
                              selected: _category == null,
                              onSelected: (_) => setState(() => _category = null),
                            ),
                          ),
                          ...categories.map(
                            (category) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(category),
                                selected: _category == category,
                                onSelected: (_) =>
                                    setState(() => _category = category),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '${visible.length} series',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const Spacer(),
                  const Text(
                    'Catálogo Xtream nativo',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('No hay resultados.'))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.62,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final series = visible[index];
                        return _SeriesPosterCard(
                          series: series,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => XtreamSeriesDetailScreen(
                                connection: data.connection,
                                summary: series,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class XtreamSeriesDetailScreen extends StatefulWidget {
  final XtreamConnectionResult connection;
  final XtreamSeriesSummary summary;

  const XtreamSeriesDetailScreen({
    super.key,
    required this.connection,
    required this.summary,
  });

  @override
  State<XtreamSeriesDetailScreen> createState() =>
      _XtreamSeriesDetailScreenState();
}

class _XtreamSeriesDetailScreenState extends State<XtreamSeriesDetailScreen> {
  late Future<XtreamSeriesDetails> _future;
  int? _selectedSeason;

  @override
  void initState() {
    super.initState();
    _future = XtreamSeriesService.fetchDetails(
      widget.connection,
      widget.summary,
    );
  }

  void _retry() => setState(() {
        _future = XtreamSeriesService.fetchDetails(
          widget.connection,
          widget.summary,
        );
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.summary.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: FutureBuilder<XtreamSeriesDetails>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Cargando temporadas y episodios…'),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return _SeriesError(
              message: snapshot.error.toString().replaceFirst('Exception: ', ''),
              onRetry: _retry,
            );
          }
          final details = snapshot.data!;
          final seasons = details.seasonNumbers;
          final season = _selectedSeason != null && seasons.contains(_selectedSeason)
              ? _selectedSeason!
              : seasons.first;
          final episodes = details.seasons[season] ?? const <XtreamSeriesEpisode>[];
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 980) {
                return _buildWide(details, season, episodes);
              }
              return _buildCompact(details, season, episodes);
            },
          );
        },
      ),
    );
  }

  Widget _buildWide(
    XtreamSeriesDetails details,
    int season,
    List<XtreamSeriesEpisode> episodes,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 285,
            child: Column(
              children: [
                Expanded(
                  flex: 5,
                  child: _Poster(series: details.series),
                ),
                const SizedBox(height: 12),
                Expanded(
                  flex: 4,
                  child: _SeasonList(
                    details: details,
                    selectedSeason: season,
                    onSelected: (value) =>
                        setState(() => _selectedSeason = value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 5,
            child: _EpisodePanel(
              series: details.series,
              season: season,
              episodes: episodes,
              onPlay: (episode) => _play(details, season, episode),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 6,
            child: _SeriesInfoPanel(
              details: details,
              season: season,
              episodes: episodes,
              onPlayFirst: episodes.isEmpty
                  ? null
                  : () => _play(details, season, episodes.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(
    XtreamSeriesDetails details,
    int season,
    List<XtreamSeriesEpisode> episodes,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(height: 390, child: _Poster(series: details.series)),
        const SizedBox(height: 14),
        _SeriesInfoPanel(
          details: details,
          season: season,
          episodes: episodes,
          onPlayFirst:
              episodes.isEmpty ? null : () => _play(details, season, episodes.first),
        ),
        const SizedBox(height: 14),
        _SeasonList(
          details: details,
          selectedSeason: season,
          onSelected: (value) => setState(() => _selectedSeason = value),
          compact: true,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 560,
          child: _EpisodePanel(
            series: details.series,
            season: season,
            episodes: episodes,
            onPlay: (episode) => _play(details, season, episode),
          ),
        ),
      ],
    );
  }

  Future<void> _play(
    XtreamSeriesDetails details,
    int season,
    XtreamSeriesEpisode episode,
  ) async {
    final episodes = details.seasons[season] ?? const <XtreamSeriesEpisode>[];
    final channels = episodes
        .map(
          (item) => item.toChannel(
            widget.connection,
            group: '${details.series.name} · Temporada $season',
          ),
        )
        .toList(growable: false);
    final index = episodes.indexWhere((item) => item.id == episode.id);
    if (channels.isEmpty || index < 0) return;
    final provider = context.read<IptvProvider>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          channel: channels[index],
          playlist: channels,
          initialIndex: index,
          settings: provider.playbackSettings,
          isLiveContent: false,
        ),
      ),
    );
  }
}

class _SeriesCatalogData {
  final XtreamConnectionResult connection;
  final List<XtreamSeriesSummary> series;

  const _SeriesCatalogData({required this.connection, required this.series});
}

class _SeriesPosterCard extends StatelessWidget {
  final XtreamSeriesSummary series;
  final VoidCallback onTap;

  const _SeriesPosterCard({required this.series, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CachedArtworkImage(
                url: series.cover,
                fit: BoxFit.cover,
                fallback: const ColoredBox(
                  color: Color(0xFF111C2C),
                  child: Center(
                    child: Icon(Icons.video_library_rounded, size: 46),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Text(
                series.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                series.category ?? series.genre ?? 'Serie',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  final XtreamSeriesSummary series;

  const _Poster({required this.series});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: CachedArtworkImage(
        url: series.cover,
        fit: BoxFit.cover,
        fallback: const ColoredBox(
          color: Color(0xFF111C2C),
          child: Center(child: Icon(Icons.video_library_rounded, size: 70)),
        ),
      ),
    );
  }
}

class _SeasonList extends StatelessWidget {
  final XtreamSeriesDetails details;
  final int selectedSeason;
  final ValueChanged<int> onSelected;
  final bool compact;

  const _SeasonList({
    required this.details,
    required this.selectedSeason,
    required this.onSelected,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final children = details.seasonNumbers.map((season) {
      final count = details.seasons[season]?.length ?? 0;
      final selected = season == selectedSeason;
      return Padding(
        padding: EdgeInsets.only(
          right: compact ? 8 : 0,
          bottom: compact ? 0 : 8,
        ),
        child: Material(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelected(season),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Temporada $season',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: selected ? Colors.white : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$count Eps'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList(growable: false);

    if (compact) {
      return SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, children: children),
      );
    }
    return ListView(children: children);
  }
}

class _EpisodePanel extends StatelessWidget {
  final XtreamSeriesSummary series;
  final int season;
  final List<XtreamSeriesEpisode> episodes;
  final ValueChanged<XtreamSeriesEpisode> onPlay;

  const _EpisodePanel({
    required this.series,
    required this.season,
    required this.episodes,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
            child: Text(
              '${series.name} · Temporada $season',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: episodes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 7),
              itemBuilder: (context, index) {
                final episode = episodes[index];
                final episodeNumber = episode.number > 0 ? episode.number : index + 1;
                return Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Container(
                      width: 48,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        'E$episodeNumber',
                        style: const TextStyle(
                          color: Color(0xFF152235),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    title: Text(
                      episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: episode.duration == null
                        ? null
                        : Text(episode.duration!, maxLines: 1),
                    trailing: const Icon(Icons.play_circle_fill_rounded),
                    onTap: () => onPlay(episode),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesInfoPanel extends StatelessWidget {
  final XtreamSeriesDetails details;
  final int season;
  final List<XtreamSeriesEpisode> episodes;
  final VoidCallback? onPlayFirst;

  const _SeriesInfoPanel({
    required this.details,
    required this.season,
    required this.episodes,
    required this.onPlayFirst,
  });

  @override
  Widget build(BuildContext context) {
    final series = details.series;
    final backdrop = series.backdrops.isNotEmpty ? series.backdrops.first : series.cover;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedArtworkImage(
                    url: backdrop,
                    fit: BoxFit.cover,
                    fallback: const ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Icon(Icons.play_circle_outline_rounded, size: 82),
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xCC000000)],
                      ),
                    ),
                  ),
                  if (onPlayFirst != null)
                    Center(
                      child: FilledButton.icon(
                        onPressed: onPlayFirst,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text('Reproducir T$season · E1'),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    series.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _InfoLine(label: 'Estreno', value: series.releaseDate),
                  _InfoLine(label: 'Género', value: series.genre),
                  _InfoLine(label: 'Categoría', value: series.category),
                  _InfoLine(label: 'Calificación', value: series.rating),
                  if ((series.plot ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Descripción',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 5),
                    Text(series.plot!),
                  ],
                  if ((series.cast ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _InfoLine(label: 'Actores', value: series.cast),
                  ],
                  if ((series.director ?? '').trim().isNotEmpty)
                    _InfoLine(label: 'Director', value: series.director),
                  const SizedBox(height: 10),
                  Text(
                    '${episodes.length} episodios en Temporada $season',
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String? value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _SeriesError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _SeriesError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
