# IPTV Player

Reproductor de listas M3U/M3U8 gratuito, de código abierto y multiplataforma
(macOS, Windows, Android, iOS, Linux), construido con Flutter.

## Robustez ante servidores IPTV lentos o inestables

Este es el punto que realmente separa un reproductor "que se cuelga"
de uno confiable. La app implementa:

- **Parseo en isolate** (`compute()`): listas de miles de canales se
  procesan en un hilo aparte, así la UI nunca se congela mientras carga
  una lista pesada.
- **Reintentos con backoff exponencial al descargar la lista M3U**
  (1s, 2s, 4s): muchos servidores IPTV fallan de forma intermitente,
  y un segundo intento suele bastar.
- **Watchdog de reproducción**: si el stream deja de avanzar en
  silencio (sin lanzar error, algo muy común cuando el servidor corta
  el feed sin cerrar la conexión), la app lo detecta a los 10 segundos
  y reconecta sola.
- **Reconexión automática con backoff** ante errores de reproducción,
  hasta 5 intentos, antes de pedirle algo al usuario.
- **Cliente HTTP con keep-alive** reutilizado entre requests, en vez
  de abrir una conexión nueva cada vez.

Ninguna app puede garantizar velocidad si el servidor IPTV del que
depende (tu proveedor de la lista M3U) es lento — eso está fuera del
control del reproductor. Lo que sí controla el reproductor es no
quedarse trabado esperando, y reconectar solo cuando el servidor
vuelve a responder.

## Por qué es fluido

La fluidez de un reproductor IPTV depende casi por completo del motor de
decodificación, no de la UI. Esta app usa **[media_kit](https://pub.dev/packages/media_kit)**,
que envuelve **libmpv/FFmpeg nativo**:

- Decodificación por hardware cuando el sistema lo permite.
- Buffer configurado bajo (8MB) para streams en vivo: prioriza arranque
  rápido sobre buffering profundo.
- Sin WebView ni reproductor HTML5 de por medio (la causa más común de
  lag en apps IPTV mal hechas).
- `ListView.builder` en las listas de canales: solo se renderiza lo que
  está en pantalla, así que listas de 10.000+ canales no ralentizan el
  scroll.
- Los logos de canal cargan de forma asíncrona con fallback inmediato,
  así una imagen caída o lenta nunca bloquea la lista.

## Funciones incluidas

- Múltiples listas M3U (remotas por URL, o archivo local).
- Favoritos persistentes.
- Búsqueda en tiempo real por nombre y categoría.
- Filtro por categorías (`group-title` del M3U).
- Reproductor con navegación siguiente/anterior dentro de la lista filtrada.
- Reintentos claros si un canal falla (sin dejar la pantalla en negro sin feedback).

## Cómo correrlo

```bash
flutter pub get
flutter run -d macos     # o windows / chrome / android / ios
```

## Cómo compilar

```bash
flutter build macos --release
flutter build windows --release
flutter build apk --release
flutter build ios --release
```

## Cómo generar el instalador (.dmg)

### Opción A — sin instalar nada, usando GitHub Actions (recomendado)

1. Creá un repositorio nuevo en GitHub y subí esta carpeta completa
   (incluye `.github/workflows/build-macos.yml`, ya configurado).
2. Andá a la pestaña **Actions** del repo → el workflow "Build macOS
   Installer" corre solo. Si no arranca automáticamente, tocá
   **Run workflow**.
3. Esperá unos minutos (compila en un Mac real de GitHub, gratis).
4. Cuando termine, entrá al resultado del workflow y descargá el
   artefacto **IPTV-Player-Installer** → es el `.dmg` listo para
   instalar en cualquier Mac.

No necesitás tener Flutter, Xcode ni una Mac para generarlo con este
método: todo pasa en la nube de GitHub.

### Opción B — localmente, si ya tenés Flutter + Xcode

```bash
./build_installer.sh
```

Genera `dist/IPTV-Player-Installer.dmg`.

## Próximos pasos sugeridos

1. **EPG (guía de programación)**: cruzar `tvg-id` con un XMLTV para
   mostrar qué se está emitiendo ahora en cada canal.
2. **Timeshift/grabación**: FFmpeg (ya incluido vía media_kit) soporta
   grabar el stream a disco mientras se reproduce.
3. **Perfiles de usuario / control parental**.
4. **Sincronización de favoritos en la nube** (ej. Firebase gratuito o
   backend propio) para tener las mismas listas en todos los dispositivos.
5. **Modo picture-in-picture** en móvil.

## Estructura del proyecto

```
lib/
  models/       Channel, Playlist
  services/      m3u_parser.dart, m3u_fetcher.dart, storage_service.dart
  providers/     iptv_provider.dart (estado global)
  screens/       home, channel_list, player
  widgets/       channel_tile
```
