class FutbolTotalEndpoints {
  FutbolTotalEndpoints._();

  // Endpoints observados dentro de Fútbol Total 3.6.
  // No contienen tokens ni secretos.
  static const String manifestRaw =
      'https://raw.githubusercontent.com/ByRafaelSystem/futboltotal-data/main/ft-tv-lists2.json';
  static const String defaultFlowRaw =
      'https://raw.githubusercontent.com/ByRafaelSystem/futboltotal-data/main/ft-flow2.json';
  static const String linksRaw =
      'https://raw.githubusercontent.com/ByRafaelSystem/futboltotal-data/main/links2.json';
  static const String linksApi =
      'https://api.github.com/repos/ByRafaelSystem/futboltotal-data/contents/links2.json';

  static const String primaryWorker =
      'https://novax-online.iptvnovax.workers.dev';
  static const String secondaryWorker =
      'https://ft-online.ftsystem.workers.dev';

  // Puente privado TV FULL: firma y descarga los JSON protegidos sin
  // exponer la compatibilidad criptográfica dentro del APK público.
  static const String authorizedProxy =
      'https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1/tvf-futboltotal-proxy';

  // Manifiesto controlado por TV FULL para validar el adaptador sin depender
  // todavía de autenticación remota de Fútbol Total.
  static const String integrationTestManifest =
      'https://raw.githubusercontent.com/luchozurita2019-ui/tvplayer/futboltotal-test-data/test_data/ft-tv-lists2.test.json';

  static const List<(String from, String to)> webMirrors = [
    ('https://deporte-libre.icu', 'https://deporte-libre.st/'),
    ('https://futbol-libres.su', 'https://futbollibres.net/'),
    ('https://librefutboltv.su', 'https://futbollibres.net/'),
  ];
}
