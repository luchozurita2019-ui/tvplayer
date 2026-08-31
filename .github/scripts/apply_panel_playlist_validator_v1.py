from pathlib import Path

path = Path('panel/index.html')
text = path.read_text(encoding='utf-8')
marker = '<button data-route="assignments"><span class="icon">↔</span><span class="label">Asignaciones</span></button>'
button = '<button type="button" onclick="location.href=\'./validator.html\'"><span class="icon">✓</span><span class="label">Validador de listas</span></button>'
if button not in text:
    if marker not in text:
        raise SystemExit('playlist validator nav marker not found')
    text = text.replace(marker, marker + '\n        ' + button, 1)
path.write_text(text, encoding='utf-8')
