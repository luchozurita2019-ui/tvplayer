from pathlib import Path

path = Path('.github/scripts/apply_android_tv_v13.py')
text = path.read_text()
old = "    if '_startRemotePolling()' not in text:\n"
new = "    if 'void _startRemotePolling() {' not in text:\n"
if old not in text:
    raise SystemExit('No se encontro el marcador defectuoso de polling V13')
path.write_text(text.replace(old, new, 1))
print('V13 apply-script fix: el cuerpo de polling se inserta correctamente.')
