from pathlib import Path

path = Path('lib/widgets/tv_live_premium_catalog.dart')
text = path.read_text(encoding='utf-8')
old = "Programación no disponible"
new = "Guía no informada"
count = text.count(old)
if count != 2:
    raise SystemExit(f'Expected 2 occurrences of {old!r}, found {count}')
text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
print('Updated EPG fallback copy: Guía no informada')
