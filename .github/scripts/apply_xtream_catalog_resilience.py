from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected 1 match, found {count}")
    p.write_text(text.replace(old, new, 1))


vod = "lib/services/xtream_vod_service.dart"
replace_once(
    vod,
    "import 'dart:convert';\n",
    "import 'dart:async';\nimport 'dart:convert';\n",
)
replace_once(
    vod,
    """  const XtreamVodSummary({
    required this.id,
    required this.name,
    required this.extension,
    this.cover,
    this.category,
    this.rating,
    this.releaseDate,
    this.genre,
    this.directSource,
  });
}
""",
    """  const XtreamVodSummary({
    required this.id,
    required this.name,
    required this.extension,
    this.cover,
    this.category,
    this.rating,
    this.releaseDate,
    this.genre,
    this.directSource,
  });

  Channel toChannel(XtreamConnectionResult connection) {
    final url = _resolveDirect(connection.streamServer, directSource) ??
        _movieUrl(connection, id, extension);
    return Channel(
      name: name,
      url: url,
      logoUrl: cover,
      group: category,
    );
  }
}
""",
)
replace_once(
    vod,
    """  const XtreamVodDetails({
    required this.movie,
    required this.extension,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.rating,
    this.duration,
    this.country,
    this.backdrop,
    this.trailerUrl,
    this.directSource,
  });

  Channel toChannel(XtreamConnectionResult connection) {
""",
    """  const XtreamVodDetails({
    required this.movie,
    required this.extension,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.rating,
    this.duration,
    this.country,
    this.backdrop,
    this.trailerUrl,
    this.directSource,
  });

  bool get hasPresentationMedia {
    final hasArtwork = (backdrop?.trim().isNotEmpty ?? false) ||
        (movie.cover?.trim().isNotEmpty ?? false);
    return hasArtwork || trailerChannel() != null;
  }

  Channel toChannel(XtreamConnectionResult connection) {
""",
)
replace_once(
    vod,
    """  static Future<List<XtreamVodSummary>> fetchCatalog(
    XtreamConnectionResult connection, {
    Duration timeout = const Duration(seconds: 18),
  }) async {
    final results = await Future.wait<List<dynamic>>([
      _actionList(connection, 'get_vod_categories', timeout),
      _actionList(connection, 'get_vod_streams', timeout),
    ]);
    final categories = _categoryMap(results[0]);
    final movies = <XtreamVodSummary>[];
    for (final raw in results[1]) {
""",
    """  static Future<List<XtreamVodSummary>> fetchCatalog(
    XtreamConnectionResult connection, {
    Duration timeout = const Duration(seconds: 35),
  }) async {
    final categoriesFuture = _safeActionList(
      connection,
      'get_vod_categories',
      const Duration(seconds: 12),
    );
    final streams = await _actionList(connection, 'get_vod_streams', timeout);
    final categories = _categoryMap(await categoriesFuture);
    final movies = <XtreamVodSummary>[];
    for (final raw in streams) {
""",
)
replace_once(
    vod,
    """          category: categoryId == null ? null : categories[categoryId],
""",
    """          category: categoryId == null
              ? _firstText(item, const ['category_name', 'category'])
              : categories[categoryId] ??
                  _firstText(item, const ['category_name', 'category']),
""",
)
replace_once(
    vod,
    """  static Future<List<dynamic>> _actionList(
    XtreamConnectionResult connection,
    String action,
    Duration timeout,
  ) async {
""",
    """  static Future<List<dynamic>> _safeActionList(
    XtreamConnectionResult connection,
    String action,
    Duration timeout,
  ) async {
    try {
      return await _actionList(connection, action, timeout);
    } on TimeoutException {
      return const <dynamic>[];
    } on FormatException {
      return const <dynamic>[];
    } catch (_) {
      return const <dynamic>[];
    }
  }

  static Future<List<dynamic>> _actionList(
    XtreamConnectionResult connection,
    String action,
    Duration timeout,
  ) async {
""",
)

movies = "lib/screens/xtream_movies_screen.dart"
replace_once(
    movies,
    """  Future<void> _openMovie(
    XtreamConnectionResult connection,
    XtreamVodSummary movie,
  ) async {
    if (_parental.isLocked &&
        _parental.isProtectedItem(name: movie.name, group: movie.category)) {
      final unlocked = await requestParentalUnlock(context);
      if (!unlocked || !mounted) return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => XtreamMovieDetailScreen(
          connection: connection,
          movie: movie,
        ),
      ),
    );
  }
""",
    """  Future<void> _openMovie(
    XtreamConnectionResult connection,
    XtreamVodSummary movie,
  ) async {
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
      if (!details.hasPresentationMedia) {
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
    final channel = details?.toChannel(connection) ?? movie.toChannel(connection);
    final provider = context.read<IptvProvider>();
    await Navigator.of(context).push(
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
""",
)
replace_once(
    movies,
    """class XtreamMovieDetailScreen extends StatefulWidget {
  final XtreamConnectionResult connection;
  final XtreamVodSummary movie;

  const XtreamMovieDetailScreen({
    super.key,
    required this.connection,
    required this.movie,
  });
""",
    """class XtreamMovieDetailScreen extends StatefulWidget {
  final XtreamConnectionResult connection;
  final XtreamVodSummary movie;
  final XtreamVodDetails? initialDetails;

  const XtreamMovieDetailScreen({
    super.key,
    required this.connection,
    required this.movie,
    this.initialDetails,
  });
""",
)
replace_once(
    movies,
    """    _parental.addListener(_onParentalChanged);
    _future = XtreamVodService.fetchDetails(widget.connection, widget.movie);
""",
    """    _parental.addListener(_onParentalChanged);
    _future = widget.initialDetails != null
        ? Future<XtreamVodDetails>.value(widget.initialDetails!)
        : XtreamVodService.fetchDetails(widget.connection, widget.movie);
""",
)

series = "lib/services/xtream_series_service.dart"
replace_once(
    series,
    """    final results = await Future.wait<List<dynamic>>([
      _actionList(connection, 'get_series_categories', timeout),
      _actionList(connection, 'get_series', timeout),
    ]);

    final categories = <String, String>{};
    for (final raw in results[0]) {
""",
    """    final categoriesFuture = _safeActionList(
      connection,
      'get_series_categories',
      const Duration(seconds: 12),
    );
    final rawSeries = await _actionList(connection, 'get_series', timeout);
    final rawCategories = await categoriesFuture;

    final categories = <String, String>{};
    for (final raw in rawCategories) {
""",
)
replace_once(
    series,
    """    for (final raw in results[1]) {
""",
    """    for (final raw in rawSeries) {
""",
)
replace_once(
    series,
    """      final categoryId = item['category_id']?.toString();
      series.add(
        XtreamSeriesSummary(
          id: id,
          name: name,
          cover: _cleanText(item['cover']),
          category: categoryId == null ? null : categories[categoryId],
""",
    """      final categoryId = _cleanText(item['category_id']);
      final categoryName = _firstText(
        item,
        const ['category_name', 'category'],
      );
      series.add(
        XtreamSeriesSummary(
          id: id,
          name: name,
          cover: _cleanText(item['cover']),
          category: categoryId == null
              ? categoryName
              : categories[categoryId] ?? categoryName,
""",
)
replace_once(
    series,
    """  static Future<List<dynamic>> _actionList(
    XtreamConnectionResult connection,
    String action,
    Duration timeout,
  ) async {
""",
    """  static Future<List<dynamic>> _safeActionList(
    XtreamConnectionResult connection,
    String action,
    Duration timeout,
  ) async {
    try {
      return await _actionList(connection, action, timeout);
    } on TimeoutException {
      return const <dynamic>[];
    } catch (_) {
      return const <dynamic>[];
    }
  }

  static Future<List<dynamic>> _actionList(
    XtreamConnectionResult connection,
    String action,
    Duration timeout,
  ) async {
""",
)

checks = {
    vod: [
        "Duration timeout = const Duration(seconds: 35)",
        "bool get hasPresentationMedia",
    ],
    movies: [
        "Future<void> _playMovieDirect(",
        "initialDetails: details",
    ],
    series: [
        "final categoryId = _cleanText(item['category_id']);",
        "final rawCategories = await categoriesFuture;",
    ],
}
for path, needles in checks.items():
    text = Path(path).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"{path}: missing validation marker {needle}")
