from pathlib import Path

path = Path('android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt')
text = path.read_text(encoding='utf-8')
old = '''        if (jwk != null) {
            LocalClearKeyDrm.validate(jwk)
            if (useHlsMime || (currentStreamMimeType == null && looksLikeHls(url))) {
                throw LocalClearKeyDrm.ConfigurationException(
                    "ClearKey con HLS no está soportado. Pedí al proveedor un stream DASH/CENC compatible."
                )
            }
        }
'''
new = '''        if (jwk != null) {
            // El catálogo autorizado del proveedor contiene ClearKey tanto en
            // DASH como en HLS. Media3 usa el mismo LocalMediaDrmCallback y la
            // selección del contenedor queda a cargo de MediaSourceFactory.
            LocalClearKeyDrm.validate(jwk)
        }
'''
count = text.count(old)
if count != 1:
    raise SystemExit(f'Expected exactly one legacy ClearKey/HLS guard, found {count}')
text = text.replace(old, new)
if 'ClearKey con HLS no está soportado' in text:
    raise SystemExit('Legacy ClearKey/HLS rejection is still present')
path.write_text(text, encoding='utf-8')
print('Provider ClearKey/HLS compatibility enabled in Android Media3 source.')
