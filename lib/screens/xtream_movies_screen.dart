import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../providers/iptv_provider.dart';
import '../services/artwork_cache_service.dart';
import '../services/parental_control_service.dart';
import '../services/section_catalog_service.dart';
import '../services/xtream_fast_catalog_service.dart';
import '../services/xtream_service.dart';
import '../services/xtream_vod_service.dart';
import '../widgets/cached_artwork_image.dart';
import '../widgets/tv_catalog_category_row.dart';
import 'player_screen.dart';

class XtreamMoviesScreen extends StatefulWidget {
  final Playlist playlist;
  const XtreamMoviesScreen({super.key, required this.playlist});

  @override
  State<XtreamMoviesScreen> createState() => _XtreamMoviesScreenState();
}

class _XtreamMoviesScreenState extends State<XtreamMoviesScreen> {
  static const Duration _cacheFreshFor = Duration(minutes: 15);

  late Future<_MovieData> _future;
  final ParentalControlService _parental = ParentalControlService.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'movie-search');
  final ScrollController _catalogScrollController = ScrollController();
  final ScrollController _searchScrollController = ScrollController();
  String? _category;
  String _query = '';
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _parental.addListener(_onParentalChanged);
    unawaited(_parental.init());
    unawaited(ArtworkCacheService.instance.switchProvider(widget.playlist.id));
    _future = _loadInitial();
  }

  @override
  void dispose() {
    _parental.removeListener(_onParentalChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _catalogScrollController.dispose();
    _searchScrollController.dispose();
    unawaited(ArtworkCacheService.instance.clearBrowsingSession());
    super.dispose();
  }

  void _onParentalChanged() {
    if (!mounted) return;
    if (_parental.isLocked &&
        _category != null &&
        _parental.isProtectedGroup(_category)) {
      _category = null;
    }
    setState(() {});
  }

  void _openSearch() {
    if (_searchOpen) return;
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    if (!_searchOpen) return;
    _searchFocus.unfocus();
    _searchController.clear();
    setState(() {
      _query = '';
      _searchOpen = false;
    });
  }

  Future<_MovieData> _loadInitial() async {
    if (widget.playlist.sourceType == PlaylistSourceType.xtream) {
      final fast = XtreamFastCatalogService.instance;
      final cached = await fast.loadCachedMovies(widget.playlist.source);
      if (cached != null && cached.movies.isNotEmpty) {
        if (DateTime.now().difference(cached.savedAt) >= _cacheFreshFor) {
          unawaited(_refreshXtream());
        }
        return _MovieData.xtream(cached.connection, cached.movies);
      }
      try {
        final fresh = await fast.refreshMovies(widget.playlist.source);
        if (fresh.movies.isNotEmpty) {
          return _MovieData.xtream(fresh.connection, fresh.movies);
        }
      } catch (_) {}
      return _loadM3uFallback();
    }
    return _loadM3uFallback();
  }

  Future<_MovieData> _loadM3uFallback() async {
    final service = SectionCatalogService.instance;
    final cached = await service.loadCached(
      widget.playlist,
      TvSectionKind.movies,
    );
    if (cached != null && cached.channels.isNotEmpty) {
      unawaited(_refreshM3u());
      return _MovieData.m3u(cached.channels);
    }
    final fresh = await service.loadOrRefresh(
      widget.playlist,
      TvSectionKind.movies,
    );
    return _MovieData.m3u(fresh.channels);
  }

  Future<void> _refreshXtream() async {
    try {
      final fresh = await XtreamFastCatalogService.instance.refreshMovies(
        widget.playlist.source,
      );
      if (!mounted || fresh.movies.isEmpty) return;
      setState(
        () => _future = Future.value(
          _MovieData.xtream(fresh.connection, fresh.movies),
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
      final fresh = all[TvSectionKind.movies];
      if (!mounted || fresh == null || fresh.channels.isEmpty) return;
      setState(() => _future = Future.value(_MovieData.m3u(fresh.channels)));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_searchOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !_searchOpen) return;
        if (_searchFocus.hasFocus) {
          _searchFocus.unfocus();
          return;
        }
        _closeSearch();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF05090F),
        appBar: AppBar(
          title: _searchOpen
              ? TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Buscar en todas las películas…',
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PELÍCULAS',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      widget.playlist.name,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
          actions: [
            IconButton(
              tooltip: _searchOpen ? 'Cerrar búsqueda' : 'Buscar películas',
              onPressed: _searchOpen ? _closeSearch : _openSearch,
              icon: Icon(
                _searchOpen ? Icons.close_rounded : Icons.search_rounded,
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
        body: FutureBuilder<_MovieData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _CenteredLoading(label: 'Cargando películas…');
            }
            if (snapshot.hasError) {
              return _CenteredError(
                label: 'No se pudo cargar el catálogo de películas.',
                onRetry: () => setState(() => _future = _loadInitial()),
              );
            }
            final data = snapshot.data!;
            if (data.items.isEmpty) {
              return _CenteredError(
                label: 'Esta lista no contiene películas disponibles.',
                onRetry: () => setState(() => _future = _loadInitial()),
              );
            }
            return _catalog(data);
          },
        ),
      ),
    );
  }

  Widget _catalog(_MovieData data) {
    final categories = _parental.visibleGroups(data.categories);
    final allowed = data.items
        .where(
          (item) => _parental.canShowItem(
            name: item.name,
            group: item.category,
          ),
        )
        .toList(growable: false);
    final normalizedQuery = _query.trim().toLowerCase();
    final List<_MovieItem> visible;
    if (_searchOpen) {
      visible = normalizedQuery.isEmpty
          ? allowed
          : allowed.where((item) {
              final name = item.name.toLowerCase();
              final category = (item.category ?? '').toLowerCase();
              return name.contains(normalizedQuery) ||
                  category.contains(normalizedQuery);
            }).toList(growable: false);
    } else {
      visible = _category == null
          ? allowed
          : allowed
              .where((item) => item.category == _category)
              .toList(growable: false);
    }

    return Row(
      children: [
        SizedBox(
          width: 250,
          child: ColoredBox(
            color: const Color(0xFF08111B),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
              itemCount: categories.length + 1,
              itemBuilder: (context, index) {
                final value = index == 0 ? null : categories[index - 1];
                final selected = value == _category;
                return TvCatalogCategoryRow(
                  label: value ?? 'Todas',
                  selected: selected,
                  autofocus: !_searchOpen && index == 0,
                  onTap: () {
                    if (_searchOpen) _closeSearch();
                    setState(() => _category = value);
                  },
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
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 10),
                child: Text(
                  _searchOpen
                      ? 'Búsqueda global  ·  ${visible.length} películas'
                      : '${_category ?? 'Todas'}  ·  ${visible.length}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const Center(
                        child: Text(
                          'No se encontraron películas.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 850
                              ? 5
                              : constraints.maxWidth >= 620
                                  ? 4
                                  : 3;
                          return GridView.builder(
                            controller: _searchOpen
                                ? _searchScrollController
                                : _catalogScrollController,
                            padding: const EdgeInsets.fromLTRB(20, 4, 24, 30),
                            scrollCacheExtent:
                                const ScrollCacheExtent.pixels(120),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: 18,
                              mainAxisSpacing: 20,
                              childAspectRatio: 0.62,
                            ),
                            itemCount: visible.length,
                            itemBuilder: (context, index) => _MovieCard(
                              item: visible[index],
                              autofocus: !_searchOpen && index == 0,
                              onTap: () =>
                                  unawaited(_openMovie(data, visible[index])),
                            ),
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

  Future<void> _openMovie(_MovieData data, _MovieItem item) async {
    if (item.summary != null && data.connection != null) {
      XtreamVodDetails details;
      try {
        details = await XtreamVodService.fetchDetails(
          data.connection!,
          item.summary!,
        );
      } catch (_) {
        details = XtreamVodDetails(
          movie: item.summary!,
          extension: item.summary!.extension,
          genre: item.summary!.genre,
          releaseDate: item.summary!.releaseDate,
          rating: item.summary!.rating,
          directSource: item.summary!.directSource,
        );
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _MovieDetailScreen(
            title: item.name,
            poster: item.cover,
            category: item.category,
            plot: details.plot,
            genre: details.genre,
            releaseDate: details.releaseDate,
            rating: details.rating,
            duration: details.duration,
            country: details.country,
            language: details.language,
            originalLanguage: details.originalLanguage,
            audioInfo: details.audioInfo,
            translation: details.translation,
            channel: details.toChannel(data.connection!),
          ),
        ),
      );
      return;
    }

    if (item.channel != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _MovieDetailScreen(
            title: item.name,
            poster: item.cover,
            category: item.category,
            channel: item.channel!,
          ),
        ),
      );
    }
  }
}

class _MovieDetailScreen extends StatelessWidget {
  final String title;
  final String? poster;
  final String? category;
  final String? plot;
  final String? genre;
  final String? releaseDate;
  final String? rating;
  final String? duration;
  final String? country;
  final String? language;
  final String? originalLanguage;
  final String? audioInfo;
  final String? translation;
  final Channel channel;

  const _MovieDetailScreen({
    required this.title,
    required this.channel,
    this.poster,
    this.category,
    this.plot,
    this.genre,
    this.releaseDate,
    this.rating,
    this.duration,
    this.country,
    this.language,
    this.originalLanguage,
    this.audioInfo,
    this.translation,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = <String>[
      if ((releaseDate ?? '').trim().isNotEmpty) releaseDate!.trim(),
      if ((duration ?? '').trim().isNotEmpty) duration!.trim(),
      if ((genre ?? category ?? '').trim().isNotEmpty)
        (genre ?? category)!.trim(),
      if ((rating ?? '').trim().isNotEmpty) '★ ${rating!.trim()}',
    ];
    final languageDetails = <String>[
      if ((language ?? '').trim().isNotEmpty) 'Idioma: ${language!.trim()}',
      if ((originalLanguage ?? '').trim().isNotEmpty &&
          originalLanguage!.trim().toLowerCase() !=
              (language ?? '').trim().toLowerCase())
        'Original: ${originalLanguage!.trim()}',
      if ((audioInfo ?? '').trim().isNotEmpty) 'Audio: ${audioInfo!.trim()}',
      if ((translation ?? '').trim().isNotEmpty)
        'Traducción: ${translation!.trim()}',
      if ((country ?? '').trim().isNotEmpty) country!.trim(),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF05090F),
      appBar: AppBar(title: const Text('Película')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(44, 28, 44, 34),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 178,
              height: 260,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedArtworkImage(
                  url: poster,
                  fit: BoxFit.cover,
                  cacheWidth: 356,
                  cacheHeight: 520,
                  prefetchExtent: 0,
                  fallback: Container(
                    color: const Color(0xFF101B25),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.movie_outlined,
                      size: 48,
                      color: Colors.white30,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 32),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 32,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      metadata.join('  ·  '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (languageDetails.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      languageDetails.join('  ·  '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0x75FFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    (plot ?? '').trim().isEmpty
                        ? 'Sin descripción disponible.'
                        : plot!.trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    autofocus: true,
                    onPressed: () => _play(context),
                    icon: const Icon(Icons.play_arrow_rounded, size: 26),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'REPRODUCIR',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _play(BuildContext context) {
    final provider = context.read<IptvProvider>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          channel: channel,
          playlist: [channel],
          initialIndex: 0,
          settings: provider.playbackSettings,
          isLiveContent: false,
        ),
      ),
    );
  }
}

class _MovieCard extends StatefulWidget {
  final _MovieItem item;
  final bool autofocus;
  final VoidCallback onTap;
  const _MovieCard({
    required this.item,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<_MovieCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _focused ? 1.035 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: const Color(0xFF0B151F),
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(13),
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: _focused
                    ? const Color(0xFF58B9FF)
                    : Colors.white.withValues(alpha: .07),
                width: _focused ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CachedArtworkImage(
                    url: widget.item.cover,
                    fit: BoxFit.cover,
                    cacheWidth: 320,
                    cacheHeight: 480,
                    prefetchExtent: 0,
                    fallback: const ColoredBox(
                      color: Color(0xFF111E29),
                      child: Center(
                        child: Icon(
                          Icons.movie_outlined,
                          color: Colors.white30,
                          size: 42,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if ((widget.item.category ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          widget.item.category!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
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

class _MovieData {
  final XtreamConnectionResult? connection;
  final List<_MovieItem> items;
  const _MovieData(this.connection, this.items);

  factory _MovieData.xtream(
    XtreamConnectionResult connection,
    List<XtreamVodSummary> movies,
  ) =>
      _MovieData(
        connection,
        movies
            .map(
              (item) => _MovieItem(
                name: item.name,
                cover: _resolveArtwork(connection.streamServer, item.cover),
                category: item.category,
                summary: item,
              ),
            )
            .toList(growable: false),
      );

  factory _MovieData.m3u(List<Channel> channels) => _MovieData(
        null,
        channels
            .map(
              (item) => _MovieItem(
                name: item.name,
                cover: item.logoUrl,
                category: item.group,
                channel: item,
              ),
            )
            .toList(growable: false),
      );

  List<String> get categories {
    final seen = <String>{};
    final result = <String>[];
    for (final item in items) {
      final value = item.category?.trim();
      if (value != null && value.isNotEmpty && seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }
}

class _MovieItem {
  final String name;
  final String? cover;
  final String? category;
  final XtreamVodSummary? summary;
  final Channel? channel;
  const _MovieItem({
    required this.name,
    this.cover,
    this.category,
    this.summary,
    this.channel,
  });
}

String? _resolveArtwork(Uri base, String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty || value.toLowerCase() == 'null' || value == '0') {
    return null;
  }
  if (value.startsWith('//')) return '${base.scheme}:$value';
  final uri = Uri.tryParse(value);
  if (uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty) {
    return uri.toString();
  }
  return base.resolve(value).toString();
}

class _CenteredLoading extends StatelessWidget {
  final String label;
  const _CenteredLoading({required this.label});
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
            Text(label, style: const TextStyle(color: Colors.white60)),
          ],
        ),
      );
}

class _CenteredError extends StatelessWidget {
  final String label;
  final VoidCallback onRetry;
  const _CenteredError({required this.label, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_outlined, size: 44, color: Colors.white38),
            const SizedBox(height: 12),
            Text(label),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      );
}
