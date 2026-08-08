import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../services/content_classifier.dart';
import 'channel_list_screen.dart';

class SourceContentScreen extends StatelessWidget {
  final Playlist playlist;

  const SourceContentScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    final counts = ContentClassifier.counts(playlist.channels);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TV FULL',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final columns = constraints.maxWidth >= 1250
              ? 4
              : constraints.maxWidth >= 760
                  ? 2
                  : 1;

          return ListView(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 48 : 18,
              vertical: wide ? 34 : 20,
            ),
            children: [
              Text(
                '¿Qué querés ver?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Contenido organizado automáticamente por TV FULL.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white70,
                    ),
              ),
              const SizedBox(height: 28),
              GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
                childAspectRatio: columns == 1 ? 3.3 : 1.35,
                children: [
                  _ContentCard(
                    icon: Icons.live_tv_rounded,
                    title: 'TV en vivo',
                    count: counts[IptvContentKind.live] ?? 0,
                    accent: const Color(0xFF1677FF),
                    onTap: () => _openKind(context, IptvContentKind.live),
                  ),
                  _ContentCard(
                    icon: Icons.movie_creation_rounded,
                    title: 'Películas',
                    count: counts[IptvContentKind.movies] ?? 0,
                    accent: const Color(0xFF4C9DFF),
                    onTap: () => _openKind(context, IptvContentKind.movies),
                  ),
                  _ContentCard(
                    icon: Icons.video_library_rounded,
                    title: 'Series',
                    count: counts[IptvContentKind.series] ?? 0,
                    accent: const Color(0xFF2D6DFF),
                    onTap: () => _openKind(context, IptvContentKind.series),
                  ),
                  _ContentCard(
                    icon: Icons.radio_rounded,
                    title: 'Radios',
                    count: counts[IptvContentKind.radios] ?? 0,
                    accent: const Color(0xFF5DB7FF),
                    onTap: () => _openKind(context, IptvContentKind.radios),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'TV FULL separa el contenido usando la estructura del proveedor y, en listas M3U, categorías y rutas del stream. Podés seguir entrando a cada categoría normalmente.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openKind(BuildContext context, IptvContentKind kind) {
    final channels = ContentClassifier.filter(playlist.channels, kind);
    if (channels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No hay ${kind.label.toLowerCase()} en esta lista.')),
      );
      return;
    }

    // ID distinto para que ChannelListScreen no reemplace esta vista filtrada
    // por la lista completa que vive en el Provider.
    final filtered = Playlist(
      id: '${playlist.id}::${kind.name}',
      name: '${playlist.name} · ${kind.label}',
      source: playlist.source,
      isRemote: false,
      channels: channels,
      lastUpdated: playlist.lastUpdated,
      sourceType: playlist.sourceType,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChannelListScreen(playlist: filtered),
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final Color accent;
  final VoidCallback onTap;

  const _ContentCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: enabled ? 0.24 : 0.08),
                Theme.of(context).colorScheme.surfaceContainerHigh,
              ],
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 58,
                color: enabled ? Colors.white : Colors.white30,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: enabled ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                count == 1 ? '1 elemento' : '$count elementos',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: enabled ? Colors.white70 : Colors.white30,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
