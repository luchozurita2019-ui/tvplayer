from pathlib import Path
import re

SERVICE = Path('lib/services/player_route_guard.dart')
SERVICE.parent.mkdir(parents=True, exist_ok=True)
SERVICE.write_text("""import 'package:flutter/material.dart';

/// Serializa la navegación hacia PlayerScreen para que un doble clic o dos
/// selecciones casi simultáneas nunca puedan apilar dos reproductores.
class PlayerRouteGuard {
  PlayerRouteGuard._();

  static bool _routeOpen = false;

  static bool get routeOpen => _routeOpen;

  static Future<T?> push<T>(BuildContext context, Route<T> route) async {
    if (_routeOpen) return null;

    // Se activa antes del primer await: dos eventos del mismo frame/event loop
    // no pueden atravesar la guarda al mismo tiempo.
    _routeOpen = true;
    try {
      return await Navigator.of(context).push<T>(route);
    } finally {
      _routeOpen = false;
    }
  }
}
""", encoding='utf-8')

pattern = re.compile(
    r"await Navigator\.of\(context\)\.push\(\n"
    r"(?P<route_indent>[ \t]*)MaterialPageRoute\(\n"
    r"(?P<builder_indent>[ \t]*)builder: \(_\) => PlayerScreen\("
)

patched = []
replacements = 0
for path in sorted(Path('lib/screens').glob('*.dart')):
    text = path.read_text(encoding='utf-8')
    if 'PlayerScreen(' not in text or not pattern.search(text):
        continue

    if "../services/player_route_guard.dart" not in text:
        anchor = "import 'player_screen.dart';"
        if anchor not in text:
            raise SystemExit(f'{path}: PlayerScreen directo sin import player_screen.dart reconocible')
        text = text.replace(
            anchor,
            "import '../services/player_route_guard.dart';\n" + anchor,
            1,
        )

    def repl(match):
        nonlocal_marker[0] += 1
        route_indent = match.group('route_indent')
        builder_indent = match.group('builder_indent')
        return (
            'await PlayerRouteGuard.push(\n'
            f'{route_indent}context,\n'
            f'{route_indent}MaterialPageRoute(\n'
            f'{builder_indent}builder: (_) => PlayerScreen('
        )

    nonlocal_marker = [0]
    new_text = pattern.sub(repl, text)
    count = nonlocal_marker[0]
    if not count:
        raise SystemExit(f'{path}: se detectó ruta PlayerScreen pero no se pudo parchear')

    path.write_text(new_text, encoding='utf-8')
    patched.append(str(path))
    replacements += count

if replacements < 3:
    raise SystemExit(f'Sólo se protegieron {replacements} aperturas PlayerScreen; se esperaban al menos 3')

print(f'PlayerScreen routes protegidas: {replacements}')
for item in patched:
    print(f'  - {item}')
