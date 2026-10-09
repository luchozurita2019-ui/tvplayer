# Actualizaciones de TV FULL PRO desde un JSON

La APK ya busca actualizaciones en tvf-update. El Installer estable ya lee el archivo
tv_full_installer/latest.json de la rama android-tv-full-pro-clean-source.
El GET de tvf-update ahora transforma ese mismo archivo al contrato que la APK
existente entiende. Las próximas versiones se anuncian editando ese JSON;
no hay que recompilar la APK para cambiar el catálogo de actualizaciones.

JSON que usan las instalaciones existentes:
https://github.com/luchozurita2019-ui/tvplayer/blob/android-tv-full-pro-clean-source/tv_full_installer/latest.json

La copia de main no es el manifiesto que consulta el Installer estable.
Las ramas y APK de laboratorio no se promueven automáticamente.

## Preparación inicial

1. Aplicar esta propuesta a android-tv-full-pro-clean-source.
2. Desplegar supabase/functions/tvf-update/index.ts junto con release_manifest.mjs
   al mismo proyecto y función tvf-update. Conservar verify_jwt=false:
   el GET es público y las operaciones POST siguen comprobando el administrador.
3. Mantener enabled=false durante la comprobación.
4. Probar el botón en una TV con una versión anterior y TV FULL Installer instalado.
5. Cuando se apruebe publicar V52, cambiar enabled a true.

Esta propuesta incluye V52, versión 1.4.20 y código 3052, con enlaces, hashes y
tamaños obtenidos del release publicado. enabled=false evita anunciarla durante
la preparación.

downloaderUrl conserva el código existente https://aftv.news/9044759.
El destino de ese código todavía requiere confirmación: debe instalar
TV FULL Installer estable. Si el Installer falta, la APK muestra ese código para
Downloader. Si ya está instalado, el botón abre directamente el Installer y el
código no interviene en la descarga de TV FULL PRO.

## Publicar la próxima actualización

1. Compilar y probar ambas APK con el mismo paquete y certificado históricos.
2. Publicarlas en un release aprobado para el canal estable.
3. Actualizar el JSON de la rama indicada:
   - versionName: versión visible de la nueva APK.
   - versionCode: código real de la compilación, mayor que el anterior.
   - arm32 y arm64: URL de su APK, SHA-256 y tamaño en bytes.
   - packageName y certificateSha256: identidad histórica.
   - downloaderUrl: código para instalar TV FULL Installer, no el enlace de TV FULL PRO.
   - enabled: false durante la preparación; true para anunciarla.
4. Ejecutar la validación y comprobar el recorrido en una TV.
5. Publicar el JSON aprobado con enabled=true.

No se elige automáticamente el release con el número más alto: las builds de
laboratorio pueden tener números mayores y deben permanecer aisladas.

## Comportamiento de la app

La APK compara el versionCode anunciado con el instalado. Una TV en V51 verá V52;
una TV que ya tenga V52 no recibe ese mismo aviso de nuevo. La búsqueda ocurre
al abrir la pantalla principal, al volver a la app y cada cinco minutos mientras
esa pantalla siga montada. La propagación de GitHub también puede demorar.

El botón abre TV FULL Installer; éste elige ARM32/ARM64, descarga y comprueba la APK.
La instalación termina en la confirmación de Android. No es una instalación
silenciosa ni cambia el reproductor o la selección de canales.

Si el JSON falla, falta una arquitectura o los campos no son válidos, el servidor
devuelve una respuesta sin actualización y no reutiliza la versión antigua de
la base de datos. Las operaciones administrativas POST se conservan, pero sus
campos de versión ya no controlan el GET público: la publicación está en el JSON.

## Validación

Con Node.js 24:

    node --test supabase/functions/tests/tvf-update.test.mjs
    node scripts/check_update_server_syntax.mjs
    node scripts/validate_update_manifest.mjs
    node scripts/validate_update_manifest.mjs --online

La comprobación online exige que ambas URL, hashes y tamaños coincidan con el
release publicado, y rechaza borradores y prereleases. GITHUB_TOKEN es opcional
para consultar la API pública; en CI se usa el token de lectura de GitHub.

La prueba local valida el contrato y las condiciones de error. La comprobación
final de permisos, pantalla de instalación y firma en el dispositivo requiere
una TV; no se afirma que esa prueba ya se haya realizado.

