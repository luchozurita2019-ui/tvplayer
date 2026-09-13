from pathlib import Path
import json


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'{label} marker not found')
    return text.replace(old, new, 1)


def patch_provider() -> None:
    path = Path('lib/providers/iptv_provider.dart')
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        "import '../services/m3u_parser.dart';",
        "import '../services/json_catalog_service.dart';\nimport '../services/m3u_parser.dart';",
        'provider import',
    )
    text = replace_once(
        text,
        "  static const _classicPlaylistSource =\n      'asset://assets/playlists/lista_clasica.m3u';",
        "  static const _classicPlaylistSource =\n      'asset://assets/playlists/lista_clasica.m3u';\n"
        "  static const _jsonPlaylistId = 'tvf_builtin_dynamic_classic_2';\n"
        "  static const _jsonPlaylistName = 'TV clásica 2';\n"
        "  static const _jsonPlaylistSource = JsonCatalogService.bundledSource;",
        'provider constants',
    )
    text = replace_once(
        text,
        "    await _ensureClassicPlaylist();\n    _normalizeSelection();",
        "    await _ensureClassicPlaylist();\n    await _ensureJsonPlaylist();\n    _normalizeSelection();",
        'provider init',
    )
    marker = "\n  Playlist? playlistById(String playlistId) {"
    method = '''

  Future<void> _ensureJsonPlaylist() async {
    final index = _playlists.indexWhere((item) => item.id == _jsonPlaylistId);
    final playlist = Playlist(
      id: _jsonPlaylistId,
      name: _jsonPlaylistName,
      source: _jsonPlaylistSource,
      isRemote: false,
      channels: const <Channel>[],
      lastUpdated: DateTime.now(),
      sourceType: PlaylistSourceType.m3u,
    );
    if (index < 0) {
      _playlists = [..._playlists, playlist];
      await _localStore.saveServices(_playlists);
      return;
    }
    final current = _playlists[index];
    if (current.name == playlist.name && current.source == playlist.source) return;
    final next = List<Playlist>.from(_playlists);
    next[index] = playlist.copyWith(lastUpdated: current.lastUpdated);
    _playlists = next;
    await _localStore.clearServiceCatalogs(_jsonPlaylistId);
    await _localStore.saveServices(_playlists);
  }
'''
    text = replace_once(text, marker, method + marker, 'provider method')
    path.write_text(text, encoding='utf-8')


def patch_section_service() -> None:
    path = Path('lib/services/section_catalog_service.dart')
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        "import 'device_performance_service.dart';",
        "import 'device_performance_service.dart';\nimport 'json_catalog_service.dart';",
        'section import',
    )
    needle = "  Future<void> _downloadAndPartitionToDisk(Playlist playlist) async {\n"
    replacement = needle + (
        "    if (JsonCatalogService.instance.handlesSource(playlist.source)) {\n"
        "      await _downloadJsonAndPartitionToDisk(playlist);\n"
        "      return;\n"
        "    }\n\n"
    )
    text = replace_once(text, needle, replacement, 'section entry')
    marker = "\n  void _remember(String key, SectionCatalogSnapshot snapshot) {"
    method = '''

  Future<void> _downloadJsonAndPartitionToDisk(Playlist playlist) async {
    final channels = await JsonCatalogService.instance.fetchCatalog(playlist.source);
    final writers = <TvSectionKind, CatalogFileWriter>{};
    final categorySets = <TvSectionKind, Set<String>>{
      for (final kind in TvSectionKind.values) kind: <String>{},
    };
    final categories = <TvSectionKind, List<String>>{
      for (final kind in TvSectionKind.values) kind: <String>[],
    };
    for (final kind in TvSectionKind.values) {
      writers[kind] = await _catalogFiles.beginSnapshot(
        serviceId: playlist.id,
        kind: 'm3u_${kind.name}',
      );
    }
    try {
      for (final channel in channels) {
        final kind = _classify(channel);
        writers[kind]!.add(channel.toJson());
        final group = channel.group?.trim();
        if (group != null && group.isNotEmpty && categorySets[kind]!.add(group)) {
          categories[kind]!.add(group);
        }
      }
      for (final kind in TvSectionKind.values) {
        final writer = writers[kind]!;
        if (writer.count == 0) {
          await writer.abort();
          continue;
        }
        final committed = await writer.commit(categories: categories[kind]!);
        if (committed) _forget('${playlist.id}|m3u_${kind.name}');
      }
      _lastNetworkRefresh['${playlist.id}|${playlist.source}'] = DateTime.now();
    } catch (_) {
      for (final writer in writers.values) {
        await writer.abort();
      }
      rethrow;
    }
  }
'''
    text = replace_once(text, marker, method + marker, 'section method')
    path.write_text(text, encoding='utf-8')


def ensure_test_asset() -> None:
    asset = Path('assets/playlists/tv_clasica_2.json')
    if asset.exists():
        return
    payload = {
        'summary': {'categories': 1, 'streams': 1},
        'categories': [{
            'name': 'Prueba JSON',
            'samples': [{
                'name': 'HLS de prueba',
                'type': 'HLS',
                'original_url': 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
            }],
        }],
    }
    asset.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    ensure_test_asset()
    patch_provider()
    patch_section_service()
