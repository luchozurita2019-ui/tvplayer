TV FULL PRO V54 (1.4.22+3054) muestra el porcentaje, los MB y una barra durante la descarga. Al terminar indica la verificación y la apertura del instalador de Android.

Cuando Android solicita permiso para instalar aplicaciones, la APK verificada y la instalación pendiente quedan guardadas. Al volver con el permiso concedido, la app verifica otra vez el archivo y continúa sin descargarlo de nuevo. Si Android cerró el proceso, la instalación pendiente se recupera al abrir la app. El botón permite continuar o volver a abrir el instalador si se canceló.

Los archivos incompletos se descargan con extensión `.part` y se eliminan si falla la descarga. Solo se reutiliza una APK cuyo SHA-256 coincide con el JSON. Durante la operación el botón queda deshabilitado.

Basada en V53 `2506240741eca0a9b581043ab77add11fc3e0271`, que incluye los cambios de V52 corregida. Conserva la lista M3U remota, su actualización por script, la reproducción, los logos y el resto de la interfaz. El endpoint sigue siendo `auto-update-json-test/update.json` del repositorio tvplayer.

Paquete: `com.tvfull.pro.tv.v10safe`. Certificado histórico SHA-256: `40de9b14a83adb7b070e316a241e7f5a7f5b1705fdc43b5f495b0e1e3fcab02a`. APK universal con ARM32, ARM64 y x86_64.

Validación antes de publicar: análisis Dart, suite Flutter completa con pruebas del progreso, permisos, recuperación tras reinicio, reintento, cache alterada, SHA-256 incorrecto y descarga truncada; firma APK; paquete y versión; presencia de las URL M3U y JSON en todas las arquitecturas. La comprobación final en TV se realiza con el usuario.

La V53 instalada descarga V54 usando su interfaz anterior. El nuevo porcentaje y la recuperación automática de permisos empiezan a funcionar una vez instalada V54, en las siguientes actualizaciones.
