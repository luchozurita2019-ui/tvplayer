import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../providers/iptv_provider.dart';
import '../services/artwork_cache_service.dart';
import '../services/catalog_index.dart';
import '../services/device_performance_service.dart';
import '../services/manual_playlist_refresh_service.dart';
import '../services/parental_control_service.dart';
import '../services/section_catalog_service.dart';
import '../services/xtream_fast_catalog_service.dart';
import '../services/xtream_service.dart';
import '../services/xtream_vod_service.dart';
import '../widgets/cached_artwork_image.dart';
import '../widgets/tv_full_premium_ui.dart';
import '../widgets/tv_full_section_shell.dart';
import 'player_screen.dart';

class XtreamMoviesScreen extends StatefulWidget {
  final Playlist playlist;
  final String initialQuery;
  final ValueChanged<String>? onSectionRequested;
  final VoidCallback? onChangeList;
  final VoidCallback? onRefreshLists;
  final VoidCallback? onParentalControl;

  const XtreamMoviesScreen({
    super.key,
    required this.playlist,
    this.initialQuery = '',
    this.onSectionRequested,
    this.onChangeList,
    this.onRefreshLists,
    this.onParentalControl,
  });

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
  bool _openingMovie = false;
  static String? _preparedKey;
  static _MovieData? _preparedData;
  Timer? _searchDebounce;
  CatalogIndex<_MovieItem>? _catalogIndex;
  _MovieData? _indexedData;
  _MovieData? _visibleData;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _searchController.text = _query;
    _searchOpen = _query.isNotEmpty;
    _parental.addListener(_onParentalChanged);
    unawaited(_parental.init());
    unawaited(ArtworkCacheService.instance.switchProvider(widget.playlist.id));
    _future = _loadInitial();
  }

  @override
  void dispose() {
    _parental.removeListener(_onParentalChanged);
    _searchDebounce?.cancel();
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
    _catalogIndex = null;
    _indexedData = null;
    setState(() {});
  }

  void _resetScroll(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      controller.jumpTo(0);
    });
  }

  void _resetCatalogScroll() => _resetScroll(_catalogScrollController);

  void _closeSearch() {
    if (!_searchOpen) return;
    _searchDebounce?.cancel();
    _searchFocus.unfocus();
    _searchController.clear();
    setState(() {
      _query = '';
      _searchOpen = false;
    });
    _resetCatalogScroll();
  }

  CatalogIndex<_MovieItem> _catalogIndexFor(_MovieData data) {
    final cached = _catalogIndex;
    if (cached != null && identical(_indexedData, data)) return cached;
    final built = CatalogIndex<_MovieItem>.build(
      items: data.items,
      categoryOrder: data.categories,
      nameOf: (item) => item.name,
      categoryOf: (item) => item.category,
      include: (item) =>
          _parental.canShowItem(name: item.name, group: item.category),
    );
    _indexedData = data;
    _catalogIndex = built;
    return built;
  }

  Future<_MovieData> _loadInitial() async {
    if (widget.playlist.sourceType == PlaylistSourceType.xtream) {
      final key = _preparedCacheKey();
      final prepared = _preparedData;
      if (!DevicePerformanceService.instance.lowRam &&
          _preparedKey == key &&
          prepared != null) {
        if (DateTime.now().difference(prepared.savedAt) >= _cacheFreshFor) {
          unawaited(_refreshXtream());
        }
        return prepared;
      }

      final fast = XtreamFastCatalogService.instance;
      final cached = await fast.loadCachedMovies(widget.playlist.source);
      if (cached != null && cached.movies.isNotEmpty) {
        if (DateTime.now().difference(cached.savedAt) >= _cacheFreshFor) {
          unawaited(_refreshXtream());
        }
        final data = _MovieData.xtream(
          cached.connection,
          cached.movies,
          categories: cached.categories,
          savedAt: cached.savedAt,
        );
        _rememberPrepared(data);
        return data;
      }
      try {
        final fresh = await fast.refreshMovies(widget.playlist.source);
        if (fresh.movies.isNotEmpty) {
          final data = _MovieData.xtream(
            fresh.connection,
            fresh.movies,
            categories: fresh.categories,
            savedAt: fresh.savedAt,
          );
          _rememberPrepared(data);
          return data;
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
      final data = _MovieData.xtream(
        fresh.connection,
        fresh.movies,
        categories: fresh.categories,
        savedAt: fresh.savedAt,
      );
      _rememberPrepared(data);
      setState(() {
        _visibleData = data;
        _catalogIndex = null;
        _indexedData = null;
      });
    } catch (_) {}
  }

  String _preparedCacheKey() {
    final revision =
        ManualPlaylistRefreshService.instance.revisionFor(widget.playlist);
    return '${widget.playlist.source.trim()}|$revision';
  }

  void _rememberPrepared(_MovieData data) {
    if (DevicePerformanceService.instance.lowRam) return;
    _preparedKey = _preparedCacheKey();
    _preparedData = data;
  }

  Future<void> _refreshM3u() async {
    try {
      final all = await SectionCatalogService.instance.refreshIfStale(
        widget.playlist,
      );
      if (all == null) return;
      final fresh = all[TvSectionKind.movies];
      if (!mounted || fresh == null || fresh.channels.isEmpty) return;
      final data = _MovieData.m3u(fresh.channels);
      setState(() {
        _visibleData = data;
        _catalogIndex = null;
        _indexedData = null;
      });
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
        } else {
          _closeSearch();
        }
      },
      child: Scaffold(
        backgroundColor: tvFullBackground,
        body: TvFullSectionShell(
          activeSection: TvFullSection.movies,
          onChangeList: widget.onChangeList,
          onRefreshLists: widget.onRefreshLists,
          onParentalControl: widget.onParentalControl,
          onSectionSelected: (section) =>
              widget.onSectionRequested?.call(section.name),
          child: FutureBuilder<_MovieData>(
            future: _future,
            builder: (context, snapshot) {
              final data = _visibleData ?? snapshot.data;
              if (data == null &&
                  snapshot.connectionState != ConnectionState.done) {
                return const _CenteredLoading(label: 'Cargando películas…');
              }
              if (data == null && snapshot.hasError) {
                return _CenteredError(
                  label: 'No se pudo cargar el catálogo de películas.',
                  onRetry: () => setState(() {
                    _visibleData = null;
                    _future = _loadInitial();
                  }),
                );
              }
              if (data == null) {
                return const _CenteredLoading(label: 'Cargando películas…');
              }
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
      ),
    );
  }

  Widget _catalog(_MovieData data) {
    final index = _catalogIndexFor(data);
    final categories = index.categories;
    final visible =
        _searchOpen ? index.search(_query) : index.forCategory(_category);
    final hero = visible.isEmpty ? null : visible.first;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0x3D101C2D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hero != null)
            SizedBox(
              height: 190,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 330,
                        child: CachedArtworkImage(
                          url: hero.cover,
                          fit: BoxFit.cover,
                          cacheWidth: 660,
                          cacheHeight: 380,
                          priority: 250,
                          prefetchExtent: 0,
                          fallback: const ColoredBox(color: Color(0xFF101C2D)),
                        ),
                      ),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0xFF0D192A),
                            Color(0xF00D192A),
                            Color(0x66101C2D),
                          ],
                          stops: [0, .48, 1],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 350, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'PELÍCULAS',
                            style: TextStyle(
                              color: tvFullCyan,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hero.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              height: 1.02,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if ((hero.category ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              hero.category!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 15),
                          SizedBox(
                            height: 38,
                            child: FilledButton.icon(
                              autofocus: true,
                              onPressed: () =>
                                  unawaited(_openMovie(data, hero)),
                              icon: const Icon(Icons.play_arrow_rounded,
                                  size: 19),
                              label: const Text('Ver película'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SizedBox(
            height: 52,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(18, 9, 18, 7),
              itemCount: categories.length + 1,
              itemBuilder: (context, chipIndex) {
                final value = chipIndex == 0 ? null : categories[chipIndex - 1];
                return _MovieCategoryChip(
                  label: value ?? 'Todas',
                  selected: value == _category,
                  onTap: () {
                    if (_searchOpen) _closeSearch();
                    setState(() => _category = value);
                    _resetCatalogScroll();
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 3, 20, 9),
            child: Text(
              _searchOpen
                  ? 'Resultados · ${visible.length}'
                  : 'Películas destacadas · ${visible.length}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? const Center(
                    child: Text('No se encontraron películas.',
                        style: TextStyle(color: Colors.white54)),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 980 ? 6 : 5;
                      return GridView.builder(
                        key: ValueKey<String>(
                          _searchOpen
                              ? 'movies-search:$_query'
                              : 'movies-category:${_category ?? 'all'}',
                        ),
                        controller: _searchOpen
                            ? _searchScrollController
                            : _catalogScrollController,
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                        scrollCacheExtent:
                            DevicePerformanceService.instance.lowRam
                                ? const ScrollCacheExtent.pixels(40)
                                : const ScrollCacheExtent.pixels(100),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 13,
                          mainAxisSpacing: 14,
                          childAspectRatio: .64,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, itemIndex) => _MovieCard(
                          item: visible[itemIndex],
                          onTap: () =>
                              unawaited(_openMovie(data, visible[itemIndex])),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMovie(_MovieData data, _MovieItem item) async {
    if (_openingMovie) return;
    _openingMovie = true;
    try {
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
    } finally {
      _openingMovie = false;
    }
  }
}

class _MovieCategoryChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MovieCategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_MovieCategoryChip> createState() => _MovieCategoryChipState();
}

class _MovieCategoryChipState extends State<_MovieCategoryChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || widget.selected;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        decoration: BoxDecoration(
          color: active
              ? tvFullBlue.withValues(alpha: _focused ? .24 : .13)
              : Colors.white.withValues(alpha: .025),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _focused
                ? tvFullCyan
                : widget.selected
                    ? tvFullCyan.withValues(alpha: .30)
                    : Colors.white.withValues(alpha: .08),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              child: Text(
                widget.label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white54,
                  fontSize: 10.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
      if ((language ?? '').trim().isNotEmpty) language!.trim(),
      if ((originalLanguage ?? '').trim().isNotEmpty &&
          originalLanguage!.trim().toLowerCase() !=
              (language ?? '').trim().toLowerCase())
        'Original: ${originalLanguage!.trim()}',
      if ((audioInfo ?? '').trim().isNotEmpty) audioInfo!.trim(),
      if ((translation ?? '').trim().isNotEmpty) translation!.trim(),
      if ((country ?? '').trim().isNotEmpty) country!.trim(),
    ];

    return Scaffold(
      backgroundColor: tvFullBackground,
      body: TvFullPremiumBackground(
        compact: true,
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(26, 20, 26, 24),
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    'PELÍCULA',
                    style: TextStyle(
                      color: tvFullCyan,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const Spacer(),
                  const TvFullClock(),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0x5C101C2D),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: .08)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 310,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(20),
                          ),
                          child: CachedArtworkImage(
                            url: poster,
                            fit: BoxFit.cover,
                            cacheWidth: 620,
                            cacheHeight: 900,
                            priority: 260,
                            prefetchExtent: 0,
                            fallback: const ColoredBox(
                              color: Color(0xFF101B25),
                              child: Center(
                                child: Icon(
                                  Icons.movie_outlined,
                                  size: 54,
                                  color: Colors.white30,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(36, 30, 38, 30),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  height: 1.03,
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
                                    color: tvFullMuted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (languageDetails.isNotEmpty) ...[
                                const SizedBox(height: 7),
                                Text(
                                  languageDetails.join('  ·  '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              Text(
                                (plot ?? '').trim().isEmpty
                                    ? 'Sin descripción disponible.'
                                    : plot!.trim(),
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 26),
                              SizedBox(
                                height: 44,
                                child: FilledButton.icon(
                                  autofocus: true,
                                  onPressed: () => _play(context),
                                  icon: const Icon(Icons.play_arrow_rounded,
                                      size: 24),
                                  label: const Text(
                                    'Reproducir',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
  final VoidCallback onTap;
  const _MovieCard({
    required this.item,
    required this.onTap,
  });

  @override
  State<_MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<_MovieCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    return AnimatedScale(
      scale: _focused ? (lowRam ? 1.025 : 1.055) : 1,
      duration: Duration(milliseconds: lowRam ? 80 : 140),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: Duration(milliseconds: lowRam ? 80 : 140),
        decoration: tvFullGlassDecoration(
          focused: _focused,
          radius: 15,
          accent: tvFullViolet,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CachedArtworkImage(
                    url: widget.item.cover,
                    fit: BoxFit.cover,
                    cacheWidth: 320,
                    cacheHeight: 480,
                    priority: _focused ? 100 : 10,
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
                  padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.12,
                          fontWeight:
                              _focused ? FontWeight.w900 : FontWeight.w800,
                        ),
                      ),
                      if ((widget.item.category ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          widget.item.category!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _focused
                                ? tvFullCyan.withValues(alpha: .72)
                                : Colors.white38,
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
  final List<String> categories;
  final DateTime savedAt;

  const _MovieData(
    this.connection,
    this.items,
    this.categories,
    this.savedAt,
  );

  factory _MovieData.xtream(
    XtreamConnectionResult connection,
    List<XtreamVodSummary> movies, {
    List<String> categories = const <String>[],
    DateTime? savedAt,
  }) {
    final items = movies
        .map(
          (item) => _MovieItem(
            name: item.name,
            cover: _resolveArtwork(connection.streamServer, item.cover),
            category: item.category,
            summary: item,
          ),
        )
        .toList(growable: false);
    final resolvedCategories =
        categories.isEmpty ? _collectCategories(items) : categories;
    return _MovieData(
      connection,
      List<_MovieItem>.unmodifiable(items),
      List<String>.unmodifiable(resolvedCategories),
      savedAt ?? DateTime.now(),
    );
  }

  factory _MovieData.m3u(List<Channel> channels) {
    final items = channels
        .map(
          (item) => _MovieItem(
            name: item.name,
            cover: item.logoUrl,
            category: item.group,
            channel: item,
          ),
        )
        .toList(growable: false);
    return _MovieData(
      null,
      List<_MovieItem>.unmodifiable(items),
      List<String>.unmodifiable(_collectCategories(items)),
      DateTime.now(),
    );
  }

  static List<String> _collectCategories(List<_MovieItem> items) {
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
