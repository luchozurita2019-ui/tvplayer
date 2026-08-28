from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'marker not found: {label}')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# 1) Reusable catalog index: parental filter + category buckets + normalized
#    search strings are prepared once per loaded catalog, not on every rebuild.
# ---------------------------------------------------------------------------
Path('lib/services/catalog_index.dart').write_text(r'''class CatalogIndex<T> {
  final List<T> all;
  final List<String> categories;
  final Map<String, List<T>> _byCategory;
  final List<_CatalogSearchEntry<T>> _searchEntries;

  const CatalogIndex._(
    this.all,
    this.categories,
    this._byCategory,
    this._searchEntries,
  );

  factory CatalogIndex.build({
    required Iterable<T> items,
    required String Function(T item) nameOf,
    required String? Function(T item) categoryOf,
    required bool Function(T item) include,
    Iterable<String> categoryOrder = const <String>[],
  }) {
    final visible = <T>[];
    final buckets = <String, List<T>>{};
    final searchEntries = <_CatalogSearchEntry<T>>[];
    final discovered = <String>[];
    final discoveredSet = <String>{};

    for (final item in items) {
      if (!include(item)) continue;
      visible.add(item);
      final category = categoryOf(item)?.trim();
      if (category != null && category.isNotEmpty) {
        buckets.putIfAbsent(category, () => <T>[]).add(item);
        if (discoveredSet.add(category)) discovered.add(category);
      }
      final searchText = _normalizeCatalogSearch(
        '${nameOf(item)} ${category ?? ''}',
      );
      searchEntries.add(_CatalogSearchEntry(item, searchText));
    }

    final orderedCategories = <String>[];
    final added = <String>{};
    for (final raw in categoryOrder) {
      final category = raw.trim();
      if (category.isEmpty || !buckets.containsKey(category)) continue;
      if (added.add(category)) orderedCategories.add(category);
    }
    for (final category in discovered) {
      if (added.add(category)) orderedCategories.add(category);
    }

    return CatalogIndex._(
      List<T>.unmodifiable(visible),
      List<String>.unmodifiable(orderedCategories),
      Map<String, List<T>>.unmodifiable(
        buckets.map(
          (key, value) => MapEntry(key, List<T>.unmodifiable(value)),
        ),
      ),
      List<_CatalogSearchEntry<T>>.unmodifiable(searchEntries),
    );
  }

  List<T> forCategory(String? category) {
    if (category == null) return all;
    return _byCategory[category] ?? const <T>[];
  }

  List<T> search(String rawQuery) {
    final query = _normalizeCatalogSearch(rawQuery);
    if (query.isEmpty) return all;
    final result = <T>[];
    for (final entry in _searchEntries) {
      if (entry.searchText.contains(query)) result.add(entry.item);
    }
    return result;
  }
}

class _CatalogSearchEntry<T> {
  final T item;
  final String searchText;
  const _CatalogSearchEntry(this.item, this.searchText);
}

String _normalizeCatalogSearch(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Automatic NORMAL / LOW-RAM profile using Android's official signal.
# ---------------------------------------------------------------------------
Path('lib/services/device_performance_service.dart').write_text(r'''import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

class DevicePerformanceService {
  DevicePerformanceService._();
  static final DevicePerformanceService instance = DevicePerformanceService._();

  static const MethodChannel _channel = MethodChannel('tvfull/device_identity');

  bool _initialized = false;
  bool _lowRam = false;
  int _memoryClassMb = 0;

  bool get lowRam => _lowRam;
  int get memoryClassMb => _memoryClassMb;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'getDeviceProfile',
        );
        _lowRam = raw?['lowRam'] == true;
        _memoryClassMb = _toInt(raw?['memoryClassMb']);
        if (_memoryClassMb > 0 && _memoryClassMb <= 128) _lowRam = true;
      } catch (_) {
        // Unknown devices keep the normal conservative profile.
      }
    }
    _applyFlutterImageBudget();
  }

  int? artworkDecodeWidth(int? requested) => _scaledArtworkSize(requested);
  int? artworkDecodeHeight(int? requested) => _scaledArtworkSize(requested);

  int? _scaledArtworkSize(int? requested) {
    if (requested == null || requested <= 0 || !_lowRam) return requested;
    final scaled = (requested * .72).round();
    return scaled < 96 ? 96 : scaled;
  }

  void _applyFlutterImageBudget() {
    final cache = PaintingBinding.instance.imageCache;
    if (_lowRam) {
      cache.maximumSize = 80;
      cache.maximumSizeBytes = 24 * 1024 * 1024;
    } else {
      cache.maximumSize = 180;
      cache.maximumSizeBytes = 48 * 1024 * 1024;
    }
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) Artwork widget: Grid/List builders already virtualize off-screen children.
#    Remove one ScrollPosition listener + localToGlobal calculations PER image.
# ---------------------------------------------------------------------------
Path('lib/widgets/cached_artwork_image.dart').write_text(r'''import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/artwork_cache_service.dart';
import '../services/device_performance_service.dart';

/// Artwork demand-driven by the virtualized GridView/ListView child lifecycle.
///
/// A card requests its image when Flutter actually builds that card. When the
/// builder disposes it, its download interest is released. This avoids hundreds
/// of per-card scroll listeners and RenderBox/global-coordinate calculations.
class CachedArtworkImage extends StatefulWidget {
  final String? url;
  final BoxFit fit;
  final Widget fallback;
  final bool allowNetwork;
  final int? cacheWidth;
  final int? cacheHeight;
  final ValueChanged<bool>? onAvailabilityChanged;

  /// Kept for source compatibility. Prefetch is now controlled by the parent
  /// GridView/ListView cache extent instead of every image measuring itself.
  final double prefetchExtent;

  const CachedArtworkImage({
    super.key,
    required this.url,
    required this.fit,
    required this.fallback,
    this.allowNetwork = true,
    this.cacheWidth,
    this.cacheHeight,
    this.onAvailabilityChanged,
    this.prefetchExtent = 96,
  });

  @override
  State<CachedArtworkImage> createState() => _CachedArtworkImageState();
}

class _CachedArtworkImageState extends State<CachedArtworkImage> {
  File? _file;
  bool _loading = false;
  bool _interestHeld = false;
  int _requestGeneration = 0;
  String? _retainedUrl;

  @override
  void initState() {
    super.initState();
    _scheduleResolve();
  }

  @override
  void didUpdateWidget(covariant CachedArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.allowNetwork != widget.allowNetwork) {
      _requestGeneration++;
      _loading = false;
      _file = null;
      _releaseInterest();
      widget.onAvailabilityChanged?.call(false);
      _scheduleResolve();
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _releaseInterest();
    super.dispose();
  }

  void _scheduleResolve() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_ensureResolved());
    });
  }

  Future<void> _ensureResolved() async {
    if (_file != null || _loading) return;
    final rawUrl = widget.url?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return;

    final service = ArtworkCacheService.instance;
    service.retain(rawUrl);
    _interestHeld = true;
    _retainedUrl = rawUrl;
    _loading = true;
    final generation = ++_requestGeneration;

    final file = await service.resolve(
      rawUrl,
      allowNetwork: widget.allowNetwork,
      demandDriven: true,
    );

    if (!mounted || generation != _requestGeneration) return;
    _loading = false;
    _releaseInterest();
    if (file == null) {
      widget.onAvailabilityChanged?.call(false);
      return;
    }
    setState(() => _file = file);
    widget.onAvailabilityChanged?.call(true);
  }

  void _releaseInterest() {
    if (!_interestHeld) return;
    ArtworkCacheService.instance.release(_retainedUrl);
    _interestHeld = false;
    _retainedUrl = null;
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return widget.fallback;
    final profile = DevicePerformanceService.instance;
    return Image.file(
      file,
      fit: widget.fit,
      cacheWidth: profile.artworkDecodeWidth(widget.cacheWidth),
      cacheHeight: profile.artworkDecodeHeight(widget.cacheHeight),
      filterQuality: profile.lowRam ? FilterQuality.low : FilterQuality.medium,
      errorBuilder: (_, __, ___) {
        widget.onAvailabilityChanged?.call(false);
        return widget.fallback;
      },
    );
  }
}
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# 4) Artwork network/disk budgets follow LOW-RAM profile.
# ---------------------------------------------------------------------------
artwork = Path('lib/services/artwork_cache_service.dart')
text = artwork.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import 'package:path_provider/path_provider.dart';",
    "import 'package:path_provider/path_provider.dart';\n\nimport 'device_performance_service.dart';",
    'artwork profile import',
)
text = replace_once(
    text,
    "  static const int _maxConcurrent = 3;\n  static const int _maxArtworkBytes = 3 * 1024 * 1024;\n  static const int _maxCacheBytes = 64 * 1024 * 1024;\n  static const int _trimToBytes = 48 * 1024 * 1024;",
    "  static const int _maxArtworkBytes = 3 * 1024 * 1024;\n\n  int get _maxConcurrent =>\n      DevicePerformanceService.instance.lowRam ? 2 : 3;\n  int get _maxCacheBytes => DevicePerformanceService.instance.lowRam\n      ? 40 * 1024 * 1024\n      : 64 * 1024 * 1024;\n  int get _trimToBytes => DevicePerformanceService.instance.lowRam\n      ? 30 * 1024 * 1024\n      : 48 * 1024 * 1024;",
    'dynamic artwork budgets',
)
text = replace_once(
    text,
    "  Future<void> switchProvider(String providerId) async {\n    _pausedForPlayback = false;",
    "  Future<void> switchProvider(String providerId) async {\n    await DevicePerformanceService.instance.init();\n    _pausedForPlayback = false;",
    'artwork init profile',
)
# Stop touching file metadata on every visible poster; prune by creation/last
# download order is good enough and avoids many tiny filesystem writes.
text = text.replace(
    "      unawaited(known.setLastModified(DateTime.now()).catchError((_) {}));\n      return known;",
    "      return known;",
)
text = text.replace(
    "      unawaited(file.setLastModified(DateTime.now()).catchError((_) {}));\n      return file;",
    "      return file;",
)
artwork.write_text(text, encoding='utf-8')


# ---------------------------------------------------------------------------
# 5) File catalog source: expose NDJSON file without first decoding every line
#    into List<dynamic>. SectionCatalogService converts each line directly to a
#    Channel, so only one materialized catalog exists in RAM.
# ---------------------------------------------------------------------------
store = Path('lib/services/catalog_file_store.dart')
text = store.read_text(encoding='utf-8')
text = replace_once(
    text,
    "class CatalogFileSnapshot {\n  final Map<String, dynamic> payload;\n  final DateTime updatedAt;\n\n  const CatalogFileSnapshot({required this.payload, required this.updatedAt});\n}\n",
    "class CatalogFileSnapshot {\n  final Map<String, dynamic> payload;\n  final DateTime updatedAt;\n\n  const CatalogFileSnapshot({required this.payload, required this.updatedAt});\n}\n\nclass CatalogFileSource {\n  final File itemsFile;\n  final List<String> categories;\n  final DateTime updatedAt;\n\n  const CatalogFileSource({\n    required this.itemsFile,\n    required this.categories,\n    required this.updatedAt,\n  });\n}\n",
    'catalog file source type',
)
text = replace_once(
    text,
    "  static const int _version = 1;\n  Directory? _root;\n",
    "  static const int _version = 1;\n  Directory? _root;\n\n  Future<CatalogFileSource?> loadSource(\n    String serviceId,\n    String kind,\n  ) async {\n    final section = await _sectionDirectory(serviceId, kind);\n    if (!await section.exists()) return null;\n    final generation = await _resolveCurrentGeneration(section);\n    if (generation == null) return null;\n    try {\n      final metaRaw = jsonDecode(\n        await File('${generation.path}/meta.json').readAsString(),\n      );\n      if (metaRaw is! Map || metaRaw['version'] != _version) return null;\n      final updatedMillis =\n          int.tryParse(metaRaw['updatedAt']?.toString() ?? '');\n      if (updatedMillis == null || updatedMillis <= 0) return null;\n      final categoriesRaw = jsonDecode(\n        await File('${generation.path}/categories.json').readAsString(),\n      );\n      final itemsFile = File('${generation.path}/items.ndjson');\n      if (!await itemsFile.exists()) return null;\n      return CatalogFileSource(\n        itemsFile: itemsFile,\n        categories: categoriesRaw is List\n            ? categoriesRaw.map((e) => e.toString()).toList(growable: false)\n            : const <String>[],\n        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMillis),\n      );\n    } catch (_) {\n      return null;\n    }\n  }\n",
    'streaming catalog source method',
)
store.write_text(text, encoding='utf-8')

section = Path('lib/services/section_catalog_service.dart')
text = section.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import 'package:flutter/foundation.dart';",
    "import 'dart:convert';\n\nimport 'package:flutter/foundation.dart';",
    'section json import',
)
text = replace_once(
    text,
    "    final fileSnapshot = await _catalogFiles.loadSnapshot(playlist.id, key);\n    if (fileSnapshot != null) {\n      return _decodeSnapshot(fileSnapshot.payload);\n    }",
    "    final fileSource = await _catalogFiles.loadSource(playlist.id, key);\n    if (fileSource != null) {\n      final decoded = await _decodeFileSource(fileSource);\n      if (decoded != null) return decoded;\n    }",
    'direct NDJSON read',
)
text = replace_once(
    text,
    "  SectionCatalogSnapshot? _decodeSnapshot(dynamic raw) {",
    r'''  Future<SectionCatalogSnapshot?> _decodeFileSource(
    CatalogFileSource source,
  ) async {
    final channels = <Channel>[];
    try {
      final lines = source.itemsFile
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        final value = line.trim();
        if (value.isEmpty) continue;
        try {
          final decoded = jsonDecode(value);
          if (decoded is! Map) continue;
          channels.add(Channel.fromJson(Map<String, dynamic>.from(decoded)));
        } catch (_) {}
      }
    } catch (_) {
      return null;
    }
    if (channels.isEmpty) return null;
    return SectionCatalogSnapshot(
      channels: List<Channel>.unmodifiable(channels),
      categories: List<String>.unmodifiable(
        source.categories.isEmpty ? _categories(channels) : source.categories,
      ),
      fromCache: true,
    );
  }

  SectionCatalogSnapshot? _decodeSnapshot(dynamic raw) {''',
    'direct channel decoder',
)
section.write_text(text, encoding='utf-8')


# ---------------------------------------------------------------------------
# 6) Android profile signal + initialize once before catalog browsing.
# ---------------------------------------------------------------------------
main_activity = Path('android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt')
text = main_activity.read_text(encoding='utf-8')
text = replace_once(
    text,
    'import android.net.Uri',
    'import android.app.ActivityManager\nimport android.content.Context\nimport android.net.Uri',
    'android performance imports',
)
text = replace_once(
    text,
    '''        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)\n            .setMethodCallHandler { call, result ->\n                if (call.method == "getAndroidId") {\n                    result.success(\n                        Settings.Secure.getString(\n                            contentResolver,\n                            Settings.Secure.ANDROID_ID,\n                        )\n                    )\n                } else {\n                    result.notImplemented()\n                }\n            }'''.replace('\\n', '\n'),
    '''        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)\n            .setMethodCallHandler { call, result ->\n                when (call.method) {\n                    "getAndroidId" -> result.success(\n                        Settings.Secure.getString(\n                            contentResolver,\n                            Settings.Secure.ANDROID_ID,\n                        )\n                    )\n                    "getDeviceProfile" -> {\n                        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager\n                        result.success(\n                            mapOf(\n                                "lowRam" to manager.isLowRamDevice,\n                                "memoryClassMb" to manager.memoryClass,\n                                "largeMemoryClassMb" to manager.largeMemoryClass,\n                            )\n                        )\n                    }\n                    else -> result.notImplemented()\n                }\n            }'''.replace('\\n', '\n'),
    'android device profile method',
)
main_activity.write_text(text, encoding='utf-8')

main = Path('lib/main.dart')
text = main.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import 'services/parental_control_service.dart';",
    "import 'services/device_performance_service.dart';\nimport 'services/parental_control_service.dart';",
    'main performance import',
)
text = replace_once(
    text,
    "  await ParentalControlService.instance.init();",
    "  await Future.wait([\n    ParentalControlService.instance.init(),\n    DevicePerformanceService.instance.init(),\n  ]);",
    'main profile init',
)
main.write_text(text, encoding='utf-8')


# ---------------------------------------------------------------------------
# 7) Movies / Series / LIVE: cached catalog index + 120ms search debounce.
# ---------------------------------------------------------------------------
def patch_screen(path: str, kind: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    text = replace_once(
        text,
        "import '../services/artwork_cache_service.dart';",
        "import '../services/artwork_cache_service.dart';\nimport '../services/catalog_index.dart';\nimport '../services/device_performance_service.dart';",
        f'{kind} performance imports',
    )
    if kind == 'movie':
        item_type, data_type = '_MovieItem', '_MovieData'
        name_expr, category_expr = 'item.name', 'item.category'
        include_expr = "_parental.canShowItem(name: item.name, group: item.category)"
        method_name = '_catalogIndexFor'
        catalog_anchor = '''    final categories = _parental.visibleGroups(data.categories);\n    final allowed = data.items\n        .where(\n          (item) => _parental.canShowItem(\n            name: item.name,\n            group: item.category,\n          ),\n        )\n        .toList(growable: false);\n    final normalizedQuery = _query.trim().toLowerCase();\n    final List<_MovieItem> visible;\n    if (_searchOpen) {\n      visible = normalizedQuery.isEmpty\n          ? allowed\n          : allowed.where((item) {\n              final name = item.name.toLowerCase();\n              final category = (item.category ?? '').toLowerCase();\n              return name.contains(normalizedQuery) ||\n                  category.contains(normalizedQuery);\n            }).toList(growable: false);\n    } else {\n      visible = _category == null\n          ? allowed\n          : allowed\n              .where((item) => item.category == _category)\n              .toList(growable: false);\n    }'''.replace('\\n', '\n')
    elif kind == 'series':
        item_type, data_type = '_SeriesItem', '_SeriesData'
        name_expr, category_expr = 'item.name', 'item.category'
        include_expr = "_parental.canShowItem(name: item.name, group: item.category)"
        method_name = '_catalogIndexFor'
        catalog_anchor = '''    final categories = _parental.visibleGroups(data.categories);\n    final allowed = data.items\n        .where(\n          (item) => _parental.canShowItem(\n            name: item.name,\n            group: item.category,\n          ),\n        )\n        .toList(growable: false);\n    final normalizedQuery = _query.trim().toLowerCase();\n    final List<_SeriesItem> visible;\n    if (_searchOpen) {\n      visible = normalizedQuery.isEmpty\n          ? allowed\n          : allowed.where((item) {\n              final name = item.name.toLowerCase();\n              final category = (item.category ?? '').toLowerCase();\n              return name.contains(normalizedQuery) ||\n                  category.contains(normalizedQuery);\n            }).toList(growable: false);\n    } else {\n      visible = _category == null\n          ? allowed\n          : allowed\n              .where((item) => item.category == _category)\n              .toList(growable: false);\n    }'''.replace('\\n', '\n')
    else:
        item_type, data_type = 'Channel', '_LiveData'
        name_expr, category_expr = 'item.name', 'item.group'
        include_expr = '_parental.canShowChannel(item)'
        method_name = '_catalogIndexFor'
        catalog_anchor = '''    final categories = _parental.visibleGroups(data.categories);\n    final allowed =\n        data.channels.where(_parental.canShowChannel).toList(growable: false);\n    final normalizedQuery = _query.trim().toLowerCase();\n    final List<Channel> visible;\n    if (_searchOpen) {\n      visible = normalizedQuery.isEmpty\n          ? allowed\n          : allowed.where((item) {\n              final name = item.name.toLowerCase();\n              final group = (item.group ?? '').toLowerCase();\n              return name.contains(normalizedQuery) ||\n                  group.contains(normalizedQuery);\n            }).toList(growable: false);\n    } else {\n      visible = _category == null\n          ? allowed\n          : allowed\n              .where((item) => item.group == _category)\n              .toList(growable: false);\n    }'''.replace('\\n', '\n')

    text = replace_once(
        text,
        "  bool _searchOpen = false;",
        f"  bool _searchOpen = false;\n  Timer? _searchDebounce;\n  CatalogIndex<{item_type}>? _catalogIndex;\n  {data_type}? _indexedData;",
        f'{kind} index state',
    )
    text = replace_once(
        text,
        "    _parental.removeListener(_onParentalChanged);",
        "    _parental.removeListener(_onParentalChanged);\n    _searchDebounce?.cancel();",
        f'{kind} dispose debounce',
    )
    text = replace_once(
        text,
        "    setState(() {});\n  }\n\n  void _openSearch()",
        "    _catalogIndex = null;\n    _indexedData = null;\n    setState(() {});\n  }\n\n  void _openSearch()",
        f'{kind} invalidate index',
    )
    text = replace_once(
        text,
        "    _searchFocus.unfocus();\n    _searchController.clear();",
        "    _searchDebounce?.cancel();\n    _searchFocus.unfocus();\n    _searchController.clear();",
        f'{kind} close debounce',
    )

    items_expr = 'data.channels' if kind == 'live' else 'data.items'
    helper = f'''\n  void _scheduleSearch(String value) {{\n    _searchDebounce?.cancel();\n    _searchDebounce = Timer(const Duration(milliseconds: 120), () {{\n      if (mounted && value != _query) setState(() => _query = value);\n    }});\n  }}\n\n  CatalogIndex<{item_type}> {method_name}({data_type} data) {{\n    final cached = _catalogIndex;\n    if (cached != null && identical(_indexedData, data)) return cached;\n    final built = CatalogIndex<{item_type}>.build(\n      items: {items_expr},\n      categoryOrder: data.categories,\n      nameOf: (item) => {name_expr},\n      categoryOf: (item) => {category_expr},\n      include: (item) => {include_expr},\n    );\n    _indexedData = data;\n    _catalogIndex = built;\n    return built;\n  }}\n'''
    text = replace_once(
        text,
        "\n  Future<" + data_type + "> _loadInitial() async {",
        helper + "\n  Future<" + data_type + "> _loadInitial() async {",
        f'{kind} index helpers',
    )
    text = replace_once(
        text,
        "onChanged: (value) => setState(() => _query = value),",
        "onChanged: _scheduleSearch,",
        f'{kind} search debounce hook',
    )
    replacement = '''    final index = _catalogIndexFor(data);\n    final categories = index.categories;\n    final visible = _searchOpen\n        ? index.search(_query)\n        : index.forCategory(_category);'''.replace('\\n', '\n')
    text = replace_once(text, catalog_anchor, replacement, f'{kind} indexed catalog')

    if kind in ('movie', 'series'):
        text = replace_once(
            text,
            "                            scrollCacheExtent:\n                                const ScrollCacheExtent.pixels(120),",
            "                            scrollCacheExtent:\n                                DevicePerformanceService.instance.lowRam\n                                    ? const ScrollCacheExtent.pixels(48)\n                                    : const ScrollCacheExtent.pixels(120),",
            f'{kind} low ram grid cache',
        )
        text = replace_once(
            text,
            "  Widget build(BuildContext context) {\n    return AnimatedScale(\n      scale: _focused ? 1.035 : 1,\n      duration: const Duration(milliseconds: 120),",
            "  Widget build(BuildContext context) {\n    final lowRam = DevicePerformanceService.instance.lowRam;\n    return AnimatedScale(\n      scale: _focused ? (lowRam ? 1.018 : 1.035) : 1,\n      duration: Duration(milliseconds: lowRam ? 70 : 120),",
            f'{kind} low ram focus animation',
        )
    else:
        text = replace_once(
            text,
            "                        scrollCacheExtent: const ScrollCacheExtent.pixels(80),",
            "                        scrollCacheExtent:\n                            DevicePerformanceService.instance.lowRam\n                                ? const ScrollCacheExtent.pixels(36)\n                                : const ScrollCacheExtent.pixels(80),",
            'live low ram list cache',
        )

    file.write_text(text, encoding='utf-8')


patch_screen('lib/screens/xtream_movies_screen.dart', 'movie')
patch_screen('lib/screens/xtream_series_screen.dart', 'series')
patch_screen('lib/screens/xtream_live_screen.dart', 'live')


# ---------------------------------------------------------------------------
# 8) Version +13, updater knows its own code, and final builds publish a stable
#    public GitHub Release asset URL without changing signing or package id.
# ---------------------------------------------------------------------------
pubspec = Path('pubspec.yaml')
text = pubspec.read_text(encoding='utf-8')
text = replace_once(text, 'version: 1.2.0+12', 'version: 1.2.1+13', 'v13 pubspec')
pubspec.write_text(text, encoding='utf-8')

updates = Path('lib/services/app_update_service.dart')
text = updates.read_text(encoding='utf-8')
text = replace_once(
    text,
    "  static const int currentVersionCode = 12;\n  static const String currentVersionName = '1.2.0';",
    "  static const int currentVersionCode = 13;\n  static const String currentVersionName = '1.2.1';",
    'v13 updater self version',
)
updates.write_text(text, encoding='utf-8')

workflow = Path('.github/workflows/build-tv-full-pro-clean.yml')
text = workflow.read_text(encoding='utf-8')
stable_release_step = '''      - name: Publish stable latest APK URL\n        env:\n          GH_TOKEN: ${{ github.token }}\n        shell: bash\n        run: |\n          set -euo pipefail\n          TAG=tv-full-pro-latest\n          if gh release view "$TAG" >/dev/null 2>&1; then\n            gh release upload "$TAG" artifact/TV-FULL-PRO.apk --clobber\n          else\n            gh release create "$TAG" artifact/TV-FULL-PRO.apk \\\n              --title "TV FULL PRO latest" \\\n              --notes "Canal estable para actualización manual de TV FULL PRO."\n          fi\n\n'''
text = replace_once(
    text,
    '      - name: Remove signing material from runner workspace\n',
    stable_release_step + '      - name: Remove signing material from runner workspace\n',
    'stable latest release asset',
)
workflow.write_text(text, encoding='utf-8')

print('TV FULL PRO 1.2.1+13 optimization patch prepared successfully')
