from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected 1 match, found {count}")
    p.write_text(text.replace(old, new, 1))


# 1) Treat timeout as network inactivity, not total download duration.
vod = "lib/services/xtream_vod_service.dart"
replace_once(
    vod,
    """    final response = await _client.get(uri, headers: _headers).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('Xtream $action respondió HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    return decoded is List ? decoded : const <dynamic>[];
""",
    """    final request = http.Request('GET', uri)..headers.addAll(_headers);
    final response = await _client.send(request).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('Xtream $action respondió HTTP ${response.statusCode}.');
    }

    // El timeout se reinicia cada vez que llega un fragmento del cuerpo.
    // Así un catálogo grande puede tardar más que [timeout] en total siempre
    // que el servidor continúe enviando datos. Sólo falla si queda inactivo.
    final body = await response.stream
        .transform(utf8.decoder)
        .timeout(timeout)
        .join();
    final decoded = jsonDecode(body);
    return decoded is List ? decoded : const <dynamic>[];
""",
)

# 2) Expose whether CachedArtworkImage really resolved a usable cached/network file.
artwork = "lib/widgets/cached_artwork_image.dart"
replace_once(
    artwork,
    """  final int? cacheWidth;
  final int? cacheHeight;

  const CachedArtworkImage({
""",
    """  final int? cacheWidth;
  final int? cacheHeight;
  final ValueChanged<bool>? onAvailabilityChanged;

  const CachedArtworkImage({
""",
)
replace_once(
    artwork,
    """    this.allowNetwork = true,
    this.cacheWidth,
    this.cacheHeight,
  });
""",
    """    this.allowNetwork = true,
    this.cacheWidth,
    this.cacheHeight,
    this.onAvailabilityChanged,
  });
""",
)
replace_once(
    artwork,
    """  void _reload() {
    _future = ArtworkCacheService.instance.resolve(
      widget.url,
      allowNetwork: widget.allowNetwork,
    );
  }
""",
    """  void _reload() {
    final future = ArtworkCacheService.instance.resolve(
      widget.url,
      allowNetwork: widget.allowNetwork,
    );
    _future = future;
    final callback = widget.onAvailabilityChanged;
    if (callback != null) {
      future.then((file) {
        if (mounted) callback(file != null);
      });
    }
  }
""",
)

# 3) Movies: use real artwork availability, keep trailer-only details, and improve timeout message.
movies = "lib/screens/xtream_movies_screen.dart"
replace_once(
    movies,
    """  Future<void> _openMovie(
    XtreamConnectionResult connection,
    XtreamVodSummary movie,
  ) async {
""",
    """  Future<void> _openMovie(
    XtreamConnectionResult connection,
    XtreamVodSummary movie, {
    required bool artworkAvailable,
  }) async {
""",
)
replace_once(
    movies,
    """      if (!mounted) return;
      if (!details.hasPresentationMedia) {
        await _playMovieDirect(connection, movie, details: details);
        return;
      }
""",
    """      if (!mounted) return;
      // No abrimos una ficha vacía por una URL de imagen rota. La ficha se
      // conserva sólo si la tarjeta cargó una carátula real o existe tráiler.
      if (!artworkAvailable && details.trailerChannel() == null) {
        await _playMovieDirect(connection, movie, details: details);
        return;
      }
""",
)
replace_once(
    movies,
    """                  return _MoviePosterCard(
                    movie: movie,
                    onTap: () =>
                        unawaited(_openMovie(data.connection, movie)),
                  );
""",
    """                  return _MoviePosterCard(
                    movie: movie,
                    onTap: (artworkAvailable) => unawaited(
                      _openMovie(
                        data.connection,
                        movie,
                        artworkAvailable: artworkAvailable,
                      ),
                    ),
                  );
""",
)
replace_once(
    movies,
    """          if (snapshot.hasError) {
            return _MovieError(
              message: snapshot.error.toString().replaceFirst('Exception: ', ''),
              onRetry: _retry,
            );
          }
""",
    """          if (snapshot.hasError) {
            final rawError = snapshot.error.toString();
            final message = rawError.contains('TimeoutException')
                ? 'El servidor Xtream dejó de enviar datos durante demasiado tiempo. Reintentá la carga de Películas.'
                : rawError.replaceFirst('Exception: ', '');
            return _MovieError(
              message: message,
              onRetry: _retry,
            );
          }
""",
)
old_card = """class _MoviePosterCard extends StatelessWidget {
  final XtreamVodSummary movie;
  final VoidCallback onTap;

  const _MoviePosterCard({required this.movie, required this.onTap});

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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedArtworkImage(
                    url: movie.cover,
                    fit: BoxFit.cover,
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 16),
                            const SizedBox(width: 3),
                            Text(movie.rating!, style: const TextStyle(fontWeight: FontWeight.w800)),
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
"""
new_card = """class _MoviePosterCard extends StatefulWidget {
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 16),
                            const SizedBox(width: 3),
                            Text(movie.rating!, style: const TextStyle(fontWeight: FontWeight.w800)),
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
"""
replace_once(movies, old_card, new_card)

checks = {
    vod: ["response.stream", ".timeout(timeout)", "El timeout se reinicia"],
    artwork: ["onAvailabilityChanged", "callback(file != null)"],
    movies: [
        "required bool artworkAvailable",
        "details.trailerChannel() == null",
        "ValueChanged<bool> onTap",
        "El servidor Xtream dejó de enviar datos",
    ],
}
for path, needles in checks.items():
    text = Path(path).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"{path}: missing validation marker {needle}")
