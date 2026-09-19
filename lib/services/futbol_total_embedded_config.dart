import 'futbol_total_manifest_parser.dart';

/// Configuración pública/no secreta observada directamente en
/// Fútbol Total v3.6.
///
/// No contiene tokens, firmas, claves ni credenciales.
class FutbolTotalEmbeddedConfig {
  static const manifestUrl =
      'https://raw.githubusercontent.com/ByRafaelSystem/futboltotal-data/main/ft-tv-lists2.json';

  static const flowFallbackUrl =
      'https://raw.githubusercontent.com/ByRafaelSystem/futboltotal-data/main/ft-flow2.json';

  static const linksUrl =
      'https://raw.githubusercontent.com/ByRafaelSystem/futboltotal-data/main/links2.json';

  static const linksApiUrl =
      'https://api.github.com/repos/ByRafaelSystem/futboltotal-data/contents/links2.json';

  static const primaryWorker =
      'https://novax-online.iptvnovax.workers.dev';

  static const secondaryWorker =
      'https://ft-online.ftsystem.workers.dev';

  /// Replica el fallback observado en MainActivity.S0():
  /// si el manifiesto no entrega listas válidas, la app usa
  /// "Flow completo" apuntando a ft-flow2.json.
  static FutbolTotalManifest fallbackManifest() {
    return FutbolTotalManifest(
      lists: const [
        FutbolTotalListDefinition(
          name: 'Flow completo',
          url: flowFallbackUrl,
          kind: 'flow',
          ttlSeconds: 0,
        ),
      ],
      futbolRules: FutbolTotalRemoteRules.empty(),
    );
  }
}
