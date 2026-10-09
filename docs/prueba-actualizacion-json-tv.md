# Prueba en TV: V52 corregida a V53

La base de esta prueba es la última compilación de `v52-lista-remota-correcta`,
commit `ecb7e29deb8d567a72fe8a007cccd9fd2df994a2`, run `37905308209`.
Es posterior a la V52 publicada originalmente. Incluye la M3U clásica remota,
los cambios de interfaz y logos de esa rama y el actualizador directo por JSON.

V52 se recupera del artifact original, con SHA-256
`6759f541352f1eba4d633ecfa63c18d20eb692be97e9427cf84e51070518fb10`.
V53 compila esa misma fuente y cambia sólo la versión a `1.4.21+3053`.
El workflow exige que `lib`, `android`, `assets`, `test` y `pubspec.lock`
sean idénticos a la base corregida. Usa el mismo Flutter 3.47.2 y la firma histórica.
Las dos APK son universales para ARM32/ARM64.

## Archivos que consulta esta APK

- Canales: `mi-lista-iptv-4k/main/lista_clasica.m3u`, actualizado por el script de la lista.
- Aviso y descarga de APK: `tvplayer/auto-update-json-test/update.json`.
- Esta compilación descarga la APK directamente; no necesita TV FULL Installer.

El puente Supabase propuesto en PR #33 corresponde a las APK anteriores.
No es el servidor que consulta esta compilación de prueba.

## Pasos en la TV

1. Instalar `TV-FULL-PRO-V52-REMOTA-JSON.apk` de la publicación V52 de prueba.
2. Abrir TV FULL PRO y verificar `1.4.20+3052`, los canales y la lista clásica.
3. Con V53 anunciada en el JSON, volver a la pantalla principal o reabrir la app.
   La APK también consulta cada cinco minutos mientras esa pantalla permanece abierta.
4. Debe aparecer una actualización a `1.4.21`.
5. Pulsar Actualizar. Si Android pide permiso para instalar aplicaciones desconocidas,
   habilitarlo para TV FULL PRO, volver a la app y pulsar Actualizar de nuevo.
6. Confirmar Actualizar en Android. Se actualiza el mismo paquete, sin desinstalar.
7. Reabrir y comprobar `1.4.21+3053`, que el cartel desapareció y que la lista sigue funcionando.

No desinstalar para hacer la prueba. Si la TV ya tiene un código superior a 3053,
Android no permite este salto como actualización y esa TV necesita otra versión de prueba.

## Publicar la actualización desde JSON

La app espera estos campos:

```json
{
  "version_code": 3053,
  "version_name": "1.4.21",
  "update_available": true,
  "apk_url": "ENLACE_HTTPS_DE_LA_APK_UNIVERSAL_PUBLICADA",
  "sha256": "SHA256_REAL_DE_LA_APK",
  "release_notes": "Prueba de actualización manteniendo la M3U remota y los últimos cambios.",
  "force_update": false
}
```

Editar únicamente `update.json` en la rama `auto-update-json-test`.
Comprobar que la descarga publicada coincide con el hash y está firmada con el
certificado histórico antes de activar. Para detener el aviso, poner
`update_available: false`. Las futuras versiones deben tener un código mayor
y conservar paquete y firma.

La validación del workflow no reemplaza la prueba física en la TV.
