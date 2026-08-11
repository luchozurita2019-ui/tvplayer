from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Missing patch anchor: {label}')
    return text.replace(old, new, 1)

# ---------------- Movies ----------------
path = Path('lib/screens/xtream_movies_screen.dart')
text = path.read_text()
text = replace_once(
    text,
    "import 'package:flutter/material.dart';",
    "import 'dart:async';\n\nimport 'package:flutter/material.dart';",
    'movies dart async',
)
text = replace_once(
    text,
    "import '../services/xtream_service.dart';",
    "import '../services/parental_control_service.dart';\nimport '../services/xtream_service.dart';",
    'movies parental import',
)
text = replace_once(
    text,
    "import '../widgets/cached_artwork_image.dart';",
    "import '../widgets/cached_artwork_image.dart';\nimport '../widgets/parental_unlock_dialog.dart';",
    'movies unlock import',
)
text = replace_once(
    text,
    "  bool _sidebarCollapsed = false;\n\n  static const double _sidebarMinWidth",
    "  bool _sidebarCollapsed = false;\n  final ParentalControlService _parental = ParentalControlService.instance;\n\n  static const double _sidebarMinWidth",
    'movies parental field',
)
text = replace_once(
    text,
    "  void initState() {\n    super.initState();\n    _future = _load();\n    _loadSidebarPreferences();\n  }",
    "  void initState() {\n    super.initState();\n    _parental.addListener(_onParentalChanged);\n    _future = _load();\n    _loadSidebarPreferences();\n  }\n\n  @override\n  void dispose() {\n    _parental.removeListener(_onParentalChanged);\n    super.dispose();\n  }\n\n  void _onParentalChanged() {\n    if (!mounted) return;\n    if (_category != null &&\n        _parental.isLocked &&\n        _parental.isProtectedGroup(_category)) {\n      _category = null;\n    }\n    setState(() {});\n  }",
    'movies lifecycle',
)
text = replace_once(
    text,
    "  Future<_MovieCatalogData> _load() async {\n    final connection =",
    "  Future<_MovieCatalogData> _load() async {\n    await _parental.init();\n    final connection =",
    'movies init parental load',
)
text = replace_once(
    text,
    "  void _resizeSidebar(double delta) {\n    if (_sidebarCollapsed) return;\n    setState(() {\n      _sidebarWidth = (_sidebarWidth + delta)\n          .clamp(_sidebarMinWidth, _sidebarMaxWidth)\n          .toDouble();\n    });\n  }\n\n  @override",
    "  void _resizeSidebar(double delta) {\n    if (_sidebarCollapsed) return;\n    setState(() {\n      _sidebarWidth = (_sidebarWidth + delta)\n          .clamp(_sidebarMinWidth, _sidebarMaxWidth)\n          .toDouble();\n    });\n  }\n\n  Future<void> _selectCategory(String? category) async {\n    if (category != null &&\n        _parental.isLocked &&\n        _parental.isProtectedGroup(category)) {\n      final unlocked = await requestParentalUnlock(context);\n      if (!unlocked || !mounted) return;\n    }\n    setState(() => _category = category);\n  }\n\n  Future<void> _toggleParentalLock() async {\n    if (_parental.isUnlocked) {\n      _parental.lockNow();\n      return;\n    }\n    await requestParentalUnlock(context);\n  }\n\n  Future<void> _openMovie(\n    XtreamConnectionResult connection,\n    XtreamVodSummary movie,\n  ) async {\n    if (_parental.isLocked &&\n        _parental.isProtectedItem(name: movie.name, group: movie.category)) {\n      final unlocked = await requestParentalUnlock(context);\n      if (!unlocked || !mounted) return;\n    }\n    await Navigator.of(context).push(\n      MaterialPageRoute(\n        builder: (_) => XtreamMovieDetailScreen(\n          connection: connection,\n          movie: movie,\n        ),\n      ),\n    );\n  }\n\n  @override",
    'movies parental methods',
)
text = replace_once(
    text,
    "        ),\n      ),\n      body: FutureBuilder<_MovieCatalogData>(",
    "        ),\n        actions: [\n          if (_parental.enabled)\n            IconButton(\n              icon: Icon(\n                _parental.isUnlocked\n                    ? Icons.lock_open_rounded\n                    : Icons.lock_rounded,\n              ),\n              tooltip: _parental.isUnlocked\n                  ? 'Bloquear contenido protegido'\n                  : 'Desbloquear contenido protegido',\n              onPressed: () => unawaited(_toggleParentalLock()),\n            ),\n          const SizedBox(width: 8),\n        ],\n      ),\n      body: FutureBuilder<_MovieCatalogData>(",
    'movies appbar lock',
)
text = replace_once(
    text,
    "    final categories = data.movies\n        .map((item) => item.category)\n        .whereType<String>()\n        .where((value) => value.trim().isNotEmpty)\n        .toSet()\n        .toList()\n      ..sort();\n    final categoryCounts = <String, int>{};\n    for (final item in data.movies) {\n      final category = item.category?.trim();\n      if (category == null || category.isEmpty) continue;\n      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;\n    }",
    "    final allCategories = data.movies\n        .map((item) => item.category)\n        .whereType<String>()\n        .where((value) => value.trim().isNotEmpty)\n        .toSet()\n        .toList()\n      ..sort();\n    final categories = _parental.visibleGroups(allCategories);\n    final categoryCounts = <String, int>{};\n    for (final item in data.movies) {\n      if (!_parental.canShowItem(name: item.name, group: item.category)) continue;\n      final category = item.category?.trim();\n      if (category == null || category.isEmpty) continue;\n      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;\n    }\n    final visibleTotal = data.movies\n        .where((item) =>\n            _parental.canShowItem(name: item.name, group: item.category))\n        .length;",
    'movies categories filter',
)
text = replace_once(
    text,
    "    final visible = data.movies.where((item) {\n      if (_category != null",
    "    final visible = data.movies.where((item) {\n      if (!_parental.canShowItem(name: item.name, group: item.category)) {\n        return false;\n      }\n      if (_category != null",
    'movies item filter',
)
text = replace_once(
    text,
    "                    onTap: () => Navigator.of(context).push(\n                      MaterialPageRoute(\n                        builder: (_) => XtreamMovieDetailScreen(\n                          connection: data.connection,\n                          movie: movie,\n                        ),\n                      ),\n                    ),",
    "                    onTap: () =>\n                        unawaited(_openMovie(data.connection, movie)),",
    'movies open item',
)
text = replace_once(text, 'totalCount: data.movies.length,', 'totalCount: visibleTotal,', 'movies total visible')
text = replace_once(
    text,
    "                  onCategorySelected: (value) => setState(() => _category = value),",
    "                  onCategorySelected: (value) =>\n                      unawaited(_selectCategory(value)),",
    'movies sidebar selection',
)
text = replace_once(
    text,
    "                    onChanged: (value) => setState(() => _category = value),",
    "                    onChanged: (value) => unawaited(_selectCategory(value)),",
    'movies dropdown selection',
)

# Movie detail must re-lock if PIN expires.
text = replace_once(
    text,
    "class _XtreamMovieDetailScreenState extends State<XtreamMovieDetailScreen> {\n  late Future<XtreamVodDetails> _future;",
    "class _XtreamMovieDetailScreenState extends State<XtreamMovieDetailScreen> {\n  late Future<XtreamVodDetails> _future;\n  final ParentalControlService _parental = ParentalControlService.instance;",
    'movie detail parental field',
)
text = replace_once(
    text,
    "  void initState() {\n    super.initState();\n    _future = XtreamVodService.fetchDetails(widget.connection, widget.movie);\n  }",
    "  void initState() {\n    super.initState();\n    _parental.addListener(_onParentalChanged);\n    _future = XtreamVodService.fetchDetails(widget.connection, widget.movie);\n  }\n\n  @override\n  void dispose() {\n    _parental.removeListener(_onParentalChanged);\n    super.dispose();\n  }\n\n  void _onParentalChanged() {\n    if (mounted) setState(() {});\n  }\n\n  bool get _blocked => _parental.isLocked && _parental.isProtectedItem(\n        name: widget.movie.name,\n        group: widget.movie.category,\n      );\n\n  Future<bool> _ensureParentalAccess() async {\n    if (!_blocked) return true;\n    return requestParentalUnlock(context);\n  }",
    'movie detail lifecycle',
)
text = replace_once(
    text,
    "      body: FutureBuilder<XtreamVodDetails>(",
    "      body: _blocked\n          ? _NativeParentalBlockedView(\n              label: 'película',\n              onUnlock: () => unawaited(requestParentalUnlock(context)),\n            )\n          : FutureBuilder<XtreamVodDetails>(",
    'movie detail blocked body',
)
text = replace_once(
    text,
    "  Future<void> _play(XtreamVodDetails details) async {\n    final channel =",
    "  Future<void> _play(XtreamVodDetails details) async {\n    if (!await _ensureParentalAccess() || !mounted) return;\n    final channel =",
    'movie play guard',
)
text = replace_once(
    text,
    "  Future<void> _playTrailer(XtreamVodDetails details) async {\n    final trailer =",
    "  Future<void> _playTrailer(XtreamVodDetails details) async {\n    if (!await _ensureParentalAccess() || !mounted) return;\n    final trailer =",
    'movie trailer guard',
)
# Shared blocked view inside movie file.
anchor = "class _MovieCatalogData {"
blocked_widget = """class _NativeParentalBlockedView extends StatelessWidget {
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

"""
text = replace_once(text, anchor, blocked_widget + anchor, 'movie blocked widget')
path.write_text(text)

# ---------------- Series ----------------
path = Path('lib/screens/xtream_series_screen.dart')
text = path.read_text()
text = replace_once(
    text,
    "import 'package:flutter/material.dart';",
    "import 'dart:async';\n\nimport 'package:flutter/material.dart';",
    'series dart async',
)
text = replace_once(
    text,
    "import '../services/xtream_series_service.dart';",
    "import '../services/parental_control_service.dart';\nimport '../services/xtream_series_service.dart';",
    'series parental import',
)
text = replace_once(
    text,
    "import '../widgets/cached_artwork_image.dart';",
    "import '../widgets/cached_artwork_image.dart';\nimport '../widgets/parental_unlock_dialog.dart';",
    'series unlock import',
)
text = replace_once(
    text,
    "  bool _sidebarCollapsed = false;\n\n  static const double _sidebarMinWidth",
    "  bool _sidebarCollapsed = false;\n  final ParentalControlService _parental = ParentalControlService.instance;\n\n  static const double _sidebarMinWidth",
    'series parental field',
)
text = replace_once(
    text,
    "  void initState() {\n    super.initState();\n    _future = _load();\n    _loadSidebarPreferences();\n  }",
    "  void initState() {\n    super.initState();\n    _parental.addListener(_onParentalChanged);\n    _future = _load();\n    _loadSidebarPreferences();\n  }\n\n  @override\n  void dispose() {\n    _parental.removeListener(_onParentalChanged);\n    super.dispose();\n  }\n\n  void _onParentalChanged() {\n    if (!mounted) return;\n    if (_category != null &&\n        _parental.isLocked &&\n        _parental.isProtectedGroup(_category)) {\n      _category = null;\n    }\n    setState(() {});\n  }",
    'series lifecycle',
)
text = replace_once(
    text,
    "  Future<_SeriesCatalogData> _load() async {\n    final connection =",
    "  Future<_SeriesCatalogData> _load() async {\n    await _parental.init();\n    final connection =",
    'series init parental load',
)
text = replace_once(
    text,
    "  void _toggleSidebar() {\n    setState(() => _sidebarCollapsed = !_sidebarCollapsed);\n    _persistSidebar();\n  }\n\n  Future<_SeriesCatalogData>",
    "  void _toggleSidebar() {\n    setState(() => _sidebarCollapsed = !_sidebarCollapsed);\n    _persistSidebar();\n  }\n\n  Future<void> _selectCategory(String? category) async {\n    if (category != null &&\n        _parental.isLocked &&\n        _parental.isProtectedGroup(category)) {\n      final unlocked = await requestParentalUnlock(context);\n      if (!unlocked || !mounted) return;\n    }\n    setState(() => _category = category);\n  }\n\n  Future<void> _toggleParentalLock() async {\n    if (_parental.isUnlocked) {\n      _parental.lockNow();\n      return;\n    }\n    await requestParentalUnlock(context);\n  }\n\n  Future<void> _openSeries(\n    XtreamConnectionResult connection,\n    XtreamSeriesSummary series,\n  ) async {\n    if (_parental.isLocked &&\n        _parental.isProtectedItem(name: series.name, group: series.category)) {\n      final unlocked = await requestParentalUnlock(context);\n      if (!unlocked || !mounted) return;\n    }\n    await Navigator.of(context).push(\n      MaterialPageRoute(\n        builder: (_) => XtreamSeriesDetailScreen(\n          connection: connection,\n          summary: series,\n        ),\n      ),\n    );\n  }\n\n  Future<_SeriesCatalogData>",
    'series parental methods',
)
text = replace_once(
    text,
    "        ),\n      ),\n      body: FutureBuilder<_SeriesCatalogData>(",
    "        ),\n        actions: [\n          if (_parental.enabled)\n            IconButton(\n              icon: Icon(\n                _parental.isUnlocked\n                    ? Icons.lock_open_rounded\n                    : Icons.lock_rounded,\n              ),\n              tooltip: _parental.isUnlocked\n                  ? 'Bloquear contenido protegido'\n                  : 'Desbloquear contenido protegido',\n              onPressed: () => unawaited(_toggleParentalLock()),\n            ),\n          const SizedBox(width: 8),\n        ],\n      ),\n      body: FutureBuilder<_SeriesCatalogData>(",
    'series appbar lock',
)
text = replace_once(
    text,
    "    final categories = data.series\n        .map((item) => item.category)\n        .whereType<String>()\n        .where((value) => value.trim().isNotEmpty)\n        .toSet()\n        .toList()\n      ..sort();\n    final categoryCounts = <String, int>{};\n    for (final item in data.series) {\n      final category = item.category?.trim();\n      if (category == null || category.isEmpty) continue;\n      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;\n    }",
    "    final allCategories = data.series\n        .map((item) => item.category)\n        .whereType<String>()\n        .where((value) => value.trim().isNotEmpty)\n        .toSet()\n        .toList()\n      ..sort();\n    final categories = _parental.visibleGroups(allCategories);\n    final categoryCounts = <String, int>{};\n    for (final item in data.series) {\n      if (!_parental.canShowItem(name: item.name, group: item.category)) continue;\n      final category = item.category?.trim();\n      if (category == null || category.isEmpty) continue;\n      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;\n    }\n    final visibleTotal = data.series\n        .where((item) =>\n            _parental.canShowItem(name: item.name, group: item.category))\n        .length;",
    'series categories filter',
)
text = replace_once(
    text,
    "    final visible = data.series.where((item) {\n      if (_category != null",
    "    final visible = data.series.where((item) {\n      if (!_parental.canShowItem(name: item.name, group: item.category)) {\n        return false;\n      }\n      if (_category != null",
    'series item filter',
)
text = replace_once(
    text,
    "                    onTap: () => Navigator.of(context).push(\n                      MaterialPageRoute(\n                        builder: (_) => XtreamSeriesDetailScreen(\n                          connection: data.connection,\n                          summary: series,\n                        ),\n                      ),\n                    ),",
    "                    onTap: () =>\n                        unawaited(_openSeries(data.connection, series)),",
    'series open item',
)
text = replace_once(text, 'totalCount: data.series.length,', 'totalCount: visibleTotal,', 'series total visible')
text = replace_once(
    text,
    "                  onCategorySelected: (value) =>\n                      setState(() => _category = value),",
    "                  onCategorySelected: (value) =>\n                      unawaited(_selectCategory(value)),",
    'series sidebar selection',
)
text = replace_once(
    text,
    "                    onChanged: (value) => setState(() => _category = value),",
    "                    onChanged: (value) => unawaited(_selectCategory(value)),",
    'series dropdown selection',
)

# Series detail guard when PIN expires.
text = replace_once(
    text,
    "class _XtreamSeriesDetailScreenState extends State<XtreamSeriesDetailScreen> {\n  late Future<XtreamSeriesDetails> _future;\n  int? _selectedSeason;",
    "class _XtreamSeriesDetailScreenState extends State<XtreamSeriesDetailScreen> {\n  late Future<XtreamSeriesDetails> _future;\n  int? _selectedSeason;\n  final ParentalControlService _parental = ParentalControlService.instance;",
    'series detail parental field',
)
text = replace_once(
    text,
    "  void initState() {\n    super.initState();\n    _future = XtreamSeriesService.fetchDetails(\n      widget.connection,\n      widget.summary,\n    );\n  }",
    "  void initState() {\n    super.initState();\n    _parental.addListener(_onParentalChanged);\n    _future = XtreamSeriesService.fetchDetails(\n      widget.connection,\n      widget.summary,\n    );\n  }\n\n  @override\n  void dispose() {\n    _parental.removeListener(_onParentalChanged);\n    super.dispose();\n  }\n\n  void _onParentalChanged() {\n    if (mounted) setState(() {});\n  }\n\n  bool get _blocked => _parental.isLocked && _parental.isProtectedItem(\n        name: widget.summary.name,\n        group: widget.summary.category,\n      );\n\n  Future<bool> _ensureParentalAccess() async {\n    if (!_blocked) return true;\n    return requestParentalUnlock(context);\n  }",
    'series detail lifecycle',
)
text = replace_once(
    text,
    "      body: FutureBuilder<XtreamSeriesDetails>(",
    "      body: _blocked\n          ? _SeriesParentalBlockedView(\n              onUnlock: () => unawaited(requestParentalUnlock(context)),\n            )\n          : FutureBuilder<XtreamSeriesDetails>(",
    'series blocked body',
)
text = replace_once(
    text,
    "  Future<void> _play(\n    XtreamSeriesDetails details,\n    int season,\n    XtreamSeriesEpisode episode,\n  ) async {\n    final episodes =",
    "  Future<void> _play(\n    XtreamSeriesDetails details,\n    int season,\n    XtreamSeriesEpisode episode,\n  ) async {\n    if (!await _ensureParentalAccess() || !mounted) return;\n    final episodes =",
    'series play guard',
)
anchor = "class _SeriesCatalogData {"
blocked_widget = """class _SeriesParentalBlockedView extends StatelessWidget {
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

"""
text = replace_once(text, anchor, blocked_widget + anchor, 'series blocked widget')
path.write_text(text)
