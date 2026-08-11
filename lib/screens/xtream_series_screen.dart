import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../providers/iptv_provider.dart';
import '../services/parental_control_service.dart';
import '../services/xtream_fast_catalog_service.dart';
import '../services/xtream_series_service.dart';
import '../services/xtream_service.dart';
import '../widgets/cached_artwork_image.dart';
import '../widgets/parental_lock_button.dart';
import '../widgets/parental_unlock_dialog.dart';
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
  double _sidebarWidth = 320;
  bool _sidebarCollapsed = false;
  final ParentalControlService _parental = ParentalControlService.instance;
  List<String> _catalogCategories = const <String>[];
  String _progressLabel = 'Cargando información del servidor…';
  int _loadGeneration = 0;
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastProgressBytes = 0;

  static const double _sidebarMinWidth = 230;
  static const double _sidebarMaxWidth = 480;
  // Compartimos las mismas preferencias del catálogo general para que TV,
  // Películas y Series mantengan exactamente el mismo ancho/estado.
  static const String _sidebarWidthKey = 'catalog_sidebar_width_v1';
  static const String _sidebarCollapsedKey = 'catalog_sidebar_collapsed_v1';

  @override
  void initState() {
    super.initState();
    _parental.addListener(_onParentalChanged);
    _future = _load();
    _loadSidebarPreferences();
  }

  @override
  void dispose() {
    _parental.removeListener(_onParentalChanged);
    super.dispose();
  }

  void _onParentalChanged() {
    if (!mounted) return;
    if (_category != null &&
        _parental.isLocked &&
        _parental.isProtectedGroup(_category)) {
      _category = null;
    }
    setState(() {});
  }

  Future<void> _loadSidebarPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final width = prefs.getDouble(_sidebarWidthKey) ?? 320;
    setState(() {
      _sidebarWidth = width.clamp(_sidebarMinWidth, _sidebarMaxWidth).toDouble();
      _sidebarCollapsed = prefs.getBool(_sidebarCollapsedKey) ?? false;
    });
  }

  Future<void> _persistSidebar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_sidebarWidthKey, _sidebarWidth);
    await prefs.setBool(_sidebarCollapsedKey, _sidebarCollapsed);
  }

  void _resizeSidebar(double delta) {
    if (_sidebarCollapsed) return;
    setState(() {
      _sidebarWidth = (_sidebarWidth + delta)
          .clamp(_sidebarMinWidth, _sidebarMaxWidth)
          .toDouble();
    });
  }

  void _toggleSidebar() {
    setState(() => _sidebarCollapsed = !_sidebarCollapsed);
    _persistSidebar();
  }

  Future<void> _selectCategory(String? category) async {
    if (category != null &&
        _parental.isLocked &&
        _parental.isProtectedGroup(category)) {
      final unlocked = await requestParentalUnlock(context);
      if (!unlocked || !mounted) return;
    }
    setState(() => _category = category);
  }

  Future<void> _toggleParentalLock() async {
    if (_parental.isUnlocked) {
      _parental.lockNow();
      return;
    }
    await requestParentalUnlock(context);
  }

  Future<void> _openSeries(
    XtreamConnectionResult connection,
    XtreamSeriesSummary series,
  ) async {
    if (_parental.isLocked &&
        _parental.isProtectedItem(name: series.name, group: series.category)) {
      final unlocked = await requestParentalUnlock(context);
      if (!unlocked || !mounted) return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => XtreamSeriesDetailScreen(
          connection: connection,
          summary: series,
        ),
      ),
    );
  }

  Future<_SeriesCatalogData> _load({bool forceNetwork = false}) async {
    await _parental.init();
    final generation = ++_loadGeneration;
    final fast = XtreamFastCatalogService.instance;

    if (!forceNetwork) {
      final cached = await fast.loadCachedSeries(widget.playlist.source);
      if (cached != null && cached.series.isNotEmpty) {
        _setCatalogCategories(cached.categories);
        unawaited(_refreshSeriesCatalog(generation));
        return _SeriesCatalogData(
          connection: cached.connection,
          series: cached.series,
        );
      }
    }

    final fresh = await fast.refreshSeries(
      widget.playlist.source,
      forceSessionRefresh: forceNetwork,
      onProgress: _onCatalogProgress,
    );
    _setCatalogCategories(fresh.categories);
    return _SeriesCatalogData(
      connection: fresh.connection,
      series: fresh.series,
    );
  }

  void _setCatalogCategories(List<String> categories) {
    final value = List<String>.unmodifiable(categories);
    if (mounted) {
      setState(() => _catalogCategories = value);
    } else {
      _catalogCategories = value;
    }
  }

  void _onCatalogProgress(XtreamCatalogProgress progress) {
    if (!mounted) return;
    final now = DateTime.now();
    final bytesDelta = progress.receivedBytes - _lastProgressBytes;
    final elapsed = now.difference(_lastProgressUpdate);
    if (progress.receivedBytes > 0 &&
        bytesDelta < 128 * 1024 &&
        elapsed < const Duration(milliseconds: 180)) {
      return;
    }
    _lastProgressUpdate = now;
    _lastProgressBytes = progress.receivedBytes;
    setState(() => _progressLabel = progress.label);
  }

  Future<void> _refreshSeriesCatalog(int generation) async {
    try {
      final fresh = await XtreamFastCatalogService.instance.refreshSeries(
        widget.playlist.source,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _catalogCategories = List<String>.unmodifiable(fresh.categories);
        if (_category != null && !_catalogCategories.contains(_category)) {
          _category = null;
        }
        _future = Future<_SeriesCatalogData>.value(
          _SeriesCatalogData(
            connection: fresh.connection,
            series: fresh.series,
          ),
        );
      });
    } catch (_) {
      // Conservamos la copia local cuando el proveedor no responde.
    }
  }

  void _retry() {
    XtreamFastCatalogService.instance.invalidateSession(widget.playlist.source);
    setState(() {
      _progressLabel = 'Cargando información del servidor…';
      _lastProgressBytes = 0;
      _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      _future = _load(forceNetwork: true);
    });
  }

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
        actions: [
          if (_parental.enabled)
            ParentalLockButton(
              unlocked: _parental.isUnlocked,
              hiddenCategoryCount:
                  _parental.hiddenGroupCount(_catalogCategories),
              onPressed: () => unawaited(_toggleParentalLock()),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<_SeriesCatalogData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  Text(_progressLabel),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            final rawError = snapshot.error.toString();
            final message = rawError.contains('TimeoutException')
                ? 'El servidor Xtream dejó de enviar datos durante demasiado tiempo. Reintentá la carga de Series.'
                : rawError.replaceFirst('Exception: ', '');
            return _SeriesError(
              message: message,
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
    final categories = _parental.visibleGroups(_catalogCategories);
    final categoryCounts = <String, int>{};
    final visible = <XtreamSeriesSummary>[];
    var visibleTotal = 0;
    final normalized = _query.trim().toLowerCase();

    for (final item in data.series) {
      if (!_parental.canShowItem(name: item.name, group: item.category)) continue;
      visibleTotal++;
      final category = item.category?.trim();
      if (category != null && category.isNotEmpty) {
        categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
      }
      if (_category != null && item.category != _category) continue;
      if (normalized.isNotEmpty &&
          !item.name.toLowerCase().contains(normalized) &&
          !(item.genre?.toLowerCase().contains(normalized) ?? false) &&
          !(item.category?.toLowerCase().contains(normalized) ?? false)) {
        continue;
      }
      visible.add(item);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gridColumns = width >= 1500
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

        Widget grid() => visible.isEmpty
            ? const Center(child: Text('No hay resultados.'))
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: gridColumns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.62,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final series = visible[index];
                  return _SeriesPosterCard(
                    series: series,
                    onTap: () =>
                        unawaited(_openSeries(data.connection, series)),
                  );
                },
              );

        // En escritorio usamos exactamente el mismo patrón que TV/Películas:
        // categorías verticales, plegables y con borde redimensionable.
        if (width >= 760) {
          return Row(
            children: [
              SizedBox(
                width: _sidebarCollapsed ? 72 : _sidebarWidth,
                child: _SeriesCategorySidebar(
                  totalCount: visibleTotal,
                  categories: categories,
                  categoryCounts: categoryCounts,
                  selectedCategory: _category,
                  collapsed: _sidebarCollapsed,
                  onToggleCollapsed: _toggleSidebar,
                  onCategorySelected: (value) =>
                      unawaited(_selectCategory(value)),
                ),
              ),
              MouseRegion(
                cursor: _sidebarCollapsed
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: _sidebarCollapsed
                      ? null
                      : (details) => _resizeSidebar(details.delta.dx),
                  onHorizontalDragEnd:
                      _sidebarCollapsed ? null : (_) => _persistSidebar(),
                  child: Container(
                    width: 9,
                    alignment: Alignment.center,
                    child: Container(width: 1, color: Colors.white12),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SeriesCatalogToolbar(
                      query: _query,
                      visibleCount: visible.length,
                      selectedCategory: _category,
                      onQueryChanged: (value) => setState(() => _query = value),
                    ),
                    Expanded(child: grid()),
                  ],
                ),
              ),
            ],
          );
        }

        // En tamaños angostos evitamos una barra lateral que quite demasiado
        // espacio al póster, pero mantenemos categorías legibles con un selector.
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Buscar serie, género o categoría…',
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.folder_rounded),
                      labelText: 'Categoría',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todos'),
                      ),
                      ...categories.map(
                        (category) => DropdownMenuItem<String?>(
                          value: category,
                          child: Text(category, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (value) => unawaited(_selectCategory(value)),
                  ),
                ],
              ),
            ),
            Expanded(child: grid()),
          ],
        );
      },
    );
  }

}


class _SeriesCatalogToolbar extends StatelessWidget {
  final String query;
  final int visibleCount;
  final String? selectedCategory;
  final ValueChanged<String> onQueryChanged;

  const _SeriesCatalogToolbar({
    required this.query,
    required this.visibleCount,
    required this.selectedCategory,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedCategory ?? 'SERIES',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$visibleCount series',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white60,
                      ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 360,
            child: TextFormField(
              initialValue: query,
              decoration: InputDecoration(
                hintText: 'Buscar en series…',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.4,
                  ),
                ),
                isDense: true,
              ),
              onChanged: onQueryChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesCategorySidebar extends StatelessWidget {
  final int totalCount;
  final List<String> categories;
  final Map<String, int> categoryCounts;
  final String? selectedCategory;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<String?> onCategorySelected;

  const _SeriesCategorySidebar({
    required this.totalCount,
    required this.categories,
    required this.categoryCounts,
    required this.selectedCategory,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF081728),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment:
              collapsed ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                collapsed ? 8 : 20,
                18,
                collapsed ? 8 : 10,
                8,
              ),
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(
                    Icons.video_library_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Series',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Achicar categorías',
                      onPressed: onToggleCollapsed,
                      icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
                    ),
                  ],
                ],
              ),
            ),
            if (collapsed)
              IconButton(
                tooltip: 'Agrandar categorías',
                onPressed: onToggleCollapsed,
                icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'CATEGORÍAS',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Colors.white54,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                      ),
                    ),
                    const Tooltip(
                      message: 'Arrastrá el borde derecho para cambiar el ancho',
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: Colors.white30,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  collapsed ? 8 : 10,
                  0,
                  collapsed ? 8 : 10,
                  20,
                ),
                itemCount: categories.length + 1,
                itemBuilder: (context, index) {
                  final category = index == 0 ? null : categories[index - 1];
                  final label = category ?? 'Todos';
                  final selected = category == selectedCategory;
                  final count = category == null
                      ? totalCount
                      : (categoryCounts[category] ?? 0);

                  if (collapsed) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Tooltip(
                        message: '$label · $count',
                        child: Material(
                          color: selected
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.20)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => onCategorySelected(category),
                            child: SizedBox(
                              height: 52,
                              child: Icon(
                                category == null
                                    ? Icons.grid_view_rounded
                                    : Icons.folder_rounded,
                                size: 25,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Tooltip(
                      message: label,
                      waitDuration: const Duration(milliseconds: 450),
                      child: ListTile(
                        minTileHeight: 54,
                        selected: selected,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        selectedTileColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.20),
                        leading: Icon(
                          category == null
                              ? Icons.grid_view_rounded
                              : Icons.folder_rounded,
                          size: 24,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white70,
                        ),
                        title: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        onTap: () => onCategorySelected(category),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
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
  final ParentalControlService _parental = ParentalControlService.instance;

  @override
  void initState() {
    super.initState();
    _parental.addListener(_onParentalChanged);
    _future = XtreamSeriesService.fetchDetails(
      widget.connection,
      widget.summary,
    );
  }

  @override
  void dispose() {
    _parental.removeListener(_onParentalChanged);
    super.dispose();
  }

  void _onParentalChanged() {
    if (mounted) setState(() {});
  }

  bool get _blocked => _parental.isLocked && _parental.isProtectedItem(
        name: widget.summary.name,
        group: widget.summary.category,
      );

  Future<bool> _ensureParentalAccess() async {
    if (!_blocked) return true;
    return requestParentalUnlock(context);
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
      body: _blocked
          ? _SeriesParentalBlockedView(
              onUnlock: () => unawaited(requestParentalUnlock(context)),
            )
          : FutureBuilder<XtreamSeriesDetails>(
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
    if (!await _ensureParentalAccess() || !mounted) return;
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

class _SeriesParentalBlockedView extends StatelessWidget {
  final VoidCallback onUnlock;

  const _SeriesParentalBlockedView({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, size: 54),
                const SizedBox(height: 16),
                const Text(
                  'Contenido protegido',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ingresá el PIN parental para acceder a esta serie.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onUnlock,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Desbloquear'),
                ),
              ],
            ),
          ),
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
