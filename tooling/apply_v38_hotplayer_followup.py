from pathlib import Path

path = Path('lib/screens/player_screen.dart')
text = path.read_text(encoding='utf-8')
old = """      if (!mounted ||
          session != _sessionId ||
          _opening ||
          _reconnecting ||
          _errorMessage != null) {
        return;
      }

      // Si hubo progreso desde el error, la recuperación nativa funcionó.
"""
new = """      if (!mounted ||
          session != _sessionId ||
          _opening ||
          _reconnecting ||
          _isBuffering ||
          _errorMessage != null) {
        return;
      }

      // Si hubo progreso desde el error, la recuperación nativa funcionó.
"""
if old not in text:
    raise SystemExit('transient live failure callback block not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('V3.8 buffering guard applied')
