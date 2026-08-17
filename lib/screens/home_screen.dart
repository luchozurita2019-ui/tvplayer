import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/playback_settings.dart';
import '../models/playlist.dart';
import '../providers/iptv_provider.dart';
import 'channel_list_screen.dart';
import 'playback_settings_screen.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _section = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IptvProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 820;
        final extendedRail = constraints.maxWidth >= 1120;

        return Scaffold(
          appBar: AppBar(
            titleSpacing: desktop ? 20 : null,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.live_tv),
                const SizedBox(width: 10),
                Text(
                  'TV FULL · $_sectionTitle',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            actions: [
              if (_section != 2)
                IconButton(
                  tooltip: 'Rendimiento',
                  icon: const Icon(Icons.tune),
                  onPressed: () => _openPlaybackSettings(context),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: desktop
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _section,
                      extended: extendedRail,
                      minExtendedWidth: 190,
                      labelType: extendedRail
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      onDestinationSelected: (index) {
                        setState(() => _section = index);
                      },
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.video_library_outlined),
                          selectedIcon: Icon(Icons.video_library),
                          label: Text('Listas'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.favorite_border),
                          selectedIcon: Icon(Icons.favorite),
                          label: Text('Favoritos'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.speed_outlined),
                          selectedIcon: Icon(Icons.speed),
                          label: Text('Rendimiento'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _sectionBody(provider),
                    ),
                  ],
                )
              : _sectionBody(provider),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: _section,
                  onDestinationSelected: (index) {
                    setState(() => _section = index);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.video_library_outlined),
                      selectedIcon: Icon(Icons.video_library),
                      label: 'Listas',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.favorite_border),
                      selectedIcon: Icon(Icons.favorite),
                      label: 'Favoritos',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.speed_outlined),
                      selectedIcon: Icon(Icons.speed),
                      label: 'Rendimiento',
                    ),
                  ],
                ),
          floatingActionButton: _section == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _showAddPlaylistDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar lista'),
                )
              : null,
        );
      },
    );
  }

  String get _sectionTitle => switch (_section) {
        0 => 'TVPlayer · Listas',
        1 => 'TVPlayer · Favoritos',
        _ => 'TVPlayer · Rendimiento',
      };

  Widget _sectionBody(IptvProvider provider) {
    return switch (_section) {
      0 => _PlaylistsView(
          playlists: provider.playlists,
          loading: provider.loading,
        ),
      1 => const _FavoritesView(),
      _ => _PerformanceView(
          settings: provider.playbackSettings,
          onOpenSettings: () => _openPlaybackSettings(context),
        ),
    };
  }

  void _openPlaybackSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlaybackSettingsScreen()),
    );
  }

  void _showAddPlaylistDialog(BuildContext context) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Agregar lista M3U'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la lista',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'URL de la lista M3U',
                  hintText: 'https://servidor/lista.m3u',
                  prefixIcon: Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final url = urlController.text.trim();
              final uri = Uri.tryParse(url);
              if (uri == null ||
                  !(uri.scheme == 'http' || uri.scheme == 'https') ||
                  uri.host.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ingresá una URL http/https válida.'),
                  ),
                );
                return;
              }

              Navigator.pop(dialogContext);
              await context.read<IptvProvider>().addPlaylistFromUrl(
                    nameController.text.trim(),
                    url,
                  );
              if (!context.mounted) return;
              final error = context.read<IptvProvider>().error;
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error)),
                );
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Agregar'),
          ),
        ],
      ),
    );
  }
}

class _PlaylistsView extends StatelessWidget {
  final List<Playlist> playlists;
  final bool loading;

  const _PlaylistsView({required this.playlists, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    if (playlists.isEmpty) {
      return const _EmptyState(
        icon: Icons.playlist_add,
        title: 'Todavía no hay listas',
        message: 'Agregá una lista M3U para comenzar a mirar televisión.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1400
            ? 4
            : constraints.maxWidth >= 980
                ? 3
                : constraints.maxWidth >= 620
                    ? 2
                    : 1;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 100),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: columns == 1 ? 3.2 : 2.1,
          ),
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            return _PlaylistCard(playlist: playlists[index]);
          },
        );
      },
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final Playlist playlist;

  const _PlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<IptvProvider>();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChannelListScreen(playlist: playlist),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.live_tv,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text('${playlist.channels.length} canales'),
                    if (playlist.groups.isNotEmpty)
                      Text(
                        '${playlist.groups.length} categorías',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opciones',
                onSelected: (value) {
                  if (value == 'delete') {
                    provider.removePlaylist(playlist.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline),
                        SizedBox(width: 10),
                        Text('Eliminar lista'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoritesView extends StatelessWidget {
  const _FavoritesView();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final favorites = provider.favorites;

    if (favorites.isEmpty) {
      return const _EmptyState(
        icon: Icons.favorite_border,
        title: 'Sin favoritos',
        message: 'Marcá tus canales preferidos para encontrarlos acá.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(22),
      itemCount: favorites.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final channel = favorites[index];
        return Card(
          child: ListTile(
            leading: _ChannelLogo(channel: channel),
            title: Text(channel.name),
            subtitle: channel.group == null ? null : Text(channel.group!),
            trailing: const Icon(Icons.play_arrow),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  channel: channel,
                  playlist: favorites,
                  initialIndex: index,
                  settings: provider.playbackSettings,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PerformanceView extends StatelessWidget {
  final PlaybackSettings settings;
  final VoidCallback onOpenSettings;

  const _PerformanceView({
    required this.settings,
    required this.onOpenSettings,
  });

  String get _profileLabel => switch (settings.profile) {
        BufferProfile.auto => 'Automático',
        BufferProfile.ultraFast => 'Ultra rápido',
        BufferProfile.balanced => 'Equilibrado',
        BufferProfile.stable => 'Estable',
        BufferProfile.custom => 'Personalizado',
      };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed, size: 34),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Motor de reproducción',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text('Perfil actual: $_profileLabel'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricChip(
                      label: 'Buffer',
                      value: '${settings.bufferMb} MB',
                    ),
                    _MetricChip(
                      label: 'Lectura anticipada',
                      value: '${settings.readaheadSeconds.toStringAsFixed(1)} s',
                    ),
                    _MetricChip(
                      label: 'Recuperación',
                      value:
                          '${settings.recoveryBufferSeconds.toStringAsFixed(1)} s',
                    ),
                    _MetricChip(
                      label: 'Reintentos',
                      value: '${settings.maxRetries}',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune),
                  label: const Text('Configurar rendimiento'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text('$label · $value'),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  final Channel channel;

  const _ChannelLogo({required this.channel});

  @override
  Widget build(BuildContext context) {
    final logo = channel.logoUrl;
    if (logo == null || logo.isEmpty) {
      return const CircleAvatar(child: Icon(Icons.tv));
    }

    return CircleAvatar(
      backgroundColor: Colors.transparent,
      child: ClipOval(
        child: Image.network(
          logo,
          width: 40,
          height: 40,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.tv),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
