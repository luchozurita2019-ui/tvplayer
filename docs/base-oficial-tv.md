# Base oficial de TV FULL PRO

`main` es la base para continuar el desarrollo y abrir las próximas pull requests.
Su punto de partida es la V54 publicada: **1.4.22+3054**, código
`0dd09bb7f81e577646ad2ae536cea98376198ab1`.

La integración conserva exactamente `lib/`, `android/`, `assets/`, `test/`,
`pubspec.yaml` y `pubspec.lock` de esa V54. También conserva la historia previa
de `main` y la historia de la rama que produjo la APK. Los cambios adicionales
son metadatos de distribución, documentación y controles de compilación.

## Referencias verificadas

- Paquete: `com.tvfull.pro.tv.v10safe`.
- Certificado histórico SHA-256: `40de9b14a83adb7b070e316a241e7f5a7f5b1705fdc43b5f495b0e1e3fcab02a`.
- APK publicada: [TV-FULL-PRO-V54-REMOTA-JSON.apk](https://github.com/luchozurita2019-ui/tvplayer/releases/download/tv-full-pro-v54-update-progress-3054-test/TV-FULL-PRO-V54-REMOTA-JSON.apk).
- SHA-256 de la APK publicada: `08e394aba3dcedf8fe7a8baa58f5779b810c326b1b5f108af421275f7b447d90`.
- JSON activo de la app: `https://raw.githubusercontent.com/luchozurita2019-ui/tvplayer/auto-update-json-test/update.json`.
- M3U activa: `https://raw.githubusercontent.com/luchozurita2019-ui/mi-lista-iptv-4k/main/lista_clasica.m3u`.

`update.json` en `main` documenta el manifiesto publicado. La app instalada sigue
consultando el endpoint de `auto-update-json-test`; integrar código en `main`
no cambia ese endpoint ni envía una actualización a las TVs.
`tv_full_installer/latest.json` en `main` describe la misma APK universal,
compatible con ARM32 y ARM64. Los endpoints de instaladores anteriores
permanecen en sus ramas existentes.

## Validación y próximas versiones

El workflow **TV FULL PRO - base oficial** valida metadatos, dependencias
bloqueadas, análisis Dart y los tests. Las pull requests internas y las
ejecuciones manuales además compilan una APK universal, comprueban paquete,
versión, firma histórica y presencia de M3U/JSON en ARM32 y ARM64. Sólo guarda
las comprobaciones; no crea releases ni modifica el JSON activo.

Mientras la versión siga siendo 3054, CI exige que el código de la app coincida
con la V54 publicada. Para modificar la app, hay que aumentar el versionCode
desde 3054 en una rama creada a partir de `main` y abrir una pull request.
El versionCode debe superar también el de cualquier APK instalada en las TVs
que reciban esa actualización; los experimentos en otras ramas tienen su
propia numeración y no definen la base oficial.

Una compilación nueva tendrá su propio SHA-256. El SHA de V54 corresponde
exclusivamente al archivo ya publicado. Sólo después de validar una release
nueva deben actualizarse las URL y hashes de distribución, y finalmente el
JSON activo. No se sobrescriben los archivos de V54.

Los workflows de releases antiguas se ejecutan sólo en sus ramas originales.
Para compilar desde `main`, usar **TV FULL PRO - base oficial**.
