import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/iptv_provider.dart';
import '../models/playlist.dart';
import 'channel_list_screen.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Carga inicial de listas y favoritos guardados en disco.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IptvProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('IPTV Player'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Listas', icon: Icon(Icons.playlist_play)),
            Tab(text: 'Favoritos', icon: Icon(Icons.favorite)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PlaylistsTab(playlists: provider.playlists, loading: provider.loading),
          _FavoritesTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddPlaylistDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Agregar lista'),
      ),
    );
  }

  void _showAddPlaylistDialog(BuildContext context) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Agregar lista M3U'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nombre de la lista'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlController,
              decoration:
                  const InputDecoration(labelText: 'URL (http://.../lista.m3u)'),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final url = urlController.text.trim();
              if (url.isEmpty) return;
              Navigator.pop(dialogContext);
              await context
                  .read<IptvProvider>()
                  .addPlaylistFromUrl(nameController.text, url);
              final error = context.read<IptvProvider>().error;
              if (error != null && context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(error)));
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  final List<Playlist> playlists;
  final bool loading;

  const _PlaylistsTab({required this.playlists, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    if (playlists.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Todavía no agregaste ninguna lista.\nUsá el botón "+" para cargar tu primera lista M3U.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return ListTile(
          leading: const Icon(Icons.list_alt),
          title: Text(playlist.name),
          subtitle: Text('${playlist.channels.length} canales'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () =>
                context.read<IptvProvider>().removePlaylist(playlist.id),
          ),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChannelListScreen(playlist: playlist),
          )),
        );
      },
    );
  }
}

class _FavoritesTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<IptvProvider>().favorites;

    if (favorites.isEmpty) {
      return const Center(
        child: Text('Marcá canales con el corazón para verlos acá.'),
      );
    }

    return ListView.builder(
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final channel = favorites[index];
        return ListTile(
          leading: const Icon(Icons.favorite, color: Colors.redAccent),
          title: Text(channel.name),
          subtitle: channel.group != null ? Text(channel.group!) : null,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PlayerScreen(
              channel: channel,
              playlist: favorites,
              initialIndex: index,
            ),
          )),
        );
      },
    );
  }
}
