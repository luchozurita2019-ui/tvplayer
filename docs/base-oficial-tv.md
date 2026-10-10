# Base oficial de TV FULL PRO

`main` es la base para continuar el desarrollo y abrir las próximas pull requests.
La versión actual del código es **V55, 1.4.23+3055**. Su punto de partida es la V54 publicada: **1.4.22+3054**, código
`0dd09bb7f81e577646ad2ae536cea98376198ab1`.

La integración inicial conservó exactamente `lib/`, `android/`, `assets/`, `test/`,
`pubspec.yaml` y `pubspec.lock` de esa V54. También conserva la historia previa
de `main` y la historia de la rama que produjo la APK. Los cambios adicionales
fueron metadatos de distribución, documentación y controles de compilación.

La V55 agrega respaldo por canal al modelo, parser M3U y pantalla Media3 de
Android TV, con sus pruebas. No cambia el código Android, los proveedores,
assets, dependencias ni el actualizador. Detalles: [respaldo-canales-v55.md](respaldo-canales-v55.md).
Su APK de prueba se compiló desde `f7626b6efed56fccfad2d9ddc1e691f8437071de`,
después de pasar análisis y 90 pruebas, y se verificó con la firma histórica.

## Referencias verificadas

- Paquete: `com.tvfull.pro.tv.v10safe`.
- Certificado histórico SHA-256: `40de9b14a83adb7b070e316a241e7f5a7f5b1705fdc43b5f495b0e1e3fcab02a`.
- APK distribuida: [TV-FULL-PRO-V55-RESPALDOS.apk](https://github.com/luchozurita2019-ui/tvplayer/releases/download/tv-full-pro-v55-channel-backups-3055/TV-FULL-PRO-V55-RESPALDOS.apk).
- SHA-256 de la APK distribuida: `585221ee2d02aa3a3217b764b28adc24f71b3d4a0e9d908cb0207e7b0b61a3b6`.
- JSON activo de la app: `https://raw.githubusercontent.com/luchozurita2019-ui/tvplayer/auto-update-json-test/update.json`.
- M3U activa: `https://raw.githubusercontent.com/luchozurita2019-ui/mi-lista-iptv-4k/main/lista_clasica.m3u`.

`update.json` en `main` documenta el manifiesto publicado. La app instalada sigue
consultando el endpoint de `auto-update-json-test`; integrar código en `main`
no cambia ese endpoint ni envía una actualización a las TVs.
`tv_full_installer/latest.json` en `main` describe la misma APK universal V55,
compatible con ARM32 y ARM64. Los endpoints de instaladores anteriores
permanecen en sus ramas existentes.

## V55 distribuida con actualización no forzada

- Instalador: [TV-FULL-PRO-V55-RESPALDOS.apk](https://github.com/luchozurita2019-ui/tvplayer/releases/download/tv-full-pro-v55-channel-backups-3055/TV-FULL-PRO-V55-RESPALDOS.apk).
- SHA-256: `585221ee2d02aa3a3217b764b28adc24f71b3d4a0e9d908cb0207e7b0b61a3b6`.
- Versión: `1.4.23+3055`; paquete y certificado iguales a V54.

La release V55 se compiló y firmó con el certificado histórico; el JSON activo de
`auto-update-json-test` y el manifiesto utilizado por el instalador en
`android-tv-full-pro-clean-source` apuntan a la APK universal V55. La actualización
no es forzada: las TV con una versión anterior pueden descargar e instalar V55
cuando consulten el manifiesto. No se garantiza la instalación hasta probarla
correctamente en cada dispositivo. La lista M3U pública todavía no declara
respaldos, por lo que el cambio automático de señal quedará pendiente hasta
que se habilite la lista con alternativas comprobadas.

## Validación y próximas versiones

El workflow **TV FULL PRO - base oficial** valida metadatos, dependencias
bloqueadas, análisis Dart y los tests. Las pull requests internas y las
ejecuciones manuales además compilan una APK universal, comprueban paquete,
versión, firma histórica y presencia de M3U/JSON en ARM32 y ARM64. Para V55,
un push de código de ejecución a main también compila y publica la release
de prueba, después de validar. Los cambios sólo de documentación/manifiestos
no generan otra APK. El workflow no modifica el JSON activo.

La base oficial mantiene código y manifiestos en V55 (3055). Para modificar la app,
hay que aumentar el versionCode
por encima de la versión actual en una rama creada a partir de `main` y abrir
una pull request. La siguiente versión debe superar 3055.
El versionCode debe superar también el de cualquier APK instalada en las TVs
que reciban esa actualización; los experimentos en otras ramas tienen su
propia numeración y no definen la base oficial.

Una compilación nueva tendrá su propio SHA-256. No debe reutilizarse el hash
ni sobrescribirse ninguna APK de una versión anterior. Sólo después de validar una release
nueva deben actualizarse las URL y hashes de distribución, y finalmente el
JSON activo. No se sobrescriben los archivos de V54.

Los workflows de releases antiguas se ejecutan sólo en sus ramas originales.
Para compilar desde `main`, usar **TV FULL PRO - base oficial**.
