from __future__ import annotations

import json
import re
import unicodedata
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE_URL = "https://raw.githubusercontent.com/LUIS-F-SORIA/canales-tv.m3u/refs/heads/main/tv-online"
ASSET_DIR = ROOT / "assets" / "playlists"
M3U_ASSET = ASSET_DIR / "lista_clasica.m3u"
LOGO_INDEX_ASSET = ASSET_DIR / "lista_clasica_logo_index.json"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, value: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(value, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    value = read(path)
    count = value.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, got {count}: {old!r}")
    write(path, value.replace(old, new, 1))


def download_classic_playlist() -> str:
    request = urllib.request.Request(
        SOURCE_URL,
        headers={
            "User-Agent": "TV-FULL-PRO-build/1.3.4",
            "Accept": "text/plain,application/x-mpegURL,*/*",
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        raw = response.read()
    text = raw.decode("utf-8", errors="replace")
    extinf_count = text.count("#EXTINF:")
    if "#EXTM3U" not in text or extinf_count < 100:
        raise RuntimeError(
            f"Classic playlist validation failed: #EXTINF count={extinf_count}"
        )
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    M3U_ASSET.write_text(text, encoding="utf-8")
    return text


TECHNICAL_TOKENS = {
    "hd",
    "fhd",
    "fullhd",
    "uhd",
    "4k",
    "2160p",
    "1080p",
    "720p",
    "576p",
    "480p",
    "hevc",
    "h265",
    "h264",
    "av1",
    "sd",
    "vip",
    "backup",
    "test",
    "alt",
    "opc",
    "opcion",
}
ALIASES = {
    "televisionpublica": "tvpublica",
    "tvpublicaargentina": "tvpublica",
    "tycsport": "tycsports",
    "cronicahd": "cronicatv",
    "cronica": "cronicatv",
    "eltrecehd": "eltrece",
}


def normalize_name(raw: str) -> str:
    value = unicodedata.normalize("NFD", raw.lower())
    value = "".join(ch for ch in value if unicodedata.category(ch) != "Mn")
    tokens = re.sub(r"[^a-z0-9]+", " ", value).strip().split()
    if tokens and tokens[0] in {"ar", "arg"}:
        tokens.pop(0)
    if tokens and tokens[-1] in {"ar", "arg"}:
        tokens.pop()
    tokens = [token for token in tokens if token not in TECHNICAL_TOKENS]
    normalized = "".join(tokens)
    return ALIASES.get(normalized, normalized)


def build_logo_index(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    attr_re = re.compile(r'([A-Za-z0-9_-]+)="([^"]*)"')
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line.startswith("#EXTINF:"):
            continue
        attrs = {key.lower(): value.strip() for key, value in attr_re.findall(line)}
        logo = attrs.get("tvg-logo", "").strip()
        if not logo.startswith(("http://", "https://")):
            continue
        lower_logo = logo.lower()
        if ".svg" in lower_logo:
            continue

        names: list[str] = []
        tvg_name = attrs.get("tvg-name", "").strip()
        if tvg_name:
            names.append(tvg_name)
        if "," in line:
            display_name = line.split(",", 1)[1].strip()
            if display_name:
                names.append(display_name)
        for name in names:
            normalized = normalize_name(name)
            if len(normalized) >= 2:
                result.setdefault(f"name:{normalized}", logo)

        tvg_id = attrs.get("tvg-id", "").strip()
        if "@" in tvg_id:
            tvg_id = tvg_id.split("@", 1)[0].strip()
        if tvg_id:
            result.setdefault(f"id:{tvg_id.lower()}", logo)

    if len(result) < 50:
        raise RuntimeError(f"Logo index unexpectedly small: {len(result)} entries")
    LOGO_INDEX_ASSET.write_text(
        json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
        encoding="utf-8",
    )
    return result


def patch_pubspec() -> None:
    replace_once("pubspec.yaml", "version: 1.3.3+25", "version: 1.3.4+26")
    replace_once(
        "pubspec.yaml",
        "flutter:\n  uses-material-design: true\n",
        "flutter:\n  uses-material-design: true\n  assets:\n    - assets/playlists/\n",
    )
    value = read("pubspec.yaml")
    marker = "# TV FULL PRO 1.3.4+26 classic-asset-performance-v26"
    if marker not in value:
        write("pubspec.yaml", value.rstrip() + "\n\n" + marker + "\n")


def patch_fetcher() -> None:
    replace_once(
        "lib/services/m3u_fetcher.dart",
        "import 'package:http/http.dart' as http;\n",
        "import 'package:flutter/services.dart';\nimport 'package:http/http.dart' as http;\n",
    )
    replace_once(
        "lib/services/m3u_fetcher.dart",
        "  static http.Client _client = http.Client();\n  static int _generation = 0;\n",
        "  static const String _assetPrefix = 'asset://';\n\n"
        "  static http.Client _client = http.Client();\n"
        "  static int _generation = 0;\n\n"
        "  static String? _assetPath(String source) {\n"
        "    final clean = source.trim();\n"
        "    if (!clean.startsWith(_assetPrefix)) return null;\n"
        "    final path = clean.substring(_assetPrefix.length).trim();\n"
        "    return path.isEmpty ? null : path;\n"
        "  }\n",
    )
    replace_once(
        "lib/services/m3u_fetcher.dart",
        "  }) async {\n    final generation = _generation;\n",
        "  }) async {\n"
        "    final assetPath = _assetPath(url);\n"
        "    if (assetPath != null) {\n"
        "      return rootBundle.loadString(assetPath);\n"
        "    }\n\n"
        "    final generation = _generation;\n",
    )
    marker = "  static Stream<String> fetchLines(\n"
    value = read("lib/services/m3u_fetcher.dart")
    first = value.find(marker)
    if first < 0:
        raise RuntimeError("fetchLines marker not found")
    suffix = value[first:]
    old = "  }) async* {\n    final generation = _generation;\n"
    if old not in suffix:
        raise RuntimeError("fetchLines body marker not found")
    new = (
        "  }) async* {\n"
        "    final assetPath = _assetPath(url);\n"
        "    if (assetPath != null) {\n"
        "      final content = await rootBundle.loadString(assetPath);\n"
        "      for (final line in const LineSplitter().convert(content)) {\n"
        "        yield line;\n"
        "      }\n"
        "      return;\n"
        "    }\n\n"
        "    final generation = _generation;\n"
    )
    suffix = suffix.replace(old, new, 1)
    write("lib/services/m3u_fetcher.dart", value[:first] + suffix)


def patch_provider() -> None:
    replace_once(
        "lib/providers/iptv_provider.dart",
        "  static const _remotePlaylistPrefix = 'tvf_remote_';\n",
        "  static const _remotePlaylistPrefix = 'tvf_remote_';\n"
        "  static const _classicPlaylistId = 'tvf_builtin_classic';\n"
        "  static const _classicPlaylistName = 'Lista clásica';\n"
        "  static const _classicPlaylistSource =\n"
        "      'asset://assets/playlists/lista_clasica.m3u';\n",
    )
    replace_once(
        "lib/providers/iptv_provider.dart",
        "    _normalizeSelection();\n    _initialized = true;\n",
        "    await _ensureClassicPlaylist();\n"
        "    _normalizeSelection();\n"
        "    _initialized = true;\n",
    )
    insert_before = "  Playlist? playlistById(String playlistId) {\n"
    method = """  Future<void> _ensureClassicPlaylist() async {
    final index = _playlists.indexWhere((item) => item.id == _classicPlaylistId);
    final classic = Playlist(
      id: _classicPlaylistId,
      name: _classicPlaylistName,
      source: _classicPlaylistSource,
      isRemote: false,
      channels: const <Channel>[],
      lastUpdated: DateTime.now(),
      sourceType: PlaylistSourceType.m3u,
    );

    if (index < 0) {
      _playlists = [..._playlists, classic];
      await _localStore.saveServices(_playlists);
      return;
    }

    final current = _playlists[index];
    if (current.name == _classicPlaylistName &&
        current.source == _classicPlaylistSource &&
        current.sourceType == PlaylistSourceType.m3u) {
      return;
    }

    final next = List<Playlist>.from(_playlists);
    next[index] = classic.copyWith(lastUpdated: current.lastUpdated);
    _playlists = next;
    await _localStore.clearServiceCatalogs(_classicPlaylistId);
    await _localStore.saveServices(_playlists);
  }

"""
    replace_once(
        "lib/providers/iptv_provider.dart",
        insert_before,
        method + insert_before,
    )


def replace_logo_resolver() -> None:
    write(
        "lib/services/channel_logo_resolver_service.dart",
        """import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

/// Fallback de logos local y liviano.
///
/// A diferencia de v25, nunca recorre un catálogo remoto durante la navegación.
/// El índice se genera al compilar a partir de la Lista clásica empaquetada y se
/// carga una sola vez, sólo cuando realmente falta un logo del proveedor.
class ChannelLogoResolverService {
  ChannelLogoResolverService._();

  static final ChannelLogoResolverService instance =
      ChannelLogoResolverService._();

  static const String _indexAsset =
      'assets/playlists/lista_clasica_logo_index.json';

  static const Set<String> _technicalTokens = <String>{
    'hd',
    'fhd',
    'fullhd',
    'uhd',
    '4k',
    '2160p',
    '1080p',
    '720p',
    '576p',
    '480p',
    'hevc',
    'h265',
    'h264',
    'av1',
    'sd',
    'vip',
    'backup',
    'test',
    'alt',
    'opc',
    'opcion',
  };

  static const Map<String, String> _aliases = <String, String>{
    'televisionpublica': 'tvpublica',
    'tvpublicaargentina': 'tvpublica',
    'tycsport': 'tycsports',
    'cronicahd': 'cronicatv',
    'cronica': 'cronicatv',
    'eltrecehd': 'eltrece',
  };

  final Map<String, String> _values = <String, String>{};
  bool _loaded = false;
  Future<void>? _loadFuture;

  @visibleForTesting
  static String normalizeNameForLookup(String raw) {
    var value = raw.toLowerCase();
    const accents = <String, String>{
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'ã': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
      'ç': 'c',
    };
    for (final entry in accents.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }

    final tokens = value
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .split(RegExp(r'\\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: true);
    if (tokens.isNotEmpty && (tokens.first == 'ar' || tokens.first == 'arg')) {
      tokens.removeAt(0);
    }
    if (tokens.isNotEmpty && (tokens.last == 'ar' || tokens.last == 'arg')) {
      tokens.removeLast();
    }
    tokens.removeWhere(_technicalTokens.contains);
    final normalized = tokens.join();
    return _aliases[normalized] ?? normalized;
  }

  @visibleForTesting
  static Set<String> lookupKeysForChannel(Channel channel) {
    final keys = <String>{};
    var tvgId = channel.tvgId?.trim() ?? '';
    if (tvgId.contains('@')) tvgId = tvgId.split('@').first.trim();
    if (tvgId.isNotEmpty) keys.add('id:${tvgId.toLowerCase()}');
    final name = normalizeNameForLookup(channel.name);
    if (name.length >= 2) keys.add('name:$name');
    return keys;
  }

  /// v26: no se hace ningún trabajo de logos al entrar al catálogo.
  Future<void> primeChannels(Iterable<Channel> channels) async {}

  Future<String?> resolveFallback(
    Channel channel, {
    bool allowNetwork = true,
  }) async {
    await _ensureLoaded();
    for (final key in lookupKeysForChannel(channel)) {
      final value = _values[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final active = _loadFuture;
    if (active != null) {
      await active;
      return;
    }

    final future = _loadLocalIndex();
    _loadFuture = future;
    try {
      await future;
    } finally {
      if (identical(_loadFuture, future)) _loadFuture = null;
    }
  }

  Future<void> _loadLocalIndex() async {
    try {
      final raw = await rootBundle.loadString(_indexAsset);
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final key = entry.key.toString().trim();
          final value = entry.value?.toString().trim() ?? '';
          if (key.isNotEmpty && value.isNotEmpty) _values[key] = value;
        }
      }
    } catch (_) {
      // El fallback visual es opcional y nunca debe trabar TV FULL PRO.
    } finally {
      _loaded = true;
    }
  }
}
""",
    )


def add_test() -> None:
    write(
        "test/builtin_classic_playlist_test.dart",
        """import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/m3u_fetcher.dart';
import 'package:iptv_player/services/m3u_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Lista clásica se lee desde el asset y contiene canales válidos', () async {
    const source = 'asset://assets/playlists/lista_clasica.m3u';
    final parser = M3uLineParser();
    var channels = 0;
    await for (final line in M3uFetcher.fetchLines(source)) {
      if (parser.addLine(line) != null) channels++;
    }
    expect(channels, greaterThan(100));
  });
}
""",
    )


def main() -> None:
    text = download_classic_playlist()
    logos = build_logo_index(text)
    patch_pubspec()
    patch_fetcher()
    patch_provider()
    replace_logo_resolver()
    add_test()
    print(
        "Applied TV FULL PRO 1.3.4+26 classic asset performance patch: "
        f"{text.count('#EXTINF:')} EXTINF entries, {len(logos)} logo keys"
    )


if __name__ == "__main__":
    main()
