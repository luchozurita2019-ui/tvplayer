from pathlib import Path

path = Path('lib/screens/xtream_movies_screen.dart')
text = path.read_text(encoding='utf-8')

field_anchor = "  int _lastProgressBytes = 0;\n"
if "bool _openingMovieDetails = false;" not in text:
    if field_anchor not in text:
        raise SystemExit('No se encontró el ancla para _openingMovieDetails')
    text = text.replace(
        field_anchor,
        field_anchor + "  bool _openingMovieDetails = false;\n",
        1,
    )

old = '''  Future<void> _openMovie(\n    XtreamConnectionResult connection,\n    XtreamVodSummary movie, {\n    required bool artworkAvailable,\n  }) async {\n    if (_parental.isLocked &&\n        _parental.isProtectedItem(name: movie.name, group: movie.category)) {\n      final unlocked = await requestParentalUnlock(context);\n      if (!unlocked || !mounted) return;\n    }\n\n    try {\n      final details = await XtreamVodService.fetchDetails(\n        connection,\n        movie,\n        timeout: const Duration(seconds: 12),\n      );\n      if (!mounted) return;\n      // No abrimos una ficha vacía por una URL de imagen rota. La ficha se\n      // conserva sólo si la tarjeta cargó una carátula real o existe tráiler.\n      if (!artworkAvailable && details.trailerChannel() == null) {\n        await _playMovieDirect(connection, movie, details: details);\n        return;\n      }\n      await Navigator.of(context).push(\n        MaterialPageRoute(\n          builder: (_) => XtreamMovieDetailScreen(\n            connection: connection,\n            movie: movie,\n            initialDetails: details,\n          ),\n        ),\n      );\n    } catch (_) {\n      if (!mounted) return;\n      await _playMovieDirect(connection, movie);\n    }\n  }\n'''

new = '''  Future<void> _openMovie(\n    XtreamConnectionResult connection,\n    XtreamVodSummary movie, {\n    required bool artworkAvailable,\n  }) async {\n    // fetchDetails ocurre antes de abrir la ficha. Sin esta guarda, dos clics\n    // rápidos lanzaban dos solicitudes y luego apilaban dos fichas de película.\n    if (_openingMovieDetails) return;\n    _openingMovieDetails = true;\n\n    try {\n      if (_parental.isLocked &&\n          _parental.isProtectedItem(name: movie.name, group: movie.category)) {\n        final unlocked = await requestParentalUnlock(context);\n        if (!unlocked || !mounted) return;\n      }\n\n      try {\n        final details = await XtreamVodService.fetchDetails(\n          connection,\n          movie,\n          timeout: const Duration(seconds: 12),\n        );\n        if (!mounted) return;\n        // No abrimos una ficha vacía por una URL de imagen rota. La ficha se\n        // conserva sólo si la tarjeta cargó una carátula real o existe tráiler.\n        if (!artworkAvailable && details.trailerChannel() == null) {\n          await _playMovieDirect(connection, movie, details: details);\n          return;\n        }\n        await Navigator.of(context).push(\n          MaterialPageRoute(\n            builder: (_) => XtreamMovieDetailScreen(\n              connection: connection,\n              movie: movie,\n              initialDetails: details,\n            ),\n          ),\n        );\n      } catch (_) {\n        if (!mounted) return;\n        await _playMovieDirect(connection, movie);\n      }\n    } finally {\n      _openingMovieDetails = false;\n    }\n  }\n'''

if old not in text:
    raise SystemExit('No se encontró _openMovie esperado; no se aplicó ningún cambio')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
print('Movie detail guard aplicado correctamente.')
