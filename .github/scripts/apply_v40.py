from pathlib import Path

# Follow-up quirúrgico sobre la v40 ya aplicada: borrar el caché persistente de
# carátulas creado por builds anteriores y corregir documentación interna vieja.

artwork = Path("lib/services/artwork_cache_service.dart")
text = artwork.read_text()
anchor = """    final future = () async {\n      final base = await getTemporaryDirectory();\n"""
replacement = """    final future = () async {\n      // Migración v40: las versiones anteriores guardaban posters de forma\n      // persistente en Application Support. Ya no se reutilizan, así que los\n      // eliminamos una sola vez al iniciar el caché temporal para recuperar\n      // almacenamiento en equipos actualizados.\n      try {\n        final support = await getApplicationSupportDirectory();\n        final legacy = Directory('${support.path}/tv_full_artwork_cache');\n        if (await legacy.exists()) await legacy.delete(recursive: true);\n      } catch (_) {}\n\n      final base = await getTemporaryDirectory();\n"""
if anchor not in text:
    raise SystemExit("No se encontró _ensureRootDirectory de artwork v40")
text = text.replace(anchor, replacement, 1)
artwork.write_text(text)

fast = Path("lib/services/xtream_fast_catalog_service.dart")
text = fast.read_text()
old = """/// Principios:\n/// - la autenticación Xtream se conserva en memoria durante la sesión;\n/// - Películas mantiene el flujo probado actual;\n/// - Series puede comenzar directamente desde la URL get.php ya guardada, sin\n///   esperar una autenticación extra sólo para mostrar el catálogo;\n/// - categorías y Series se descargan en paralelo;\n/// - el cuerpo se recibe como stream con timeout por inactividad;\n/// - jsonDecode, normalización y ordenamiento se ejecutan en un isolate;\n/// - el catálogo normalizado se guarda en disco para apertura inmediata;\n/// - las imágenes NO forman parte de esta carga y siguen su cola independiente.\n"""
new = """/// Principios v40:\n/// - para catálogo se intenta primero la conexión directa derivada de get.php;\n/// - categorías se resuelven antes del payload pesado para no competir por red;\n/// - get_vod_streams/get_series se escriben como stream a un archivo temporal;\n/// - lectura JSON y normalización pesada se ejecutan fuera del isolate de UI;\n/// - no se ordenan miles de elementos antes de poder mostrar el catálogo;\n/// - el catálogo local compacto es sólo fallback/offline y no contiene el bloque\n///   de conexión; las imágenes usan un caché temporal independiente.\n"""
if old not in text:
    raise SystemExit("No se encontró comentario de arquitectura antiguo")
text = text.replace(old, new, 1)
fast.write_text(text)
