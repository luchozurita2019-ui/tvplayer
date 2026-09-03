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
import '../services/xtream_series_service.dart';
import '../services/xtream_service.dart';
import '../widgets/cached_artwork_image.dart';
import '../widgets/tv_catalog_category_row.dart';
import '../widgets/tv_full_premium_ui.dart';
import 'player_screen.dart';

class XtreamSeriesScreen extends StatefulWidget {
  final Playlist playlist;
  const XtreamSeriesScreen({super.key, required this.playlist});

  @override
  State<XtreamSeriesScreen> createState() => _XtreamSeriesScreenState();
}

class _XtreamSeriesScreenState extends State<XtreamSeriesScreen> {
  static const Duration _cacheFreshFor = Duration(minutes: 15);

  late Future<_SeriesData> _future;
  final ParentalControlService _parental = ParentalControlService.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'series-search');
  final ScrollController _catalogScrollController = ScrollController();
  final ScrollController _searchScrollController = ScrollController();
  String? _category;
  String _query = '';
  bool _searchOpen = false;
  bool _openingSeries = false;
  static String? _preparedKey;
  static _SeriesData? _preparedData;
  Timer? _searchDebounce;
  CatalogIndex<_SeriesItem>? _catalogIndex;
  _SeriesData? _indexedData;
  _SeriesData? _visibleData;

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
  void _resetSearchScroll() => _resetScroll(_searchScrollController);

  void _openSearch() {
    if (_searchOpen) return;
    setState(() => _searchOpen = true);
    _resetSearchScroll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

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

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted && value != _query) {
        setState(() => _query = value);
        _resetSearchScroll();
      }
    });
  }

  CatalogIndex<_SeriesItem> _catalogIndexFor(_SeriesData data) {
    final cached = _catalogIndex;
    if (cached != null && identical(_indexedData, data)) return cached;
    final built = CatalogIndex<_SeriesItem>.build(
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

  Future<_SeriesData> _loadInitial() async {
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
      final cached = await fast.loadCachedSeries(widget.playlist.source);
      if (cached != null && cached.series.isNotEmpty) {
        if (DateTime.now().difference(cached.savedAt) >= _cacheFreshFor) {
          unawaited(_refreshXtream());
        }
        final data = _SeriesData.xtream(
          cached.connection,
          cached.series,
          categories: cached.categories,
          savedAt: cached.savedAt,
        );
        _rememberPrepared(data);
        return data;
      }
      try {
        final fresh = await fast.refreshSeries(widget.playlist.source);
        if (fresh.series.isNotEmpty) {
          final data = _SeriesData.xtream(
            fresh.connection,
            fresh.series,
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

  Future<_SeriesData> _loadM3uFallback() async {
    final service = SectionCatalogService.instance;
    final cached = await service.loadCached(
      widget.playlist,
      TvSectionKind.series,
    );
    if (cached != null && cached.channels.isNotEmpty) {
      unawaited(_refreshM3u());
      return _SeriesData.m3u(cached.channels);
    }
    final fresh = await service.loadOrRefresh(
      widget.playlist,
      TvSectionKind.series,
    );
    return _SeriesData.m3u(fresh.channels);
  }

  Future<void> _refreshXtream() async {
    try {
      final fresh = await XtreamFastCatalogService.instance.refreshSeries(
        widget.playlist.source,
      );
      if (!mounted || fresh.series.isEmpty) return;
      final data = _SeriesData.xtream(
        fresh.connection,
        fresh.series,
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

  void _rememberPrepared(_SeriesData data) {
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
      final fresh = all[TvSectionKind.series];
      if (!mounted || fresh == null || fresh.channels.isEmpty) return;
      final data = _SeriesData.m3u(fresh.channels);
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
          return;
        }
        _closeSearch();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: const Color(0xA3050910),
          surfaceTintColor: Colors.transparent,
          title: _searchOpen
              ? TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Buscar en todas las series…',
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: _scheduleSearch,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SERIES',
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
              tooltip: _searchOpen ? 'Cerrar búsqueda' : 'Buscar series',
              onPressed: _searchOpen ? _closeSearch : _openSearch,
              icon: Icon(
                _searchOpen ? Icons.close_rounded : Icons.search_rounded,
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
        body: TvFullPremiumBackground(
          compact: true,
          child: FutureBuilder<_SeriesData>(
            future: _future,
            builder: (context, snapshot) {
              final data = _visibleData ?? snapshot.data;
              if (data == null &&
                  snapshot.connectionState != ConnectionState.done) {
                return const _CenteredLoading(label: 'Cargando series…');
              }
              if (data == null && snapshot.hasError) {
                return _CenteredError(
                  label: 'No se pudo cargar el catálogo de series.',
                  onRetry: () => setState(() {
                    _visibleData = null;
                    _future = _loadInitial();
                  }),
                );
              }
              if (data == null) {
                return const _CenteredLoading(label: 'Cargando series…');
              }
              if (data.items.isEmpty) {
                return _CenteredError(
                  label: 'Esta lista no contiene series disponibles.',
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

  Widget _catalog(_SeriesData data) {
    final index = _catalogIndexFor(data);
    final categories = index.categories;
    final visible =
        _searchOpen ? index.search(_query) : index.forCategory(_category);
    return Row(
      children: [
        SizedBox(
          width: 250,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xD9101928), Color(0xCC07101D)],
              ),
              border: Border(
                right: BorderSide(color: tvFullBlue, width: .35),
              ),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
              itemCount: categories.length + 1,
              itemBuilder: (context, index) {
                final value = index == 0 ? null : categories[index - 1];
                final selected = value == _category;
                return TvCatalogCategoryRow(
                  label: value ?? 'Todas',
                  selected: selected,
                  primary: index == 0,
                  autofocus: !_searchOpen && index == 0,
                  onTap: () {
                    if (_searchOpen) _closeSearch();
                    setState(() => _category = value);
                    _resetCatalogScroll();
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
                      ? 'Búsqueda global  ·  ${visible.length} series'
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
                          'No se encontraron series.',
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
                            key: ValueKey<String>(
                              _searchOpen
                                  ? 'series-search:$_query'
                                  : 'series-category:${_category ?? 'all'}',
                            ),
                            controller: _searchOpen
                                ? _searchScrollController
                                : _catalogScrollController,
                            padding: const EdgeInsets.fromLTRB(20, 4, 24, 30),
                            scrollCacheExtent:
                                DevicePerformanceService.instance.lowRam
                                    ? const ScrollCacheExtent.pixels(48)
                                    : const ScrollCacheExtent.pixels(120),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: 18,
                              mainAxisSpacing: 20,
                              childAspectRatio: 0.62,
                            ),
                            itemCount: visible.length,
                            itemBuilder: (context, index) => _SeriesCard(
                              item: visible[index],
                              autofocus: !_searchOpen && index == 0,
                              onTap: () =>
                                  unawaited(_openSeries(data, visible[index])),
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

  Future<void> _openSeries(_SeriesData data, _SeriesItem item) async {
    if (_openingSeries) return;
    _openingSeries = true;
    try {
      _SeriesDetailModel model;
      if (item.summary != null && data.connection != null) {
        try {
          final details = await XtreamSeriesService.fetchDetails(
            data.connection!,
            item.summary!,
          );
          model = _SeriesDetailModel.fromXtream(data.connection!, details);
        } catch (_) {
          final fallback = await _findM3uSeriesFallback(
            item,
            data.connection!,
          );
          if (fallback == null) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'El proveedor no devolvió episodios para esta serie.',
                ),
              ),
            );
            return;
          }
          model = _SeriesDetailModel.fromM3u(fallback);
        }
      } else {
        model = _SeriesDetailModel.fromM3u(item);
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _SeriesDetailScreen(model: model)),
      );
    } finally {
      _openingSeries = false;
    }
  }

  Future<_SeriesItem?> _findM3uSeriesFallback(
    _SeriesItem xtreamItem,
    XtreamConnectionResult connection,
  ) async {
    final fallbackPlaylist = widget.playlist.copyWith(
      source: connection.playlistUrl,
      sourceType: PlaylistSourceType.m3u,
    );
    final service = SectionCatalogService.instance;
    final target = _normalizeSeriesKey(xtreamItem.name);

    _SeriesItem? exactFrom(List<Channel> channels) {
      final m3uData = _SeriesData.m3u(channels);
      for (final candidate in m3uData.items) {
        if (_normalizeSeriesKey(candidate.name) == target) return candidate;
      }
      return null;
    }

    final cached = await service.loadCached(
      fallbackPlaylist,
      TvSectionKind.series,
    );
    if (cached != null && cached.channels.isNotEmpty) {
      final exact = exactFrom(cached.channels);
      if (exact != null) return exact;

      final refreshed = await service.refreshIfStale(
        fallbackPlaylist,
        freshFor: _cacheFreshFor,
      );
      final freshSeries = refreshed?[TvSectionKind.series];
      if (freshSeries == null || freshSeries.channels.isEmpty) return null;
      return exactFrom(freshSeries.channels);
    }

    try {
      final fresh = await service.loadOrRefresh(
        fallbackPlaylist,
        TvSectionKind.series,
      );
      if (fresh.channels.isEmpty) return null;
      return exactFrom(fresh.channels);
    } catch (_) {
      return null;
    }
  }
}

class _SeriesDetailScreen extends StatefulWidget {
  final _SeriesDetailModel model;
  const _SeriesDetailScreen({required this.model});

  @override
  State<_SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<_SeriesDetailScreen> {
  late int _season;

  @override
  void initState() {
    super.initState();
    _season = widget.model.seasons.keys.first;
  }

  @override
  Widget build(BuildContext context) {
    final episodes = widget.model.seasons[_season] ?? const <_EpisodeItem>[];
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const Color(0xA3050910),
        surfaceTintColor: Colors.transparent,
        title: const Text('Serie'),
      ),
      body: TvFullPremiumBackground(
        compact: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 28),
          child: Column(
            children: [
              SizedBox(
                height: 145,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      height: 140,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedArtworkImage(
                          url: widget.model.cover,
                          fit: BoxFit.cover,
                          cacheWidth: 192,
                          cacheHeight: 280,
                          prefetchExtent: 0,
                          fallback: const ColoredBox(
                            color: Color(0xFF101B25),
                            child: Icon(
                              Icons.video_library_outlined,
                              size: 34,
                              color: Colors.white30,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.model.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if ((widget.model.meta ?? '').isNotEmpty) ...[
                            const SizedBox(height: 7),
                            Text(
                              widget.model.meta!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white54),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            (widget.model.plot ?? '').trim().isEmpty
                                ? 'Seleccioná una temporada y un episodio.'
                                : widget.model.plot!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xA6FFFFFF),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 190,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                            child: Text(
                              'TEMPORADAS',
                              style: TextStyle(
                                color: Color(0x73FFFFFF),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              children: widget.model.seasons.keys.map((season) {
                                final selected = season == _season;
                                return TvCatalogCategoryRow(
                                  label: 'Temporada $season',
                                  selected: selected,
                                  onTap: () => setState(() => _season = season),
                                );
                              }).toList(growable: false),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(width: 1, color: Colors.white10),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            child: Text(
                              'EPISODIOS  ·  ${episodes.length}',
                              style: const TextStyle(
                                color: Color(0x73FFFFFF),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              key: ValueKey<int>(_season),
                              itemCount: episodes.length,
                              itemBuilder: (context, index) {
                                final episode = episodes[index];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: _EpisodeFocusTile(
                                    episode: episode,
                                    autofocus: index == 0,
                                    onTap: () =>
                                        _play(context, episode.channel),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _play(BuildContext context, Channel channel) {
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

class _EpisodeFocusTile extends StatefulWidget {
  final _EpisodeItem episode;
  final bool autofocus;
  final VoidCallback onTap;

  const _EpisodeFocusTile({
    required this.episode,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_EpisodeFocusTile> createState() => _EpisodeFocusTileState();
}

class _EpisodeFocusTileState extends State<_EpisodeFocusTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    return AnimatedScale(
      scale: _focused ? (lowRam ? 1.018 : 1.035) : 1,
      duration: Duration(milliseconds: lowRam ? 80 : 130),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: Duration(milliseconds: lowRam ? 80 : 130),
        decoration: tvFullGlassDecoration(
          focused: _focused,
          radius: 12,
          accent: tvFullCyan,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            autofocus: widget.autofocus,
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: widget.onTap,
            child: SizedBox(
              height: 60,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text(
                        widget.episode.number > 0
                            ? 'E${widget.episode.number.toString().padLeft(2, '0')}'
                            : '▶',
                        style: TextStyle(
                          color:
                              _focused ? tvFullCyan : const Color(0xFF58B9FF),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.episode.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  _focused ? FontWeight.w900 : FontWeight.w700,
                            ),
                          ),
                          if ((widget.episode.duration ?? '').isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              widget.episode.duration!,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.play_arrow_rounded,
                      color: _focused ? tvFullCyan : Colors.white54,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeriesCard extends StatefulWidget {
  final _SeriesItem item;
  final bool autofocus;
  final VoidCallback onTap;

  const _SeriesCard({
    required this.item,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<_SeriesCard> {
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
          accent: const Color(0xFFA04CFF),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            autofocus: widget.autofocus,
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
                          Icons.video_library_outlined,
                          size: 42,
                          color: Colors.white30,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Text(
                    widget.item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.15,
                      fontWeight: _focused ? FontWeight.w900 : FontWeight.w800,
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
}

class _SeriesData {
  final XtreamConnectionResult? connection;
  final List<_SeriesItem> items;
  final List<String> categories;
  final DateTime savedAt;

  const _SeriesData(
    this.connection,
    this.items,
    this.categories,
    this.savedAt,
  );

  factory _SeriesData.xtream(
    XtreamConnectionResult connection,
    List<XtreamSeriesSummary> series, {
    List<String> categories = const <String>[],
    DateTime? savedAt,
  }) {
    final items = series
        .map(
          (item) => _SeriesItem(
            name: item.name,
            cover: _resolveArtwork(connection.streamServer, item.cover),
            category: item.category,
            summary: item,
          ),
        )
        .toList(growable: false);
    final resolvedCategories =
        categories.isEmpty ? _collectCategories(items) : categories;
    return _SeriesData(
      connection,
      List<_SeriesItem>.unmodifiable(items),
      List<String>.unmodifiable(resolvedCategories),
      savedAt ?? DateTime.now(),
    );
  }

  factory _SeriesData.m3u(List<Channel> channels) {
    final byKey = <String, _SeriesItem>{};
    for (final channel in channels) {
      final parsed = _parseM3uEpisode(channel);
      final key = _normalizeSeriesKey(parsed.seriesTitle);
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = _SeriesItem(
          name: parsed.seriesTitle,
          cover: channel.logoUrl,
          category: channel.group,
          m3uEpisodes: [parsed],
        );
      } else {
        existing.m3uEpisodes!.add(parsed);
      }
    }
    final items = byKey.values.toList(growable: false);
    return _SeriesData(
      null,
      List<_SeriesItem>.unmodifiable(items),
      List<String>.unmodifiable(_collectCategories(items)),
      DateTime.now(),
    );
  }

  static List<String> _collectCategories(List<_SeriesItem> items) {
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

class _SeriesItem {
  final String name;
  final String? cover;
  final String? category;
  final XtreamSeriesSummary? summary;
  final List<_M3uEpisode>? m3uEpisodes;
  const _SeriesItem({
    required this.name,
    this.cover,
    this.category,
    this.summary,
    this.m3uEpisodes,
  });
}

class _SeriesDetailModel {
  final String title;
  final String? cover;
  final String? plot;
  final String? meta;
  final Map<int, List<_EpisodeItem>> seasons;
  const _SeriesDetailModel({
    required this.title,
    required this.seasons,
    this.cover,
    this.plot,
    this.meta,
  });

  factory _SeriesDetailModel.fromXtream(
    XtreamConnectionResult connection,
    XtreamSeriesDetails details,
  ) {
    final seasons = <int, List<_EpisodeItem>>{};
    for (final entry in details.seasons.entries) {
      seasons[entry.key] = entry.value
          .map(
            (episode) => _EpisodeItem(
              number: episode.number,
              title: episode.title,
              duration: episode.duration,
              channel: episode.toChannel(
                connection,
                group: details.series.name,
              ),
            ),
          )
          .toList(growable: false);
    }
    final meta = [
      details.series.releaseDate,
      details.series.genre,
      details.series.rating,
    ].whereType<String>().where((e) => e.trim().isNotEmpty).join('  ·  ');
    return _SeriesDetailModel(
      title: details.series.name,
      cover: _resolveArtwork(connection.streamServer, details.series.cover),
      plot: details.series.plot,
      meta: meta,
      seasons: seasons,
    );
  }

  factory _SeriesDetailModel.fromM3u(_SeriesItem item) {
    final seasons = <int, List<_EpisodeItem>>{};
    for (final episode in item.m3uEpisodes ?? const <_M3uEpisode>[]) {
      seasons.putIfAbsent(episode.season, () => []).add(
            _EpisodeItem(
              number: episode.number,
              title: episode.channel.name,
              channel: episode.channel,
            ),
          );
    }
    return _SeriesDetailModel(
      title: item.name,
      cover: item.cover,
      meta: item.category,
      seasons: seasons.isEmpty
          ? {
              1: (item.m3uEpisodes ?? const <_M3uEpisode>[])
                  .map(
                    (e) => _EpisodeItem(
                      number: e.number,
                      title: e.channel.name,
                      channel: e.channel,
                    ),
                  )
                  .toList(growable: false),
            }
          : seasons,
    );
  }
}

class _EpisodeItem {
  final int number;
  final String title;
  final String? duration;
  final Channel channel;
  const _EpisodeItem({
    required this.number,
    required this.title,
    required this.channel,
    this.duration,
  });
}

class _M3uEpisode {
  final String seriesTitle;
  final int season;
  final int number;
  final Channel channel;
  const _M3uEpisode({
    required this.seriesTitle,
    required this.season,
    required this.number,
    required this.channel,
  });
}

_M3uEpisode _parseM3uEpisode(Channel channel) {
  final name = channel.name.trim();
  final patterns = <RegExp>[
    RegExp(r'\bS(\d{1,2})\s*E(\d{1,3})\b', caseSensitive: false),
    RegExp(r'\b(\d{1,2})x(\d{1,3})\b', caseSensitive: false),
    RegExp(r'\bT(\d{1,2})\s*E(\d{1,3})\b', caseSensitive: false),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(name);
    if (match == null) continue;
    final season = int.tryParse(match.group(1) ?? '') ?? 1;
    final episode = int.tryParse(match.group(2) ?? '') ?? 1;
    final before = _trimSeriesSeparators(name.substring(0, match.start));
    final after = _trimSeriesSeparators(name.substring(match.end));
    final seriesTitle = before.isNotEmpty
        ? before
        : after.isNotEmpty
            ? after
            : channel.group?.trim().isNotEmpty == true
                ? channel.group!.trim()
                : name;
    return _M3uEpisode(
      seriesTitle: seriesTitle,
      season: season,
      number: episode,
      channel: channel,
    );
  }
  return _M3uEpisode(
    seriesTitle:
        channel.group?.trim().isNotEmpty == true ? channel.group!.trim() : name,
    season: 1,
    number: 1,
    channel: channel,
  );
}

String _trimSeriesSeparators(String value) =>
    value.replaceAll(RegExp(r'^[\s\-_:|.]+|[\s\-_:|.]+$'), '').trim();

String _normalizeSeriesKey(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ü', 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

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
            const Icon(
              Icons.video_library_outlined,
              size: 44,
              color: Colors.white38,
            ),
            const SizedBox(height: 12),
            Text(label),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      );
}
