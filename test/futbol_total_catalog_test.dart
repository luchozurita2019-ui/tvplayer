import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/futbol_total_agenda_parser.dart';
import 'package:iptv_player/services/futbol_total_embedded_config.dart';
import 'package:iptv_player/services/futbol_total_flow_catalog_parser.dart';
import 'package:iptv_player/services/futbol_total_manifest_parser.dart';

void main() {
  group('FutbolTotalEmbeddedConfig', () {
    test('replica el fallback Flow completo observado en v3.6', () {
      final manifest = FutbolTotalEmbeddedConfig.fallbackManifest();
      expect(manifest.lists, hasLength(1));
      expect(manifest.lists.single.name, 'Flow completo');
      expect(manifest.lists.single.kind, 'flow');
      expect(
        manifest.lists.single.url,
        FutbolTotalEmbeddedConfig.flowFallbackUrl,
      );
      expect(manifest.lists.single.ttlSeconds, 0);
    });

    test('conserva los endpoints públicos embebidos sin secretos', () {
      expect(FutbolTotalEmbeddedConfig.manifestUrl, contains('ft-tv-lists2.json'));
      expect(FutbolTotalEmbeddedConfig.linksUrl, contains('links2.json'));
      expect(FutbolTotalEmbeddedConfig.primaryWorker, startsWith('https://'));
      expect(FutbolTotalEmbeddedConfig.secondaryWorker, startsWith('https://'));
    });
  });

  group('FutbolTotalManifestParser', () {
    test('lee lists y reglas de futbol', () {
      const json = r'''
      {
        "futbol": {
          "evento_path": "/evento.php?id=",
          "iframe": "iframe",
          "descartar": ["/chat/"],
          "saltos": [
            {"host": "example.com", "modo": "webview", "playback": "m3u8"}
          ]
        },
        "lists": [
          {
            "name": "Flow Premium",
            "url": "https://example.com/flow.json",
            "kind": "flow",
            "ttl": 120
          },
          {
            "name": "Fútbol",
            "url": "https://example.com/agenda.json",
            "kind": "futbol",
            "ttl": 30
          }
        ]
      }
      ''';

      final parsed = const FutbolTotalManifestParser().parse(json);
      expect(parsed.lists, hasLength(2));
      expect(parsed.flowLists.single.name, 'Flow Premium');
      expect(parsed.futbolLists.single.url, 'https://example.com/agenda.json');
      expect(parsed.futbolRules.eventoPath, '/evento.php?id=');
      expect(parsed.futbolRules.hops.single.webViewMode, isTrue);
    });

    test('kind vacío cae a flow y ttl negativo a cero', () {
      const json = r'''
      {
        "lists": [
          {"name": "TV", "url": "https://example.com/tv.json", "kind": "", "ttl": -5}
        ]
      }
      ''';

      final parsed = const FutbolTotalManifestParser().parse(json);
      expect(parsed.lists.single.kind, 'flow');
      expect(parsed.lists.single.ttlSeconds, 0);
    });
  });

  group('FutbolTotalAgendaParser', () {
    test('omite finales y canales con anuncios', () {
      const json = r'''
      [
        {
          "status": "FINAL",
          "titulo": "Terminado",
          "ts_utc": 1,
          "canales": [
            {"canal_id": "fin", "canal": "Canal final", "con_anuncios": false}
          ]
        },
        {
          "status": "EN VIVO",
          "titulo": "Equipo A vs Equipo B",
          "ts_utc": 123456,
          "canales": [
            {"canal_id": "ads", "canal": "Con anuncios", "con_anuncios": true},
            {"canal_id": "senal-1", "canal": "Señal 1", "con_anuncios": false}
          ]
        }
      ]
      ''';

      final parsed = const FutbolTotalAgendaParser().parse(json);
      expect(parsed.events, hasLength(1));
      expect(parsed.events.single.title, 'Equipo A vs Equipo B');
      expect(parsed.events.single.channels.single.canalId, 'senal-1');
      expect(parsed.channelCount, 1);
      expect(parsed.events.single.isLive, isTrue);
    });

    test('crea la referencia base-origen|canal_id observada en la APK', () {
      final ref = FutbolTotalAgendaReference.fromAgendaUrl(
        'https://agenda.example.com:8443/agenda/lista.json',
        'canal-25',
      );
      expect(ref.baseOrigin, 'https://agenda.example.com:8443');
      expect(ref.encoded, 'https://agenda.example.com:8443|canal-25');
      expect(
        FutbolTotalAgendaReference.parse(ref.encoded).canalId,
        'canal-25',
      );
    });

    test('construye evento_path + canal_id en el mismo origen', () {
      final ref = FutbolTotalAgendaReference.fromAgendaUrl(
        'https://agenda.example.com/agenda/lista.json',
        'abc123',
      );
      final request = const FutbolTotalEventUrlBuilder().build(
        ref,
        '/evento.php?id=',
      );
      expect(
        request.url.toString(),
        'https://agenda.example.com/evento.php?id=abc123',
      );
      expect(request.referer, 'https://agenda.example.com');
    });
  });

  group('FutbolTotalFlowCatalogParser', () {
    test('usa original_url, fallback url y conserva headers', () {
      const json = r'''
      {
        "seeds": ["https://seed.example.com/a.mpd"],
        "seed_ua": "FT-UA",
        "categories": [
          {
            "name": "Deportes",
            "samples": [
              {
                "name": "Canal 1",
                "original_url": "https://media.example.com/live/1.m3u8",
                "url": "https://fallback.invalid/live.m3u8",
                "icono": "https://media.example.com/logo.png",
                "headers": {
                  "User-Agent": "Player-UA",
                  "Referer": "https://media.example.com/"
                }
              },
              {
                "name": "Canal 2",
                "url": "https://media.example.com/live/2.m3u8"
              }
            ]
          }
        ]
      }
      ''';

      final parsed = const FutbolTotalFlowCatalogParser().parse(json);
      expect(parsed.channels, hasLength(2));
      expect(
        parsed.channels.first.url,
        'https://media.example.com/live/1.m3u8',
      );
      expect(parsed.channels.first.httpUserAgent, 'Player-UA');
      expect(parsed.channels.first.httpReferrer, 'https://media.example.com/');
      expect(parsed.seedUserAgent, 'FT-UA');
    });

    test('omite WEBVIEW y DRM sin afectar canales directos', () {
      const json = r'''
      {
        "categories": [
          {
            "name": "TV",
            "samples": [
              {
                "name": "Web",
                "url": "https://example.com/web",
                "type": "WEBVIEW"
              },
              {
                "name": "DRM",
                "url": "https://example.com/live.mpd",
                "drm_license_uri": "clearkey://example"
              },
              {
                "name": "Libre",
                "url": "https://example.com/live.m3u8"
              }
            ]
          }
        ]
      }
      ''';

      final parsed = const FutbolTotalFlowCatalogParser().parse(json);
      expect(parsed.channels.single.name, 'Libre');
      expect(parsed.skippedWeb, 1);
      expect(parsed.skippedDrm, 1);
    });
  });
}
