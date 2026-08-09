from pathlib import Path

path = Path('lib/screens/player_screen.dart')
text = path.read_text(encoding='utf-8')
old = """      if (!completed ||
          !mounted ||
          _opening ||
          _reconnecting ||
          _isBuffering ||
          _errorMessage != null) {
"""
new = """      if (!completed ||
          !mounted ||
          _opening ||
          _reconnecting ||
          _errorMessage != null) {
"""
if old not in text:
    raise SystemExit('completed guard not found')
text = text.replace(old, new, 1)
text = text.replace(
    """        // No dejamos que mpv cambie el estado global a Pause cuando el cache
        // se vacía. El frame puede quedar quieto mientras llegan paquetes,
        // pero el motor sigue en reproducción y FFmpeg puede reconectar abajo.
        await platform.setProperty('cache-pause', 'yes');
""",
    """        // Dejamos activo el buffering nativo de mpv. Si la red se queda sin
        // datos, pausa internamente, rellena el cache y continúa sin destruir
        // la sesión HTTP/HLS; esto es mucho más tolerante a conexiones débiles.
        await platform.setProperty('cache-pause', 'yes');
""",
    1,
)
path.write_text(text, encoding='utf-8')
print('V3.8 completed/cache comments fixed')
