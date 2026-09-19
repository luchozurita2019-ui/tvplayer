import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/futbol_total_flow_catalog_parser.dart';
import 'package:iptv_player/services/futbol_total_manifest_parser.dart';

void main() {
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
