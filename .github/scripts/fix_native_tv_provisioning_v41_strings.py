from pathlib import Path

path = Path('native-tv-complete/app/src/main/java/com/tvfull/pro/ProvisioningActivity.kt')
text = path.read_text(encoding='utf-8')
broken = 'Vinculá este televisor desde el panel de TV FULL.\nLas listas y servicios se cargarán automáticamente.'
# At this point the regex replacement has interpreted \\n as a real newline.
actual_broken = broken.replace('\\n', '\n')
fixed = broken
if actual_broken not in text:
    raise SystemExit('V4.1 provisioning broken newline marker not found')
text = text.replace(actual_broken, fixed, 1)
path.write_text(text, encoding='utf-8')
print('V4.1 provisioning Kotlin string escaping fixed successfully.')
