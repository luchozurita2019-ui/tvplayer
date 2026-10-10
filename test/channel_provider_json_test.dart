import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/playlist.dart';
import 'package:iptv_player/models/playlist_source_type.dart';
import 'package:iptv_player/services/provider_json_catalog_parser.dart';

import 'fixtures/provider_json_fixture.dart';

void main() {
  test('el guardado real en JSON conserva logo, DRM, tipo y headers', () {
    final original = const ProviderJsonCatalogParser()
        .parse(providerFixture())
        .channels
        .single;
    final saved = jsonEncode(original.toJson());
    final restored = Channel.fromJson(
      jsonDecode(saved) as Map<String, dynamic>,
    );
    expect(restored.logoBytes, base64Decode(testPngBase64));
    expect(restored.logoUrl, isNull);
    expect(restored.drmKeyId, testKeyId);
    expect(restored.drmKey, testKey);
    expect(restored.streamMimeType, 'application/x-mpegURL');
    expect(
      restored.resolvedHttpHeaders('Default')['User-Agent'],
      'Provider test agent',
    );
    expect(restored.uniqueKey, original.uniqueKey);
  });

  test('JSON de canales antiguos mantiene compatibilidad y no activa DRM', () {
    final old = Channel.fromJson({
      'name': 'Canal anterior',
      'url': 'https://example.test/live.ts',
      'httpUserAgent': 'Legacy UA',
      'httpReferrer': 'https://example.test/',
    });
    expect(old.hasDrmConfiguration, isFalse);
    expect(old.logoBytes, isNull);
    expect(old.resolvedHttpHeaders('Default'), {
      'User-Agent': 'Legacy UA',
      'Referer': 'https://example.test/',
    });
    expect(old.toJson().containsKey('drmKey'), isFalse);
  });

  test(
    'un par DRM guardado incompleto se rechaza, no se pierde silenciosamente',
    () {
      expect(
        () => Channel.fromJson({
          'name': 'Canal',
          'url': 'https://example.test/a.mpd',
          'drmKeyId': testKeyId,
        }),
        throwsFormatException,
      );
    },
  );

  test('el nuevo sourceType sobrevive a la serialización de Playlist', () {
    final value = Playlist(
      id: 'provider-json-1',
      name: 'Local',
      source: '/private/catalog.private.json',
      isRemote: false,
      channels: const [],
      lastUpdated: DateTime(2026),
      sourceType: PlaylistSourceType.localProviderJson,
    );
    final restored = Playlist.fromJson(jsonDecode(jsonEncode(value.toJson())));
    expect(restored.sourceType, PlaylistSourceType.localProviderJson);
    expect(restored.isRemote, isFalse);
    expect(PlaylistSourceType.values.take(3), [
      PlaylistSourceType.m3u,
      PlaylistSourceType.xtream,
      PlaylistSourceType.stalker,
    ]);
  });
}
