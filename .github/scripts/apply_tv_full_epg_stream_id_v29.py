from pathlib import Path


def replace_once(path: str, old: str, new: str):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected 1 occurrence, found {count}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')

# Preserve the actual Xtream stream_id on Channel. This is optional and fully
# backward-compatible with M3U/local channels and old persisted JSON.
replace_once(
    'lib/models/channel.dart',
    '  final String? tvgId; // id para cruzar con EPG en el futuro\n',
    "  final String? tvgId; // id XMLTV/EPG del proveedor\n  final String? xtreamStreamId; // stream_id real para APIs Xtream (EPG, etc.)\n",
)
replace_once(
    'lib/models/channel.dart',
    '    this.tvgId,\n    this.httpUserAgent,',
    '    this.tvgId,\n    this.xtreamStreamId,\n    this.httpUserAgent,',
)
replace_once(
    'lib/models/channel.dart',
    "        'tvgId': tvgId,\n        'httpUserAgent': httpUserAgent,",
    "        'tvgId': tvgId,\n        'xtreamStreamId': xtreamStreamId,\n        'httpUserAgent': httpUserAgent,",
)
replace_once(
    'lib/models/channel.dart',
    "      tvgId: json['tvgId'] as String?,\n      httpUserAgent: json['httpUserAgent'] as String?,",
    "      tvgId: json['tvgId'] as String?,\n      xtreamStreamId: json['xtreamStreamId'] as String?,\n      httpUserAgent: json['httpUserAgent'] as String?,",
)

# The fast LIVE cache must be rebuilt once because v3 did not persist stream_id.
replace_once(
    'lib/services/xtream_live_fast_service.dart',
    '  static const int _cacheVersion = 3;',
    '  static const int _cacheVersion = 4;',
)
replace_once(
    'lib/services/xtream_live_fast_service.dart',
    "            tvgId: _cleanText(item['tvgId']),\n          ),",
    "            tvgId: _cleanText(item['tvgId']),\n            xtreamStreamId: _cleanText(item['xtreamStreamId']),\n          ),",
)
replace_once(
    'lib/services/xtream_live_fast_service.dart',
    "          'tvgId': _firstText(item, const <String>[\n            'epg_channel_id',\n            'tvg_id',\n          ]),\n        }),",
    "          'tvgId': _firstText(item, const <String>[\n            'epg_channel_id',\n            'tvg_id',\n          ]),\n          'xtreamStreamId': id,\n        }),",
)

# Also preserve it on the native Xtream fallback path.
replace_once(
    'lib/services/xtream_service.dart',
    "          tvgId: epgId == null || epgId.isEmpty ? null : epgId,\n        ),",
    "          tvgId: epgId == null || epgId.isEmpty ? null : epgId,\n          xtreamStreamId: streamId,\n        ),",
)

# EPG must prefer the persisted stream_id, only falling back to URL parsing for
# old/legacy channels.
replace_once(
    'lib/services/live_epg_service.dart',
    "  String? _streamIdFromChannel(Channel channel) {\n    final uri = Uri.tryParse(channel.url.trim());",
    "  String? _streamIdFromChannel(Channel channel) {\n    final stored = channel.xtreamStreamId?.trim() ?? '';\n    if (RegExp(r'^\\d+$').hasMatch(stored)) return stored;\n\n    final uri = Uri.tryParse(channel.url.trim());",
)

# Version the bugfix separately from the v28 UI release.
replace_once(
    'pubspec.yaml',
    'version: 1.3.6+28',
    'version: 1.3.7+29',
)
pubspec = Path('pubspec.yaml')
text = pubspec.read_text(encoding='utf-8')
marker = '# TV FULL PRO 1.3.7+29 xtream-epg-stream-id-v29\n'
if marker not in text:
    text = text.rstrip() + '\n\n' + marker
    pubspec.write_text(text, encoding='utf-8')

# Regression test for persistence/backward compatibility.
test = Path('test/channel_xtream_stream_id_test.dart')
test.write_text("""import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/channel.dart';

void main() {
  test('Channel conserva xtreamStreamId al serializar', () {
    const channel = Channel(
      name: 'Canal prueba',
      url: 'https://cdn.example.test/direct/live-token',
      tvgId: 'guide.channel',
      xtreamStreamId: '12345',
    );

    final restored = Channel.fromJson(channel.toJson());
    expect(restored.xtreamStreamId, '12345');
    expect(restored.tvgId, 'guide.channel');
    expect(restored.url, channel.url);
  });

  test('JSON antiguo sin xtreamStreamId sigue siendo compatible', () {
    final restored = Channel.fromJson(<String, dynamic>{
      'name': 'Canal viejo',
      'url': 'https://example.test/live/u/p/77.ts',
      'logoUrl': null,
      'group': 'TV',
      'tvgId': null,
      'httpUserAgent': null,
      'httpReferrer': null,
    });

    expect(restored.xtreamStreamId, isNull);
    expect(restored.name, 'Canal viejo');
  });
}
""", encoding='utf-8')

print('Applied TV FULL PRO 1.3.7+29 Xtream stream_id EPG fix')
