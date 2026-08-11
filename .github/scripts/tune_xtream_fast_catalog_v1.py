from pathlib import Path

path = Path('lib/services/xtream_fast_catalog_service.dart')
text = path.read_text()

def repl(old, new, count=1):
    global text
    found = text.count(old)
    if found != count:
        raise SystemExit(f'expected {count} matches, found {found}: {old[:80]!r}')
    text = text.replace(old, new, count)

repl(
    "static const Duration _categoryTimeout = Duration(seconds: 12);",
    "static const Duration _categoryTimeout = Duration(seconds: 6);",
)

# A timeout/socket stall should surface immediately instead of repeating the same
# large network request through the legacy fallback.
repl(
    """    } catch (error) {
      // Compatibilidad: si un clon Xtream devuelve una estructura que nuestro
      // preparador rápido no entiende, conservamos el cargador probado anterior.
      try {
        final movies = await XtreamVodService.fetchCatalog(connection);
""",
    """    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (error) {
      // Compatibilidad: si un clon Xtream devuelve una estructura que nuestro
      // preparador rápido no entiende, conservamos el cargador probado anterior.
      try {
        final movies = await XtreamVodService.fetchCatalog(connection);
""",
)
repl(
    """    } catch (error) {
      try {
        final series = await XtreamSeriesService.fetchCatalog(connection);
""",
    """    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (error) {
      try {
        final series = await XtreamSeriesService.fetchCatalog(connection);
""",
)

# Normal network path already owns the plain maps produced by the isolate. Reuse
# those maps for disk cache so we do not remap 10k/30k objects on the UI isolate.
repl(
    """    rememberConnection(connection);
    unawaited(_writeMovieCache(playlistUrl, snapshot));
    return snapshot;
""",
    """    rememberConnection(connection);
    unawaited(_writePreparedCache(
      playlistUrl,
      'movies',
      connection,
      prepared,
      snapshot.savedAt,
    ));
    return snapshot;
""",
)
repl(
    """    rememberConnection(connection);
    unawaited(_writeSeriesCache(playlistUrl, snapshot));
    return snapshot;
""",
    """    rememberConnection(connection);
    unawaited(_writePreparedCache(
      playlistUrl,
      'series',
      connection,
      prepared,
      snapshot.savedAt,
    ));
    return snapshot;
""",
)

anchor = """  Future<void> _writeMovieCache(
    String playlistUrl,
    XtreamMovieCatalogSnapshot snapshot,
  ) async {
"""
insert = """  Future<void> _writePreparedCache(
    String playlistUrl,
    String kind,
    XtreamConnectionResult connection,
    Map<String, dynamic> prepared,
    DateTime savedAt,
  ) async {
    // Yield first so returning the fresh catalog to Flutter always wins over
    // persistence. jsonEncode itself runs in compute() inside _writeCache.
    await Future<void>.delayed(Duration.zero);
    final payload = <String, dynamic>{
      'version': _cacheVersion,
      'kind': kind,
      'savedAt': savedAt.millisecondsSinceEpoch,
      'connection': _connectionToMap(connection),
      'categories': prepared['categories'] ?? const <String>[],
      'items': prepared['items'] ?? const <dynamic>[],
    };
    await _writeCache(playlistUrl, kind, payload);
  }

""" + anchor
repl(anchor, insert)

path.write_text(text)

checks = [
    'Duration(seconds: 6)',
    'on SocketException',
    '_writePreparedCache(',
    "'items': prepared['items']",
]
final = path.read_text()
for needle in checks:
    if needle not in final:
        raise SystemExit(f'missing marker {needle}')
