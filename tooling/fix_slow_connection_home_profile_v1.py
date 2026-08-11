from pathlib import Path

path = Path('lib/screens/home_screen.dart')
text = path.read_text()
old = """        BufferProfile.balanced => 'Equilibrado',\n        BufferProfile.stable => 'Estable',\n        BufferProfile.custom => 'Personalizado',\n"""
new = """        BufferProfile.balanced => 'Equilibrado',\n        BufferProfile.stable => 'Estable',\n        BufferProfile.slowConnection => 'Conexión lenta',\n        BufferProfile.custom => 'Personalizado',\n"""
if old not in text:
    raise SystemExit('home profile switch not found')
path.write_text(text.replace(old, new, 1))
