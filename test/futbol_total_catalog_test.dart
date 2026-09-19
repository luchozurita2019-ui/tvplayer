import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/futbol_total_agenda_parser.dart';
import 'package:iptv_player/services/futbol_total_authorized_fetcher.dart';
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

  group('FutbolTotalAuthorizedFetcher', () {
    test('envía sólo repos privados conocidos al proxy autorizado', () {
      expect(
        FutbolTotalAuthorizedFetcher.requiresAuthorizedProxy(
          'https://raw.githubusercontent.com/ByRafaelSystem/futboltotal-data/main/ft-flow2.json',
        ),
        isTrue,
      );
      expect(
        FutbolTotalAuthorizedFetcher.requiresAuthorizedProxy(
          'https://api.github.com/repos/ByRafaelSystem/futboltotal-data/contents/links2.json',
        ),
        isTrue,
      );
      expect(
        FutbolTotalAuthorizedFetcher.requiresAuthorizedProxy(
          'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
        ),
        isFalse,
      );
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

    test('omite WEBVIEW, conserva ClearKey válido y rechaza DRM inválido', () {
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
                "name": "DRM válido",
                "url": "https://example.com/live.mpd",
                "drm_license_uri": "kid:00112233445566778899aabbccddeeff,k:ffeeddccbbaa99887766554433221100"
              },
              {
                "name": "DRM inválido",
                "url": "https://example.com/bad.mpd",
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
      expect(parsed.channels, hasLength(2));
      expect(parsed.channels.first.name, 'DRM válido');
      expect(
        parsed.channels.first.drmKeyId,
        '00112233445566778899aabbccddeeff',
      );
      expect(
        parsed.channels.first.drmKey,
        'ffeeddccbbaa99887766554433221100',
      );
      expect(parsed.channels.first.streamMimeType, 'application/dash+xml');
      expect(parsed.channels.last.name, 'Libre');
      expect(parsed.skippedWeb, 1);
      expect(parsed.skippedDrm, 1);
    });

    test('modo web opcional conserva WEBVIEW y DIRECTO HTML sin tocar HLS', () {
      const json = r'''
      {
        "categories": [
          {
            "name": "Partidos",
            "samples": [
              {
                "name": "Web embed",
                "type": "WEBVIEW",
                "original_url": "https://embed.example.com/player.html",
                "headers": {"Referer": "https://origin.example.com/"}
              },
              {
                "name": "Directo HTML",
                "type": "DIRECTO",
                "original_url": "https://direct.example.com/live.php?id=1",
                "headers": {"Referer": "https://origin.example.com/"}
              },
              {
                "name": "Directo HLS",
                "type": "DIRECTO",
                "original_url": "https://cdn.example.com/live.m3u8"
              }
            ]
          }
        ]
      }
      ''';

      final parsed = const FutbolTotalFlowCatalogParser().parse(
        json,
        allowWebPlayback: true,
      );

      expect(parsed.channels, hasLength(3));
      expect(parsed.channels[0].streamMimeType, 'text/html');
      expect(parsed.channels[1].streamMimeType, 'text/html');
      expect(parsed.channels[2].streamMimeType, 'application/x-mpegURL');
      expect(parsed.channels[0].httpReferrer, 'https://origin.example.com/');
      expect(parsed.skippedWeb, 0);
    });

    test('modo normal sigue omitiendo WEBVIEW como antes', () {
      const json = r'''
      {
        "categories": [
          {
            "name": "TV",
            "samples": [
              {
                "name": "Web",
                "type": "WEBVIEW",
                "original_url": "https://example.com/player.html"
              },
              {
                "name": "HLS",
                "type": "HLS",
                "original_url": "https://example.com/live.m3u8"
              }
            ]
          }
        ]
      }
      ''';

      final parsed = const FutbolTotalFlowCatalogParser().parse(json);
      expect(parsed.channels, hasLength(1));
      expect(parsed.channels.single.name, 'HLS');
      expect(parsed.skippedWeb, 1);
    });

    test('rutea URLs Flow por el resolvedor dinámico sin perder DRM ni headers', () {
      const json = r'''
      {
        "categories": [
          {
            "name": "Internacionales",
            "samples": [
              {
                "name": "Flow DASH",
                "type": "CLEARKEY",
                "globalIndex": 368,
                "drm_license_uri": "kid:00112233445566778899aabbccddeeff,k:ffeeddccbbaa99887766554433221100",
                "original_url": "https://cdn-token.app.flow.com.ar/cdntoken/v2/generator?path=https://cdn-flow-balancer.app.flow.com.ar/live/c6eds/TV5/SA_Live_dash_enc/TV5.mpd",
                "headers": {
                  "Origin": "https://portal.app.flow.com.ar",
                  "Referer": "https://portal.app.flow.com.ar/",
                  "User-Agent": "Flow-UA"
                }
              }
            ]
          }
        ]
      }
      ''';

      final parsed = const FutbolTotalFlowCatalogParser().parse(json);
      final channel = parsed.channels.single;

      expect(channel.url, 'tvfull-dynamic://stream/368');
      expect(channel.dynamicStreamId, '368');
      expect(
        channel.dynamicStreamPath,
        contains('/live/c6eds/TV5/SA_Live_dash_enc/TV5.mpd'),
      );
      expect(channel.providerGlobalIndex, '368');
      expect(channel.streamMimeType, 'application/dash+xml');
      expect(channel.drmKeyId, '00112233445566778899aabbccddeeff');
      expect(channel.drmKey, 'ffeeddccbbaa99887766554433221100');
      expect(channel.httpUserAgent, 'Flow-UA');
      expect(channel.httpReferrer, 'https://portal.app.flow.com.ar/');
      expect(channel.httpHeaders?['Origin'], 'https://portal.app.flow.com.ar');
    });

    test('detecta HLS dentro de URLs generadoras y conserva ClearKey existente', () {
      const json = r'''
      {
        "categories": [
          {
            "name": "TV",
            "samples": [
              {
                "name": "Flow HLS",
                "type": "CLEARKEY",
                "drm_license_uri": "kid:00112233445566778899aabbccddeeff,k:ffeeddccbbaa99887766554433221100",
                "original_url": "https://cdn-token.app.flow.com.ar/generator?path=https://cdn.example.com/live/c7eds/test/playlist.m3u8",
                "headers": {
                  "Origin": "https://portal.app.flow.com.ar"
                }
              }
            ]
          }
        ]
      }
      ''';

      final channel =
          const FutbolTotalFlowCatalogParser().parse(json).channels.single;

      expect(channel.url, startsWith('tvfull-dynamic://stream/'));
      expect(channel.dynamicStreamPath, contains('playlist.m3u8'));
      expect(channel.streamMimeType, 'application/x-mpegURL');
      expect(channel.drmKeyId, isNotNull);
      expect(channel.drmKey, isNotNull);
    });
  });
}
