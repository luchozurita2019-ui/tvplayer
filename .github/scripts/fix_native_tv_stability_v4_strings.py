from pathlib import Path

path = Path('native-tv-complete/app/src/main/java/com/tvfull/pro/ProvisioningActivity.kt')
text = path.read_text(encoding='utf-8')

broken = 'text = "Vinculá este televisor desde el panel de TV FULL.\nLas listas y servicios se cargarán automáticamente."'
fixed = 'text = "Vinculá este televisor desde el panel de TV FULL.\\nLas listas y servicios se cargarán automáticamente."'

if broken not in text:
    raise SystemExit('V4 provisioning multiline Kotlin marker not found')

path.write_text(text.replace(broken, fixed, 1), encoding='utf-8')
print('V4 Kotlin string escaping fixed successfully.')
