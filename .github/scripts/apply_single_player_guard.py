from pathlib import Path

path = Path("lib/screens/channel_list_screen.dart")
text = path.read_text(encoding="utf-8")

field_old = """  double _sidebarWidth = 320;\n  bool _sidebarCollapsed = false;\n"""
field_new = """  double _sidebarWidth = 320;\n  bool _sidebarCollapsed = false;\n  bool _openingPlayer = false;\n"""

if "bool _openingPlayer = false;" not in text:
    if text.count(field_old) != 1:
        raise SystemExit("No se encontro de forma unica el punto para agregar _openingPlayer")
    text = text.replace(field_old, field_new, 1)

old = """  Future<void> _openChannel(\n    BuildContext context,\n    List<Channel> channels,\n    Channel channel,\n    IptvProvider provider,\n  ) async {\n    final index = channels.indexOf(channel);\n    if (index < 0) return;\n\n    ArtworkCacheService.instance.pauseForPlayback();\n    await Navigator.of(context).push(\n      MaterialPageRoute(\n        builder: (_) => PlayerScreen(\n          channel: channel,\n          playlist: channels,\n          initialIndex: index,\n          settings: provider.playbackSettings,\n          isLiveContent:\n              _mode == _CatalogMode.live || _mode == _CatalogMode.radios,\n        ),\n      ),\n    );\n    ArtworkCacheService.instance.resumeBrowsing();\n  }\n"""

new = """  Future<void> _openChannel(\n    BuildContext context,\n    List<Channel> channels,\n    Channel channel,\n    IptvProvider provider,\n  ) async {\n    // Evita que dos clics rapidos apilen dos rutas PlayerScreen. El bloqueo\n    // se activa antes del primer await, por lo que un segundo clic en el\n    // mismo frame/event loop se descarta mientras el reproductor esta abierto.\n    if (_openingPlayer) return;\n\n    final index = channels.indexOf(channel);\n    if (index < 0) return;\n\n    _openingPlayer = true;\n    ArtworkCacheService.instance.pauseForPlayback();\n    try {\n      await Navigator.of(context).push(\n        MaterialPageRoute(\n          builder: (_) => PlayerScreen(\n            channel: channel,\n            playlist: channels,\n            initialIndex: index,\n            settings: provider.playbackSettings,\n            isLiveContent:\n                _mode == _CatalogMode.live || _mode == _CatalogMode.radios,\n          ),\n        ),\n      );\n    } finally {\n      _openingPlayer = false;\n      ArtworkCacheService.instance.resumeBrowsing();\n    }\n  }\n"""

if "if (_openingPlayer) return;" not in text:
    if text.count(old) != 1:
        raise SystemExit("No se encontro de forma unica _openChannel esperado")
    text = text.replace(old, new, 1)

if text.count("if (_openingPlayer) return;") != 1:
    raise SystemExit("Guard de reproductor duplicado o ausente")
if text.count("bool _openingPlayer = false;") != 1:
    raise SystemExit("Estado _openingPlayer duplicado o ausente")

path.write_text(text, encoding="utf-8")
print("Single-player route guard aplicado correctamente")
