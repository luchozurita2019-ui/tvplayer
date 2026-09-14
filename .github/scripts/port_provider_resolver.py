from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f"Expected block not found in {path}: {old[:100]!r}")
    file.write_text(text.replace(old, new, 1))


# Channel keeps the stable resolver identity and the original provider metadata.
replace_once(
    "lib/models/channel.dart",
    "  final String? xtreamStreamId; // stream_id real para APIs Xtream (EPG, etc.)\n",
    "  final String? xtreamStreamId; // stream_id real para APIs Xtream (EPG, etc.)\n"
    "  final String? dynamicStreamId; // identidad estable usada por el resolvedor\n"
    "  final String? dynamicStreamPath; // ruta original de provider.json\n"
    "  final String? providerGlobalIndex; // índice del catálogo si el proveedor lo usa\n",
)
replace_once(
    "lib/models/channel.dart",
    "    this.xtreamStreamId,\n    this.httpUserAgent,\n",
    "    this.xtreamStreamId,\n"
    "    this.dynamicStreamId,\n"
    "    this.dynamicStreamPath,\n"
    "    this.providerGlobalIndex,\n"
    "    this.httpUserAgent,\n",
)
replace_once(
    "lib/models/channel.dart",
    "        'xtreamStreamId': xtreamStreamId,\n        'httpUserAgent': httpUserAgent,\n",
    "        'xtreamStreamId': xtreamStreamId,\n"
    "        if (dynamicStreamId != null) 'dynamicStreamId': dynamicStreamId,\n"
    "        if (dynamicStreamPath != null) 'dynamicStreamPath': dynamicStreamPath,\n"
    "        if (providerGlobalIndex != null) 'providerGlobalIndex': providerGlobalIndex,\n"
    "        'httpUserAgent': httpUserAgent,\n",
)
replace_once(
    "lib/models/channel.dart",
    "      xtreamStreamId: json['xtreamStreamId'] as String?,\n      httpUserAgent: json['httpUserAgent'] as String?,\n",
    "      xtreamStreamId: json['xtreamStreamId'] as String?,\n"
    "      dynamicStreamId: json['dynamicStreamId'] as String?,\n"
    "      dynamicStreamPath: json['dynamicStreamPath'] as String?,\n"
    "      providerGlobalIndex: json['providerGlobalIndex'] as String?,\n"
    "      httpUserAgent: json['httpUserAgent'] as String?,\n",
)
replace_once(
    "lib/models/channel.dart",
    "  String get uniqueKey => '$name|$url';\n",
    "  String get uniqueKey {\n"
    "    final dynamicId = dynamicStreamId?.trim();\n"
    "    return dynamicId == null || dynamicId.isEmpty\n"
    "        ? '$name|$url'\n"
    "        : '$name|dynamic:$dynamicId';\n"
    "  }\n",
)

# provider.json accepts direct URLs as before and retains true relative paths as
# dynamic channels. Arbitrary schemes remain invalid.
replace_once(
    "lib/services/provider_json_catalog_parser.dart",
    "  static const maxIconBytes = 2 * 1024 * 1024;\n",
    "  static const maxIconBytes = 2 * 1024 * 1024;\n"
    "  static const dynamicStreamPrefix = 'tvfull-dynamic://stream/';\n",
)
replace_once(
    "lib/services/provider_json_catalog_parser.dart",
    "    final baseUri = _catalogBaseUri(root);\n    final categories = root['categories'] as List;\n",
    "    final baseUri = _catalogBaseUri(root);\n"
    "    final resolveAll =\n"
    "        root['resolver_mode']?.toString().trim().toLowerCase() == 'all';\n"
    "    final categories = root['categories'] as List;\n",
)
replace_once(
    "lib/services/provider_json_catalog_parser.dart",
    "            _sample(samples[j], group, samplePath, warnings, baseUri),\n",
    "            _sample(\n"
    "              samples[j],\n"
    "              group,\n"
    "              samplePath,\n"
    "              warnings,\n"
    "              baseUri,\n"
    "              resolveAll,\n"
    "            ),\n",
)
replace_once(
    "lib/services/provider_json_catalog_parser.dart",
    "    List<String> warnings,\n    Uri? baseUri,\n  ) {\n",
    "    List<String> warnings,\n    Uri? baseUri,\n    bool resolveAll,\n  ) {\n",
)
replace_once(
    "lib/services/provider_json_catalog_parser.dart",
    "    if (rawUrl is! String || rawUrl.trim().isEmpty) {\n"
    "      throw const FormatException('Falta original_url de tipo texto.');\n"
    "    }\n\n"
    "    final url = _resolveStreamUrl(rawUrl.trim(), baseUri);\n",
    "    if (rawUrl is! String || rawUrl.trim().isEmpty) {\n"
    "      throw const FormatException('Falta original_url de tipo texto.');\n"
    "    }\n\n"
    "    final originalUrl = rawUrl.trim();\n"
    "    final parsedOriginal = Uri.tryParse(originalUrl);\n"
    "    final direct = _isHttpUrl(originalUrl);\n"
    "    if (!direct &&\n"
    "        (parsedOriginal == null ||\n"
    "            parsedOriginal.hasScheme ||\n"
    "            parsedOriginal.hasAuthority ||\n"
    "            originalUrl.startsWith('//') ||\n"
    "            RegExp(r'[\\x00-\\x20]').hasMatch(originalUrl))) {\n"
    "      throw const FormatException('original_url relativa inválida.');\n"
    "    }\n"
    "    final explicitResolverId = _firstText(\n"
    "      raw,\n"
    "      const ['resolver_id', 'stream_id', 'id'],\n"
    "    );\n"
    "    final globalIndexRaw = raw['globalIndex']?.toString().trim();\n"
    "    final globalIndex = globalIndexRaw == null || globalIndexRaw.isEmpty\n"
    "        ? null\n"
    "        : globalIndexRaw;\n"
    "    final dynamicId = explicitResolverId ?? globalIndex ?? originalUrl;\n"
    "    final sampleResolverRequired = raw['resolver_required'] == true ||\n"
    "        raw['resolver_required']?.toString().toLowerCase() == 'true';\n"
    "    final shouldResolve = resolveAll ||\n"
    "        sampleResolverRequired ||\n"
    "        (!direct && baseUri == null);\n"
    "    final url = shouldResolve\n"
    "        ? '$dynamicStreamPrefix${Uri.encodeComponent(dynamicId)}'\n"
    "        : _resolveStreamUrl(originalUrl, baseUri);\n",
)
replace_once(
    "lib/services/provider_json_catalog_parser.dart",
    "    final uriPath = Uri.parse(url).path.toLowerCase();\n",
    "    final uriPath = Uri.parse(originalUrl).path.toLowerCase();\n",
)
replace_once(
    "lib/services/provider_json_catalog_parser.dart",
    "      httpHeaders: headers.isEmpty ? null : Map.unmodifiable(headers),\n      drmKeyId: drm?.keyId,\n",
    "      httpHeaders: headers.isEmpty ? null : Map.unmodifiable(headers),\n"
    "      dynamicStreamId: shouldResolve ? dynamicId : null,\n"
    "      dynamicStreamPath: shouldResolve ? originalUrl : null,\n"
    "      providerGlobalIndex: globalIndex,\n"
    "      drmKeyId: drm?.keyId,\n",
)
replace_once(
    "lib/services/provider_json_catalog_parser.dart",
    "  String _resolveStreamUrl(String value, Uri? baseUri) {\n",
    "  String? _firstText(Map raw, List<String> keys) {\n"
    "    for (final key in keys) {\n"
    "      final value = raw[key]?.toString().trim();\n"
    "      if (value != null &&\n"
    "          value.isNotEmpty &&\n"
    "          value.toLowerCase() != 'null') {\n"
    "        return value;\n"
    "      }\n"
    "    }\n"
    "    return null;\n"
    "  }\n\n"
    "  String _resolveStreamUrl(String value, Uri? baseUri) {\n",
)

# Remote source no longer deletes most of the catalog. It never copies remote
# DRM key material; entries that need provider authorization are tagged for the
# just-in-time resolver.
replace_once(
    "lib/services/remote_provider_json_service.dart",
    "/// Esta ruta remota sólo importa streams HTTP/HTTPS directos y sin DRM. Las\n"
    "/// rutas relativas y las entradas protegidas se contabilizan pero se omiten;\n"
    "/// el soporte ClearKey local sigue disponible para catálogos autorizados que el\n"
    "/// usuario importe manualmente.\n",
    "/// La fuente remota conserva el catálogo completo. Las rutas relativas y las\n"
    "/// entradas protegidas se marcan para resolución justo antes de reproducir.\n"
    "/// El material DRM remoto no se propaga: un resolvedor autorizado debe\n"
    "/// devolver la URL/sesión reproducible. El ClearKey local sigue disponible.\n",
)
replace_once(
    "lib/services/remote_provider_json_service.dart",
    "          final url = sample['original_url'];\n"
    "          if (url is! String || !_absoluteHttpUrl(url.trim())) {\n"
    "            relativeUrlSamples++;\n"
    "            continue;\n"
    "          }\n\n"
    "          final drm = sample['drm_license_uri'];\n"
    "          if (drm is String && drm.trim().isNotEmpty) {\n"
    "            protectedSamples++;\n"
    "            continue;\n"
    "          }\n\n"
    "          // Nunca propagar material DRM por la fuente remota integrada.\n"
    "          sample.remove('drm_license_uri');\n"
    "          samples.add(sample);\n"
    "          usableSamples++;\n",
    "          final url = sample['original_url'];\n"
    "          if (url is! String || url.trim().isEmpty) continue;\n"
    "          final relative = !_absoluteHttpUrl(url.trim());\n"
    "          if (relative) relativeUrlSamples++;\n\n"
    "          final drm = sample['drm_license_uri'];\n"
    "          final protected = drm is String && drm.trim().isNotEmpty;\n"
    "          if (protected) protectedSamples++;\n\n"
    "          if (relative || protected) {\n"
    "            sample['resolver_required'] = true;\n"
    "          }\n"
    "          sample.remove('drm_license_uri');\n"
    "          samples.add(sample);\n"
    "          usableSamples++;\n",
)
replace_once(
    "lib/services/remote_provider_json_service.dart",
    "          'El catálogo remoto no contiene URLs HTTP/HTTPS directas y sin DRM utilizables.',\n",
    "          'El catálogo remoto no contiene canales utilizables.',\n",
)

# Generic resolver can now be used without Xtream credentials when provider.json
# is the catalog. It exposes the original path and global index as placeholders.
replace_once(
    "lib/services/dynamic_stream_service.dart",
    "  Future<List<Channel>> fetchCatalog() async {\n    final config = _requireConfig();\n\n",
    "  Future<List<Channel>> fetchCatalog() async {\n"
    "    final config = _requireConfig();\n"
    "    if (config.username.isEmpty || config.password.isEmpty) {\n"
    "      throw const DynamicStreamException(\n"
    "        'El catálogo Xtream dinámico requiere usuario y contraseña.',\n"
    "      );\n"
    "    }\n\n",
)
replace_once(
    "lib/services/dynamic_stream_service.dart",
    "      'group': channel.group ?? '',\n    };\n\n    final resolverUri = _resolverUri(config, id);\n",
    "      'group': channel.group ?? '',\n"
    "      'path': channel.dynamicStreamPath ?? '',\n"
    "      'globalIndex': channel.providerGlobalIndex ?? '',\n"
    "    };\n\n"
    "    final resolverUri = _resolverUri(config, vars);\n",
)
replace_once(
    "lib/services/dynamic_stream_service.dart",
    "  Uri _resolverUri(_DynamicSourceConfig config, String id) {\n"
    "    final path = config.resolverPath.replaceAll('{id}', Uri.encodeComponent(id));\n",
    "  Uri _resolverUri(_DynamicSourceConfig config, Map<String, String> vars) {\n"
    "    final path = _expand(config.resolverPath, vars);\n",
)
replace_once(
    "lib/services/dynamic_stream_service.dart",
    "    final username = map['username']?.toString().trim() ?? '';\n"
    "    final password = map['password']?.toString().trim() ?? '';\n"
    "    if (username.isEmpty || password.isEmpty) {\n"
    "      throw const FormatException('Faltan usuario o contraseña Xtream.');\n"
    "    }\n\n",
    "    final username = map['username']?.toString().trim() ?? '';\n"
    "    final password = map['password']?.toString().trim() ?? '';\n\n",
)

# Media3 resolves provider channels immediately before prepare(). Reconnects and
# channel changes naturally resolve again because they re-enter _prepareCurrent.
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    "import '../services/device_performance_service.dart';\n",
    "import '../services/device_performance_service.dart';\n"
    "import '../services/dynamic_stream_service.dart';\n",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    "    final headers = Map<String, String>.from(_headers);\n"
    "    String? userAgent;\n"
    "    for (final key in headers.keys.toList()) {\n"
    "      if (key.toLowerCase() == 'user-agent') {\n"
    "        userAgent = headers.remove(key);\n"
    "        break;\n"
    "      }\n"
    "    }\n\n"
    "    try {\n"
    "      await _player.invokeMethod<void>('prepare', {\n"
    "        'url': _channel.url,\n",
    "    var playbackUrl = _channel.url;\n"
    "    final headers = Map<String, String>.from(_headers);\n\n"
    "    try {\n"
    "      final dynamicId = _channel.dynamicStreamId?.trim();\n"
    "      if (dynamicId != null && dynamicId.isNotEmpty) {\n"
    "        final resolved = await DynamicStreamService.instance.resolve(_channel);\n"
    "        if (!mounted || generation != _openGeneration) return;\n"
    "        playbackUrl = resolved.url;\n"
    "        headers.addAll(resolved.headers);\n"
    "      }\n\n"
    "      String? userAgent;\n"
    "      for (final key in headers.keys.toList()) {\n"
    "        if (key.toLowerCase() == 'user-agent') {\n"
    "          userAgent = headers.remove(key);\n"
    "          break;\n"
    "        }\n"
    "      }\n\n"
    "      await _player.invokeMethod<void>('prepare', {\n"
    "        'url': playbackUrl,\n",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    "    } on FormatException catch (error) {\n",
    "    } on DynamicStreamException catch (error) {\n"
    "      if (!mounted || generation != _openGeneration) return;\n"
    "      _finishWithError('No se pudo abrir el canal', error.message);\n"
    "    } on FormatException catch (error) {\n",
)

replace_once(
    "lib/services/section_catalog_service.dart",
    "      bytes += _stringBytes(channel.tvgId);\n",
    "      bytes += _stringBytes(channel.tvgId);\n"
    "      bytes += _stringBytes(channel.dynamicStreamId);\n"
    "      bytes += _stringBytes(channel.dynamicStreamPath);\n"
    "      bytes += _stringBytes(channel.providerGlobalIndex);\n",
)

# Build reads an authorized resolver config from a GitHub secret when present.
# No credentials or session tokens are committed to the repository.
replace_once(
    ".github/workflows/build-provider-json.yml",
    "      - name: Build signed ARM32 and ARM64 APKs\n"
    "        shell: bash\n"
    "        run: |\n"
    "          set -euo pipefail\n"
    "          flutter build apk --release --split-per-abi \\\n",
    "      - name: Build signed ARM32 and ARM64 APKs\n"
    "        shell: bash\n"
    "        env:\n"
    "          TV_FULL_DYNAMIC_SOURCE_JSON: ${{ secrets.TV_FULL_DYNAMIC_SOURCE_JSON }}\n"
    "        run: |\n"
    "          set -euo pipefail\n"
    "          dynamic_args=()\n"
    "          if [[ -n \"${TV_FULL_DYNAMIC_SOURCE_JSON:-}\" ]]; then\n"
    "            dynamic_args+=(--dart-define=TV_FULL_DYNAMIC_SOURCE_JSON=\"$TV_FULL_DYNAMIC_SOURCE_JSON\")\n"
    "          fi\n"
    "          flutter build apk --release --split-per-abi \\\n",
)
replace_once(
    ".github/workflows/build-provider-json.yml",
    "            --build-number=\"$BUILD_NUMBER\" \\\n"
    "            --dart-define=TV_FULL_ANDROID_TV=true\n",
    "            --build-number=\"$BUILD_NUMBER\" \\\n"
    "            --dart-define=TV_FULL_ANDROID_TV=true \\\n"
    "            \"${dynamic_args[@]}\"\n",
)
replace_once(
    ".github/workflows/build-provider-json.yml",
    "          La fuente remota integrada sólo importa URLs HTTP/HTTPS directas sin DRM; rutas relativas o protegidas se omiten.\n",
    "          La fuente provider.json conserva el catálogo completo: rutas relativas/protegidas usan el resolvedor autorizado justo al reproducir; streams directos siguen directos.\n",
)

# Synthetic regression tests. No real provider credentials, tokens or DRM keys.
Path("test/remote_provider_json_service_test.dart").write_text(
    r'''import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/services/remote_provider_json_service.dart';

void main() {
  test('la fuente remota conserva directos y marca los que requieren resolver', () async {
    final body = jsonEncode({
      'summary': {'categories': 1, 'streams': 3},
      'categories': [
        {
          'name': 'Prueba',
          'samples': [
            {
              'name': 'Directo',
              'type': 'HLS',
              'original_url': 'https://example.test/live/directo.m3u8',
            },
            {
              'name': 'Relativo',
              'type': 'DASH',
              'original_url': 'live/relativo/manifest.mpd',
              'globalIndex': 22,
            },
            {
              'name': 'Protegido',
              'type': 'DASH',
              'original_url': 'https://example.test/live/protegido.mpd',
              'drm_license_uri': 'synthetic-test-marker',
              'globalIndex': 23,
            },
          ],
        },
      ],
    });

    final client = MockClient((request) async => http.Response(body, 200));
    final payload = await RemoteProviderJsonService.instance.fetch(client: client);

    expect(payload.sourceSamples, 3);
    expect(payload.usableSamples, 3);
    expect(payload.relativeUrlSamples, 1);
    expect(payload.protectedSamples, 1);

    final normalized = jsonDecode(payload.content) as Map<String, dynamic>;
    final category = (normalized['categories'] as List).single as Map<String, dynamic>;
    final samples = category['samples'] as List<dynamic>;
    expect(samples, hasLength(3));
    expect((samples[0] as Map)['resolver_required'], isNull);
    expect((samples[1] as Map)['resolver_required'], isTrue);
    expect((samples[2] as Map)['resolver_required'], isTrue);
    expect((samples[2] as Map).containsKey('drm_license_uri'), isFalse);
  });
}
'''
)

Path("test/provider_json_dynamic_resolver_test.dart").write_text(
    r'''import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/services/dynamic_stream_service.dart';
import 'package:iptv_player/services/provider_json_catalog_parser.dart';

void main() {
  test('provider.json conserva una ruta relativa como canal dinámico', () {
    final result = const ProviderJsonCatalogParser().parse(jsonEncode({
      'categories': [
        {
          'name': 'Deportes',
          'samples': [
            {
              'name': 'Canal demo',
              'type': 'DASH',
              'original_url': 'live/demo/manifest.mpd',
              'globalIndex': 42,
              'resolver_required': true,
            }
          ],
        }
      ],
    }));

    final channel = result.channels.single;
    expect(channel.dynamicStreamId, '42');
    expect(channel.dynamicStreamPath, 'live/demo/manifest.mpd');
    expect(channel.providerGlobalIndex, '42');
    expect(channel.streamMimeType, 'application/dash+xml');
    expect(channel.url, startsWith(DynamicStreamService.streamPrefix));

    final restored = Channel.fromJson(channel.toJson());
    expect(restored.dynamicStreamId, '42');
    expect(restored.dynamicStreamPath, 'live/demo/manifest.mpd');
    expect(restored.providerGlobalIndex, '42');
  });

  test('resolver-only usa id, path, globalIndex y Android ID al abrir', () async {
    const config = r'''
{
  "name": "Proveedor JSON",
  "server": "https://resolver.example",
  "resolver": {
    "path": "/resolve/{id}",
    "method": "POST",
    "form": {
      "id": "{id}",
      "path": "{path}",
      "index": "{globalIndex}",
      "device": "{androidId}"
    }
  },
  "playbackHeaders": {
    "X-Device": "{androidId}",
    "User-Agent": "TV FULL PRO provider test"
  }
}
''';

    final client = MockClient((request) async {
      expect(request.url.path, '/resolve/42');
      expect(request.bodyFields['id'], '42');
      expect(request.bodyFields['path'], 'live/demo/manifest.mpd');
      expect(request.bodyFields['index'], '42');
      expect(request.bodyFields['device'], 'device-demo');
      return http.Response('https://cdn.example/live/demo.mpd', 200);
    });

    final service = DynamicStreamService.forTesting(
      configJson: config,
      client: client,
      androidIdProvider: () async => 'device-demo',
    );

    const channel = Channel(
      name: 'Canal demo',
      url: 'tvfull-dynamic://stream/42',
      dynamicStreamId: '42',
      dynamicStreamPath: 'live/demo/manifest.mpd',
      providerGlobalIndex: '42',
    );
    final resolved = await service.resolve(channel);
    expect(resolved.url, 'https://cdn.example/live/demo.mpd');
    expect(resolved.headers['X-Device'], 'device-demo');
  });
}
'''
)
