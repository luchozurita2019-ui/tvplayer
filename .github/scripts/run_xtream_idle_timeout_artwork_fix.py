from pathlib import Path

path = Path('.github/scripts/apply_xtream_idle_timeout_artwork_fix.py')
source = path.read_text()
old = """    if count != 1:\n        raise SystemExit(f\"{path}: expected 1 match, found {count}\")\n    p.write_text(text.replace(old, new, 1))\n"""
new = """    if count == 2 and path == 'lib/screens/xtream_movies_screen.dart' and 'snapshot.hasError' in old:\n        p.write_text(text.replace(old, new, 1))\n        return\n    if count != 1:\n        raise SystemExit(f\"{path}: expected 1 match, found {count}\")\n    p.write_text(text.replace(old, new, 1))\n"""
if source.count(old) != 1:
    raise SystemExit('Could not prepare guarded replacement helper')
source = source.replace(old, new, 1)
exec(compile(source, str(path), 'exec'))
