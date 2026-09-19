/*
 * Capturador de diagnóstico autorizado para Fútbol Total v3.6.
 *
 * Uso previsto: ejecutar contra la APK ORIGINAL instalada y firmada por Rafael.
 * No modifica respuestas, firmas, tokens ni comportamiento de la aplicación.
 * Sólo observa el String que Q1.i.d(...) ya devolvió a la propia app.
 *
 * Ejemplo:
 *   frida -U -f com.byrafael.streamapp -l tools/capturar_futboltotal_json.js
 */

Java.perform(function () {
  const Targets = [
    'ft-tv-lists2.json',
    'ft-flow2.json',
    'links2.json',
    'ft-mundotv.json',
    'ft-key-sources.json',
    'ft-logos.json'
  ];

  function wanted(url) {
    if (!url) return false;
    const value = String(url);
    return Targets.some(function (name) {
      return value.indexOf(name) !== -1;
    });
  }

  try {
    const Loader = Java.use('Q1.i');
    const fetch = Loader.d.overload(
      'java.lang.String',
      'boolean',
      'K2.l'
    );

    fetch.implementation = function (url, noCache, callback) {
      const result = fetch.call(this, url, noCache, callback);

      if (wanted(url) && result) {
        const payload = {
          type: 'futboltotal-json',
          url: String(url),
          length: String(result).length,
          content: String(result)
        };

        send(payload);
        console.log(
          '\n========== FUTBOL TOTAL JSON ==========' +
          '\nURL: ' + payload.url +
          '\nBYTES/TEXT: ' + payload.length +
          '\n' + payload.content +
          '\n========== FIN JSON ==========\n'
        );
      }

      return result;
    };

    console.log('[OK] Hook Q1.i.d instalado. Abrí Modo TV / Fútbol.');
  } catch (error) {
    console.log('[ERROR] No se pudo instalar hook Q1.i.d: ' + error);
  }
});
