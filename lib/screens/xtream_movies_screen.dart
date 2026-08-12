import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../providers/iptv_provider.dart';
import '../services/parental_control_service.dart';
import '../services/xtream_fast_catalog_service.dart';
import '../services/xtream_service.dart';
import '../services/xtream_vod_service.dart';
import '../widgets/cached_artwork_image.dart';
import '../widgets/parental_lock_button.dart';
import '../widgets/parental_unlock_dialog.dart';
import '../services/player_route_guard.dart';
import 'player_screen.dart';

class XtreamMoviesScreen extends StatefulWidget {
  final Playlist playlist;

  const XtreamMoviesScreen({super.key, required this.playlist});

  @override
  State<XtreamMoviesScreen> createState() => _XtreamMoviesScreenState();
}

class _XtreamMoviesScreenState extends State<XtreamMoviesScreen> {
  late Future<_MovieCatalogData> _future;
  String _query = '';
  String? _category;
  double _sidebarWidth = 320;
  bool _sidebarCollapsed = false;
  final ParentalControlService _parental = ParentalControlService.instance;
  List<String> _catalogCategories = const <String>[];
  String _progressLabel = 'Cargando información del servidor…';
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastProgressBytes = 0;

  static const double _sidebarMinWidth = 230;
  static const double _sidebarMaxWidth = 480;
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

  Future<_MovieCatalogData> _load({bool forceNetwork = false}) async {
    await _parental.init();
    final fast = XtreamFastCatalogService.instance;

    try {
      final fresh = await fast.refreshMovies(
        widget.playlist.source,
        forceSessionRefresh: forceNetwork,
        onProgress: _onCatalogProgress,
      );
      _setCatalogCategories(fresh.categories);
      return _MovieCatalogData(
        connection: fresh.connection,
        movies: fresh.movies,
      );
    } catch (_) {
      // La copia local es únicamente respaldo/offline. Nunca dispara una
      // actualización pesada escondida detrás de la interfaz.
      final cached = await fast.loadCachedMovies(widget.playlist.source);
      if (cached != null && cached.movies.isNotEmpty) {
        _setCatalogCategories(cached.categories);
        return _MovieCatalogData(
          connection: cached.connection,
          movies: cached.movies,
        );
      }
      rethrow;
    }
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

  Future<void> _loadSidebarPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sidebarWidth = (prefs.getDouble(_sidebarWidthKey) ?? 320)
          .clamp(_sidebarMinWidth, _sidebarMaxWidth)
          .toDouble();
      _sidebarCollapsed = prefs.getBool(_sidebarCollapsedKey) ?? false;
    });
  }

  Future<void> _persistSidebar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_sidebarWidthKey, _sidebarWidth);
    await prefs.setBool(_sidebarCollapsedKey, _sidebarCollapsed);
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

  void _toggleSidebar() {
    setState(() => _sidebarCollapsed = !_sidebarCollapsed);
    _persistSidebar();
  }

  void _resizeSidebar(double delta) {
    if (_sidebarCollapsed) return;
    setState(() {
      _sidebarWidth = (_sidebarWidth + delta)
          .clamp(_sidebarMinWidth, _sidebarMaxWidth)
          .toDouble();
    });
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

  Future<void> _openMovie(
    XtreamConnectionResult connection,
    XtreamVodSummary movie, {
    required bool artworkAvailable,
  }) async {
    if (_parental.isLocked &&
        _parental.isProtectedItem(name: movie.name, group: movie.category)) {
      final unlocked = await requestParentalUnlock(context);
      if (!unlocked || !mounted) return;
    }

    try {
      final details = await XtreamVodService.fetchDetails(
        connection,
        movie,
        timeout: const Duration(seconds: 12),
      );
      if (!mounted) return;
      // No abrimos una ficha vacía por una URL de imagen rota. La ficha se
      // conserva sólo si la tarjeta cargó una carátula real o existe tráiler.
      if (!artworkAvailable && details.trailerChannel() == null) {
        await _playMovieDirect(connection, movie, details: details);
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => XtreamMovieDetailScreen(
            connection: connection,
            movie: movie,
            initialDetails: details,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await _playMovieDirect(connection, movie);
    }
  }

  Future<void> _playMovieDirect(
    XtreamConnectionResult connection,
    XtreamVodSummary movie, {
    XtreamVodDetails? details,
  }) async {
    final channel =
        details?.toChannel(connection) ?? movie.toChannel(connection);
    final provider = context.read<IptvProvider>();
    await PlayerRouteGuard.push(
      context,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Películas',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
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
              hiddenCategoryCount: _parental.hiddenGroupCount(
                _catalogCategories,
              ),
              onPressed: () => unawaited(_toggleParentalLock()),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<_MovieCatalogData>(
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
                ? 'El servidor Xtream dejó de enviar datos durante demasiado tiempo. Reintentá la carga de Películas.'
                : rawError.replaceFirst('Exception: ', '');
            return _MovieError(message: message, onRetry: _retry);
          }
          final data = snapshot.data!;
          if (data.movies.isEmpty) {
            return _MovieError(
              message:
                  'El servidor Xtream no devolvió películas mediante get_vod_streams.',
              onRetry: _retry,
            );
          }
          return _buildCatalog(data);
        },
      ),
    );
  }

  Widget _buildCatalog(_MovieCatalogData data) {
    final categories = _parental.visibleGroups(_catalogCategories);
    final categoryCounts = <String, int>{};
    final visible = <XtreamVodSummary>[];
    var visibleTotal = 0;
    final normalized = _query.trim().toLowerCase();

    // Una sola pasada: parental + conteos + categoría + búsqueda.
    for (final item in data.movies) {
      if (!_parental.canShowItem(name: item.name, group: item.category))
        continue;
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
                  final movie = visible[index];
                  return _MoviePosterCard(
                    movie: movie,
                    onTap: (artworkAvailable) => unawaited(
                      _openMovie(
                        data.connection,
                        movie,
                        artworkAvailable: artworkAvailable,
                      ),
                    ),
                  );
                },
              );

        if (width >= 760) {
          return Row(
            children: [
              SizedBox(
                width: _sidebarCollapsed ? 72 : _sidebarWidth,
                child: _MovieCategorySidebar(
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
                  onHorizontalDragEnd: _sidebarCollapsed
                      ? null
                      : (_) => _persistSidebar(),
                  child: Container(
                    width: 9,
                    alignment: Alignment.center,
                    child: Container(width: 1, color: Colors.white12),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    _MovieCatalogToolbar(
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

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Buscar película, género o categoría…',
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
                          child: Text(
                            category,
                            overflow: TextOverflow.ellipsis,
                          ),
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

class XtreamMovieDetailScreen extends StatefulWidget {
  final XtreamConnectionResult connection;
  final XtreamVodSummary movie;
  final XtreamVodDetails? initialDetails;

  const XtreamMovieDetailScreen({
    super.key,
    required this.connection,
    required this.movie,
    this.initialDetails,
  });

  @override
  State<XtreamMovieDetailScreen> createState() =>
      _XtreamMovieDetailScreenState();
}

class _XtreamMovieDetailScreenState extends State<XtreamMovieDetailScreen> {
  late Future<XtreamVodDetails> _future;
  final ParentalControlService _parental = ParentalControlService.instance;

  @override
  void initState() {
    super.initState();
    _parental.addListener(_onParentalChanged);
    _future = widget.initialDetails != null
        ? Future<XtreamVodDetails>.value(widget.initialDetails!)
        : XtreamVodService.fetchDetails(widget.connection, widget.movie);
  }

  @override
  void dispose() {
    _parental.removeListener(_onParentalChanged);
    super.dispose();
  }

  void _onParentalChanged() {
    if (mounted) setState(() {});
  }

  bool get _blocked =>
      _parental.isLocked &&
      _parental.isProtectedItem(
        name: widget.movie.name,
        group: widget.movie.category,
      );

  Future<bool> _ensureParentalAccess() async {
    if (!_blocked) return true;
    return requestParentalUnlock(context);
  }

  void _retry() => setState(() {
    _future = XtreamVodService.fetchDetails(widget.connection, widget.movie);
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.movie.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _blocked
          ? _NativeParentalBlockedView(
              label: 'película',
              onUnlock: () => unawaited(requestParentalUnlock(context)),
            )
          : FutureBuilder<XtreamVodDetails>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 14),
                        Text('Cargando información de la película…'),
                      ],
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _MovieError(
                    message: snapshot.error.toString().replaceFirst(
                      'Exception: ',
                      '',
                    ),
                    onRetry: _retry,
                  );
                }
                final details = snapshot.data!;
                return LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= 980
                      ? _buildWide(details)
                      : _buildCompact(details),
                );
              },
            ),
    );
  }

  Widget _buildWide(XtreamVodDetails details) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 340, child: _MoviePoster(details: details)),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              children: [
                _MovieHero(
                  details: details,
                  onPlay: () => _play(details),
                  onTrailer: details.trailerChannel() == null
                      ? null
                      : () => _playTrailer(details),
                ),
                const SizedBox(height: 18),
                _MovieMetadata(details: details),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(XtreamVodDetails details) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(height: 520, child: _MoviePoster(details: details)),
        const SizedBox(height: 16),
        _MovieHero(
          details: details,
          compact: true,
          onPlay: () => _play(details),
          onTrailer: details.trailerChannel() == null
              ? null
              : () => _playTrailer(details),
        ),
        const SizedBox(height: 16),
        _MovieMetadata(details: details),
      ],
    );
  }

  Future<void> _play(XtreamVodDetails details) async {
    if (!await _ensureParentalAccess() || !mounted) return;
    final channel = details.toChannel(widget.connection);
    final provider = context.read<IptvProvider>();
    await PlayerRouteGuard.push(
      context,
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

  Future<void> _playTrailer(XtreamVodDetails details) async {
    if (!await _ensureParentalAccess() || !mounted) return;
    final trailer = details.trailerChannel();
    if (trailer == null) return;
    final provider = context.read<IptvProvider>();
    await PlayerRouteGuard.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          channel: trailer,
          playlist: [trailer],
          initialIndex: 0,
          settings: provider.playbackSettings,
          isLiveContent: false,
        ),
      ),
    );
  }
}

class _NativeParentalBlockedView extends StatelessWidget {
  final String label;
  final VoidCallback onUnlock;

  const _NativeParentalBlockedView({
    required this.label,
    required this.onUnlock,
  });

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
                Text(
                  'Ingresá el PIN parental para acceder a esta $label.',
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

class _MovieCatalogData {
  final XtreamConnectionResult connection;
  final List<XtreamVodSummary> movies;

  const _MovieCatalogData({required this.connection, required this.movies});
}

class _MoviePosterCard extends StatefulWidget {
  final XtreamVodSummary movie;
  final ValueChanged<bool> onTap;

  const _MoviePosterCard({required this.movie, required this.onTap});

  @override
  State<_MoviePosterCard> createState() => _MoviePosterCardState();
}

class _MoviePosterCardState extends State<_MoviePosterCard> {
  bool _artworkAvailable = false;

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onTap(_artworkAvailable),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedArtworkImage(
                    url: movie.cover,
                    fit: BoxFit.cover,
                    onAvailabilityChanged: (available) {
                      _artworkAvailable = available;
                    },
                    fallback: const ColoredBox(
                      color: Color(0xFF111C2C),
                      child: Center(child: Icon(Icons.movie_rounded, size: 46)),
                    ),
                  ),
                  if (movie.rating != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 16),
                            const SizedBox(width: 3),
                            Text(
                              movie.rating!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Text(
                movie.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                movie.category ?? movie.genre ?? 'Película',
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

class _MoviePoster extends StatelessWidget {
  final XtreamVodDetails details;

  const _MoviePoster({required this.details});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 0.67,
        child: CachedArtworkImage(
          url: details.movie.cover,
          fit: BoxFit.cover,
          fallback: const ColoredBox(
            color: Color(0xFF111C2C),
            child: Center(child: Icon(Icons.movie_rounded, size: 72)),
          ),
        ),
      ),
    );
  }
}

class _MovieHero extends StatelessWidget {
  final XtreamVodDetails details;
  final VoidCallback onPlay;
  final VoidCallback? onTrailer;
  final bool compact;

  const _MovieHero({
    required this.details,
    required this.onPlay,
    this.onTrailer,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: compact ? 310 : 390,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedArtworkImage(
              url: details.backdrop ?? details.movie.cover,
              fit: BoxFit.cover,
              fallback: const ColoredBox(color: Color(0xFF101B2B)),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(compact ? 20 : 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    details.movie.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (compact
                                ? Theme.of(context).textTheme.headlineSmall
                                : Theme.of(context).textTheme.headlineMedium)
                            ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      if (details.releaseDate != null)
                        Text(details.releaseDate!),
                      if (details.genre != null) Text(details.genre!),
                      if (details.duration != null) Text(details.duration!),
                      if (details.rating != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 18),
                            const SizedBox(width: 4),
                            Text(details.rating!),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: onPlay,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Reproducir'),
                      ),
                      if (onTrailer != null)
                        OutlinedButton.icon(
                          onPressed: onTrailer,
                          icon: const Icon(Icons.movie_filter_rounded),
                          label: const Text('Ver tráiler'),
                        ),
                    ],
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

class _MovieMetadata extends StatelessWidget {
  final XtreamVodDetails details;

  const _MovieMetadata({required this.details});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void add(String label, String? value) {
      final text = value?.trim() ?? '';
      if (text.isEmpty) return;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyLarge,
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      );
    }

    add('Fecha de lanzamiento', details.releaseDate);
    add('Género', details.genre ?? details.movie.category);
    add('Descripción', details.plot);
    add('Director', details.director);
    add('Actores', details.cast);
    add('País', details.country);
    add('Duración', details.duration);

    if (rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'El servidor no proporcionó metadatos adicionales para esta película.',
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }
}

class _MovieCatalogToolbar extends StatelessWidget {
  final int visibleCount;
  final String? selectedCategory;
  final ValueChanged<String> onQueryChanged;

  const _MovieCatalogToolbar({
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
                  selectedCategory ?? 'PELÍCULAS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$visibleCount películas',
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 360,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar en películas…',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: onQueryChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _MovieCategorySidebar extends StatelessWidget {
  final int totalCount;
  final List<String> categories;
  final Map<String, int> categoryCounts;
  final String? selectedCategory;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<String?> onCategorySelected;

  const _MovieCategorySidebar({
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
          crossAxisAlignment: collapsed
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
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
                    Icons.movie_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Películas',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Achicar categorías',
                      onPressed: onToggleCollapsed,
                      icon: const Icon(
                        Icons.keyboard_double_arrow_left_rounded,
                      ),
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
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'CATEGORÍAS',
                        style: TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    Tooltip(
                      message:
                          'Arrastrá el borde derecho para cambiar el ancho',
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
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.20)
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
                      child: ListTile(
                        minTileHeight: 54,
                        selected: selected,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.20),
                        leading: Icon(
                          category == null
                              ? Icons.grid_view_rounded
                              : Icons.folder_rounded,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white70,
                        ),
                        title: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
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

class _MovieError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _MovieError({required this.message, required this.onRetry});

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
                const Icon(Icons.error_outline_rounded, size: 44),
                const SizedBox(height: 14),
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
