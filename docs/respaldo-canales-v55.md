# TV FULL PRO V55: respaldo de señales por canal

Versión 1.4.23+3055, construida desde main alineado con la V54 publicada.

La Lista clásica puede declarar hasta dos señales alternativas mediante comentarios `#EXT-X-TVFULL-BACKUP:` con JSON `url` y `headers`. Hay una sola entrada visible por canal. La V54 ignora estos comentarios y conserva la señal principal; la V55 los guarda también en el catálogo y favoritos.

En Android TV se utiliza el mismo reproductor Media3, sin cambios en el código Android, perfiles de memoria, DRM ni resolvedor dinámico. Después de que Media3 agota sus recuperaciones y comunica un error, una señal sin progreso o un fin inesperado, la V55 abre el siguiente respaldo del mismo canal. Sus headers se usan de manera independiente: no se copian Cookie ni Authorization de la señal anterior.

Cada alternativa se intenta una vez por recorrido. Al agotarse las tres señales aparece un error con Reintentar; no hay un bucle infinito. Reintentar inicia un recorrido nuevo. Cambiar de canal cancela los reintentos y descarta eventos de la generación anterior. La identidad, el nombre y los favoritos siguen siendo los del canal original.

Las fuentes sin respaldos conservan la política de recuperación de V54. Las fuentes con DRM o resolvedor dinámico siguen por su recorrido existente. La selección de respaldos depende de la lista: no se inventa una señal para canales sin otra fuente comprobada.

Paquete `com.tvfull.pro.tv.v10safe`, certificado histórico, URL de la Lista clásica y endpoint de actualización JSON se conservan. La descarga con porcentaje y reanudación de instalación de V54 sigue incluida.

Validación: análisis de lib/test, toda la batería existente, pruebas de lectura y persistencia de respaldos, headers separados, error 403, fin de señal, eventos antiguos, agotamiento de fuentes y cambio de canal. La compilación verifica versión, paquete, certificado y URLs incluidas en la APK.

Para probar en el televisor, instalar V55, actualizar la Lista clásica y abrir un canal con respaldos. Cuando una fuente falla debe mostrarse «Probando respaldo 1…» y continuar el mismo canal si la otra señal responde. Las pruebas automatizadas simulan errores del reproductor; no certifican la conectividad ni la decodificación en cada modelo de televisor.
