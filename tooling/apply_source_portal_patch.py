from pathlib import Path
import re

path = Path('lib/screens/home_screen.dart')
s = path.read_text()

s = s.replace(
    "import '../models/playlist.dart';\n",
    "import '../models/playlist.dart';\nimport '../models/playlist_source_type.dart';\n",
    1,
)
s = s.replace(
    "import 'channel_list_screen.dart';\n",
    "import 'add_source_screen.dart';\nimport 'source_content_screen.dart';\n",
    1,
)

s = s.replace(
    "onPressed: () => _showAddPlaylistDialog(context),",
    "onPressed: () => Navigator.of(context).push(\n                    MaterialPageRoute(builder: (_) => const AddSourceScreen()),\n                  ),",
    1,
)

s = s.replace("0 => 'TVPlayer · Listas',", "0 => 'Servicios',", 1)
s = s.replace("1 => 'TVPlayer · Favoritos',", "1 => 'Favoritos',", 1)
s = s.replace("_ => 'TVPlayer · Rendimiento',", "_ => 'Rendimiento',", 1)

start = s.find('  void _showAddPlaylistDialog(BuildContext context) {')
end = s.find('\n}\n\nclass _PlaylistsView', start)
if start == -1 or end == -1:
    raise SystemExit('No se encontró el diálogo M3U antiguo')
s = s[:start] + s[end:]

s = s.replace(
    "message: 'Agregá una lista M3U para comenzar a mirar televisión.',",
    "message: 'Agregá un servicio M3U/M3U8, Xtream Codes o Portal Stalker para comenzar.',",
    1,
)

old_tap = """        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChannelListScreen(playlist: playlist),
          ),
        ),"""
new_tap = """        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SourceContentScreen(playlist: playlist),
          ),
        ),"""
if old_tap not in s:
    raise SystemExit('No se encontró navegación de playlist')
s = s.replace(old_tap, new_tap, 1)

old_meta = """                    const SizedBox(height: 5),
                    Text('${playlist.channels.length} canales'),
                    if (playlist.groups.isNotEmpty)"""
new_meta = """                    const SizedBox(height: 5),
                    Text(
                      playlist.sourceType.label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text('${playlist.channels.length} elementos'),
                    if (playlist.groups.isNotEmpty)"""
if old_meta not in s:
    raise SystemExit('No se encontró metadata de tarjeta')
s = s.replace(old_meta, new_meta, 1)

path.write_text(s)
