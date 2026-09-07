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
import '../services/channel_logo_resolver_service.dart';
import '../services/device_performance_service.dart';
import '../services/live_epg_service.dart';
import '../services/live_channel_usage_service.dart';
import '../services/parental_control_service.dart';
import '../services/remote_access_guard.dart';
import '../services/section_catalog_service.dart';
import '../services/xtream_fast_catalog_service.dart';
import '../services/xtream_live_fast_service.dart';
import '../services/xtream_service.dart';
import '../widgets/channel_logo_image.dart';
import '../widgets/tv_catalog_category_row.dart';
import '../widgets/tv_full_premium_ui.dart';
import '../widgets/tv_full_section_shell.dart';
import '../widgets/tv_live_premium_catalog.dart';
import 'player_screen.dart';

class XtreamLiveScreen extends StatefulWidget {
  final Playlist playlist;
  final String title;
  final List<String> filterKeywords;
  final bool autoOpenFirstChannel;
  final bool sportsPresentation;
  final VoidCallback? onChangeList;
  final VoidCallback? onRefreshLists;
  final VoidCallback? onParentalControl;
  final ValueChanged<String>? onSectionRequested;

  const XtreamLiveScreen({
    super.key,
    required this.playlist,
    this.title = 'TV EN VIVO',
    this.filterKeywords = const <String>[],
    this.autoOpenFirstChannel = false,
    this.sportsPresentation = false,
    this.onChangeList,
    this.onRefreshLists,
    this.onParentalControl,
    this.onSectionRequested,
  });

  @override
  State<XtreamLiveScreen> createState() => _XtreamLiveScreenState();
}

class _XtreamLiveScreenState extends State<XtreamLiveScreen> {
  static const Duration _cacheFreshFor = Duration(minutes: 3);

  late Future<_LiveData> _future;
  final ParentalControlService _parental = ParentalControlService.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'live-search');
  final ScrollController _catalogScrollController = ScrollController();
  final ScrollController _searchScrollController = ScrollController();
  String? _category;
  String _status = 'Cargando TV en vivo…';
  String _query = '';
  bool _searchOpen = false;
  bool _openingPlayer = false;
  bool _initialPlayerOpened = false;
  Timer? _searchDebounce;
  CatalogIndex<Channel>? _catalogIndex;
  _LiveData? _indexedData;
  _LiveData? _visibleData;

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

  CatalogIndex<Channel> _catalogIndexFor(_LiveData data) {
    final cached = _catalogIndex;
    if (cached != null && identical(_indexedData, data)) return cached;
    final built = CatalogIndex<Channel>.build(
      items: data.channels,
      categoryOrder: data.categories,
      nameOf: (item) => item.name,
      categoryOf: (item) => item.group,
      include: (item) {
        if (!_parental.canShowChannel(item)) return false;
        if (widget.filterKeywords.isEmpty) return true;
        final haystack = '${item.name} ${item.group ?? ''}'.toLowerCase();
        return widget.filterKeywords.any(
          (keyword) => haystack.contains(keyword.toLowerCase()),
        );
      },
    );
    unawaited(ChannelLogoResolverService.instance.primeChannels(data.channels));
    _indexedData = data;
    _catalogIndex = built;
    return built;
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

      _primeXtreamCatalogConnection();
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
      _primeXtreamCatalogConnection();
      final fresh = await XtreamLiveFastService.instance.refresh(
        widget.playlist.source,
        onProgress: (p) => _setStatus(p.label),
      );
      if (!mounted || fresh.channels.isEmpty) return;
      final data = _LiveData(fresh.channels, categories: fresh.categories);
      setState(() {
        _visibleData = data;
        _catalogIndex = null;
        _indexedData = null;
      });
    } catch (_) {}
  }

  void _primeXtreamCatalogConnection() {
    final raw = widget.playlist.source.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return;
    }

    final username = uri.queryParameters['username']?.trim() ?? '';
    final password = uri.queryParameters['password']?.trim() ?? '';
    if (username.isEmpty || password.isEmpty) return;

    var path = uri.path;
    final lower = path.toLowerCase();
    if (lower.endsWith('/get.php')) {
      path = path.substring(0, path.length - '/get.php'.length);
    } else if (lower.endsWith('get.php')) {
      path = path.substring(0, path.length - 'get.php'.length);
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    } else if (lower.endsWith('/player_api.php')) {
      path = path.substring(0, path.length - '/player_api.php'.length);
    } else if (lower.endsWith('player_api.php')) {
      path = path.substring(0, path.length - 'player_api.php'.length);
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    }

    final server = uri.replace(
      path: path.isEmpty ? '/' : path,
      query: '',
      fragment: '',
    );

    XtreamFastCatalogService.instance.rememberConnection(
      XtreamConnectionResult(
        playlistUrl: raw,
        apiServer: server,
        streamServer: server,
        username: username,
        password: password,
      ),
    );
  }

  Future<void> _refreshM3u() async {
    try {
      final all = await SectionCatalogService.instance.refreshIfStale(
        widget.playlist,
      );
      if (all == null) return;
      final fresh = all[TvSectionKind.live];
      if (!mounted || fresh == null || fresh.channels.isEmpty) return;
      final data = _LiveData(fresh.channels, categories: fresh.categories);
      setState(() {
        _visibleData = data;
        _catalogIndex = null;
        _indexedData = null;
      });
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

    if (widget.sportsPresentation) {
      return _buildSportsScreen(provider);
    }

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
          titleSpacing: 24,
          title: _searchOpen
              ? TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Buscar en todos los canales…',
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: _scheduleSearch,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
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
              tooltip: _searchOpen ? 'Cerrar búsqueda' : 'Buscar canales',
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
          child: FutureBuilder<_LiveData>(
            future: _future,
            builder: (context, snapshot) {
              final data = _visibleData ?? snapshot.data;
              if (data == null &&
                  snapshot.connectionState != ConnectionState.done) {
                return _Loading(message: _status);
              }
              if (data == null && snapshot.hasError) {
                return _ErrorView(
                  message: 'No se pudo cargar la TV en vivo.',
                  onRetry: () => setState(() {
                    _visibleData = null;
                    _future = _loadInitial();
                  }),
                );
              }
              if (data == null) return _Loading(message: _status);
              if (data.channels.isEmpty) {
                return _ErrorView(
                  message: 'Esta lista no contiene canales de TV en vivo.',
                  onRetry: () => setState(() => _future = _loadInitial()),
                );
              }
              if (widget.autoOpenFirstChannel && !_initialPlayerOpened) {
                final firstVisible = _catalogIndexFor(data).forCategory(null);
                if (firstVisible.isNotEmpty) {
                  _initialPlayerOpened = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) unawaited(_openPlayer(firstVisible, 0));
                  });
                }
              }
              return _buildCatalog(data);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSportsScreen(IptvProvider provider) {
    return Scaffold(
      backgroundColor: tvFullBackground,
      body: TvFullSectionShell(
        activeSection: TvFullSection.sports,
        onChangeList: widget.onChangeList,
        onRefreshLists: widget.onRefreshLists,
        onParentalControl: widget.onParentalControl,
        onSectionSelected: (section) =>
            widget.onSectionRequested?.call(section.name),
        child: FutureBuilder<_LiveData>(
          future: _future,
          builder: (context, snapshot) {
            final data = _visibleData ?? snapshot.data;
            if (data == null &&
                snapshot.connectionState != ConnectionState.done) {
              return _Loading(message: _status);
            }
            if (data == null && snapshot.hasError) {
              return _ErrorView(
                message: 'No se pudo cargar Deportes.',
                onRetry: () => setState(() {
                  _visibleData = null;
                  _future = _loadInitial();
                }),
              );
            }
            if (data == null || data.channels.isEmpty) {
              return _ErrorView(
                message: 'Esta lista no contiene canales deportivos.',
                onRetry: () => setState(() => _future = _loadInitial()),
              );
            }
            return _buildSportsCatalog(data, provider);
          },
        ),
      ),
    );
  }

  Widget _buildSportsCatalog(_LiveData data, IptvProvider provider) {
    final visible = _catalogIndexFor(data).forCategory(null);
    if (visible.isEmpty) {
      return const Center(
        child: Text(
          'No se encontraron canales deportivos.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    final featured = LiveChannelUsageService.instance.featuredChannels(
      visible,
      isFavorite: provider.isFavorite,
      limit: 5,
    );
    final hero = featured.isEmpty ? visible.first : featured.first;
    final secondary = featured.skip(1).take(4).toList(growable: false);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0x3D101C2D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DEPORTES',
              style: TextStyle(
                color: tvFullCyan,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.8,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Eventos y canales destacados',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 7,
                    child: _SportsHeroCard(
                      channel: hero,
                      onTap: () => unawaited(
                        _openPlayer(visible, visible.indexOf(hero)),
                      ),
                    ),
                  ),
                  if (secondary.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 2.2,
                        ),
                        itemCount: secondary.length,
                        itemBuilder: (context, index) {
                          final channel = secondary[index];
                          return _SportsSmallCard(
                            channel: channel,
                            onTap: () => unawaited(
                              _openPlayer(visible, visible.indexOf(channel)),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Todos los deportes · ${visible.length}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: _catalogScrollController,
                padding: EdgeInsets.zero,
                scrollCacheExtent: DevicePerformanceService.instance.lowRam
                    ? const ScrollCacheExtent.pixels(36)
                    : const ScrollCacheExtent.pixels(80),
                itemCount: visible.length,
                itemBuilder: (context, index) => _ChannelRow(
                  channel: visible[index],
                  autofocus: false,
                  onTap: () => unawaited(_openPlayer(visible, index)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalog(_LiveData data) {
    final index = _catalogIndexFor(data);
    final categories = index.categories;
    final visible =
        _searchOpen ? index.search(_query) : index.forCategory(_category);

    if (!_searchOpen) {
      final provider = context.read<IptvProvider>();
      return TvLivePremiumCatalog(
        channels: visible,
        categories: categories,
        selectedCategory: _category,
        query: _query,
        showSearchField: false,
        onCategorySelected: (category) {
          setState(() => _category = category);
          _resetCatalogScroll();
        },
        onQueryChanged: (_) {},
        onPlay: (channel) {
          final channelIndex = visible.indexOf(channel);
          if (channelIndex >= 0) {
            unawaited(_openPlayer(visible, channelIndex));
          }
        },
        isFavorite: provider.isFavorite,
        onFavoriteToggle: provider.toggleFavorite,
        programGuideLoader: (channel) => LiveEpgService.instance
            .loadXtreamNowNext(widget.playlist.source, channel),
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 220,
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
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
              itemCount: categories.length + 1,
              itemBuilder: (context, index) {
                final category = index == 0 ? null : categories[index - 1];
                final selected = category == _category;
                return TvCatalogCategoryRow(
                  label: category ?? 'Todos',
                  selected: selected,
                  primary: index == 0,
                  autofocus: !_searchOpen && index == 0,
                  onTap: () {
                    if (_searchOpen) _closeSearch();
                    setState(() => _category = category);
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  _searchOpen
                      ? 'Búsqueda global  ·  ${visible.length} canales'
                      : '${_category ?? 'Todos'}  ·  ${visible.length} canales',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const Center(
                        child: Text(
                          'No se encontraron canales.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        key: ValueKey<String>(
                          _searchOpen
                              ? 'live-search:$_query'
                              : 'live-category:${_category ?? 'all'}',
                        ),
                        controller: _searchOpen
                            ? _searchScrollController
                            : _catalogScrollController,
                        padding: const EdgeInsets.fromLTRB(14, 0, 20, 20),
                        scrollCacheExtent:
                            DevicePerformanceService.instance.lowRam
                                ? const ScrollCacheExtent.pixels(36)
                                : const ScrollCacheExtent.pixels(80),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final channel = visible[index];
                          return _ChannelRow(
                            channel: channel,
                            autofocus: !_searchOpen && index == 0,
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
    if (_openingPlayer) return;
    _openingPlayer = true;
    try {
      final provider = context.read<IptvProvider>();
      final section = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            channel: channels[index],
            playlist: channels,
            initialIndex: index,
            settings: provider.playbackSettings,
            isLiveContent: true,
            onChangeList: widget.onChangeList,
            onRefreshLists: widget.onRefreshLists,
            onParentalControl: widget.onParentalControl,
          ),
        ),
      );
      if (section != null && mounted) {
        widget.onSectionRequested?.call(section);
      }
    } finally {
      _openingPlayer = false;
      if (mounted) setState(() {});
    }
  }
}

class _SportsHeroCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback onTap;

  const _SportsHeroCard({required this.channel, required this.onTap});

  @override
  State<_SportsHeroCard> createState() => _SportsHeroCardState();
}

class _SportsHeroCardState extends State<_SportsHeroCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      decoration: tvFullGlassDecoration(
        focused: _focused,
        radius: 16,
        accent: tvFullCyan,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: true,
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .035),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ChannelLogoImage(
                    channel: widget.channel,
                    fit: BoxFit.contain,
                    cacheWidth: 184,
                    cacheHeight: 184,
                    priority: 220,
                    prefetchExtent: 0,
                    fallback: const Icon(
                      Icons.sports_soccer_rounded,
                      size: 42,
                      color: tvFullCyan,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TvFullLiveBadge(compact: true),
                      const SizedBox(height: 9),
                      Text(
                        widget.channel.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if ((widget.channel.group ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.channel.group!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
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

class _SportsSmallCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback onTap;

  const _SportsSmallCard({required this.channel, required this.onTap});

  @override
  State<_SportsSmallCard> createState() => _SportsSmallCardState();
}

class _SportsSmallCardState extends State<_SportsSmallCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
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
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: ChannelLogoImage(
                    channel: widget.channel,
                    fit: BoxFit.contain,
                    cacheWidth: 64,
                    cacheHeight: 64,
                    prefetchExtent: 0,
                    fallback: const Icon(
                      Icons.sports_rounded,
                      size: 18,
                      color: Colors.white54,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.channel.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
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
    final lowRam = DevicePerformanceService.instance.lowRam;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 1),
      child: AnimatedScale(
        scale: _focused ? (lowRam ? 1.012 : 1.025) : 1,
        duration: Duration(milliseconds: lowRam ? 70 : 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: Duration(milliseconds: lowRam ? 70 : 120),
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
              borderRadius: BorderRadius.circular(12),
              onFocusChange: (value) => setState(() => _focused = value),
              onTap: widget.onTap,
              child: SizedBox(
                height: 60,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: ChannelLogoImage(
                          channel: widget.channel,
                          fit: BoxFit.contain,
                          cacheWidth: 84,
                          cacheHeight: 84,
                          priority: _focused ? 100 : 20,
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
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        widget.channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              _focused ? FontWeight.w900 : FontWeight.w700,
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
                          style: TextStyle(
                            color: _focused
                                ? tvFullCyan.withValues(alpha: .75)
                                : Colors.white38,
                            fontSize: 11,
                          ),
                        ),
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
      backgroundColor: Colors.transparent,
      body: TvFullPremiumBackground(
        compact: true,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 540),
            padding: const EdgeInsets.all(32),
            decoration: tvFullGlassDecoration(radius: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 46, color: tvFullCyan),
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
        ),
      ),
    );
  }
}
