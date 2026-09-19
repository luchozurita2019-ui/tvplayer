import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/json_bridge_parser.dart';

void main() {
  group('JsonBridgeParser', () {
    test('convierte catalogo categories/samples a canales', () {
      const json = r'''
{
  "categories": [
    {
      "name": "Noticias",
      "samples": [
        {
          "name": "Canal Demo",
          "type": "HLS",
          "url": "https://example.com/live/demo.m3u8",
          "logo": "https://example.com/logo.png",
          "headers": {
            "Referer": "https://example.com/"
          }
        }
      ]
    }
  ]
}
''';

      final result = JsonBridgeParser.parse(json);
      expect(result.channels, hasLength(1));
      expect(result.categories, ['Noticias']);
      expect(result.channels.single.name, 'Canal Demo');
      expect(result.channels.single.url, 'https://example.com/live/demo.m3u8');
      expect(result.channels.single.httpReferrer, 'https://example.com/');
    });

    test('convierte agenda cuando canal_id tiene stream autorizado', () {
      const json = r'''
{
  "events": [
    {
      "status": "EN VIVO",
      "titulo": "Equipo A vs Equipo B",
      "canales": [
        {
          "canal_id": "demo-1",
          "canal": "Señal 1",
          "con_anuncios": false
        }
      ]
    }
  ],
  "streams": {
    "demo-1": {
      "url": "https://media.example.com/event/demo.m3u8",
      "headers": {
        "Origin": "https://media.example.com"
      }
    }
  }
}
''';

      final result = JsonBridgeParser.parse(json);
      expect(result.channels, hasLength(1));
      expect(result.channels.single.group, '🔴 EN VIVO · Equipo A vs Equipo B');
      expect(
        result.channels.single.url,
        'https://media.example.com/event/demo.m3u8',
      );
      expect(result.unresolved, 0);
    });

    test('no intenta resolver WEBVIEW, DRM ni ids sin URL', () {
      const json = r'''
[
  {
    "status": "proximo",
    "titulo": "Evento",
    "canales": [
      {"canal_id": "solo-id", "canal": "Sin resolver"},
      {"canal_id": "web", "canal": "Web", "type": "WEBVIEW", "url": "https://example.com/page"},
      {"canal_id": "drm", "canal": "DRM", "url": "https://example.com/a.mpd", "drm": "secret"}
    ]
  }
]
''';

      final result = JsonBridgeParser.parse(json);
      expect(result.channels, isEmpty);
      expect(result.unresolved, 1);
      expect(result.skippedWeb, 1);
      expect(result.skippedDrm, 1);
    });
  });
}
