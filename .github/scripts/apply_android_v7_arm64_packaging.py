from pathlib import Path

GRADLE = Path('android/app/build.gradle.kts')
text = GRADLE.read_text()

if 'lib/x86_64/**' not in text:
    marker = 'android {\n'
    block = '''android {\n    packaging {\n        jniLibs {\n            excludes += setOf(\n                "lib/x86/**",\n                "lib/x86_64/**",\n                "lib/armeabi-v7a/**",\n            )\n        }\n    }\n'''
    if marker not in text:
        raise SystemExit('No se encontro bloque android en build.gradle.kts')
    text = text.replace(marker, block, 1)

GRADLE.write_text(text)

for required in ['lib/x86/**', 'lib/x86_64/**', 'lib/armeabi-v7a/**']:
    if required not in text:
        raise SystemExit(f'Falta exclusion ABI: {required}')

print('Empaquetado V7 limitado a librerias ARM64.')
