import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../providers/iptv_provider.dart';
import '../widgets/channel_tile.dart';
import 'player_screen.dart';

class ChannelListScreen extends StatefulWidget {
  final Playlist playlist;

  const ChannelListScreen({super.key, required this.playlist});

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  String? _selectedGroup;
  String _query = '';
  Channel? _focusedChannel;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final playlist = provider.playlistById(widget.playlist.id) ?? widget.playlist;
    final channels = _filteredChannels(playlist);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${channels.length} de ${playlist.channels.length} canales',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (playlist.isRemote)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar lista',
              onPressed: provider.loading
                  ? null
                  : () => context
                      .read<IptvProvider>()
                      .refreshPlaylist(playlist.id),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 920) {
            return _DesktopChannelLayout(
              playlist: playlist,
              channels: channels,
              selectedGroup: _selectedGroup,
              query: _query,
              focusedChannel: _effectiveFocused(channels),
              onGroupSelected: (group) {
                setState(() {
                  _selectedGroup = group;
                  _focusedChannel = null;
                });
              },
              onQueryChanged: (value) => setState(() => _query = value),
              onChannelFocused: (channel) {
                if (_focusedChannel == channel) return;
                setState(() => _focusedChannel = channel);
              },
              onPlayChannel: (channel) => _openChannel(
                context,
                channels,
                channel,
                provider,
              ),
              onFavoriteToggle: provider.toggleFavorite,
              isFavorite: provider.isFavorite,
            );
          }

          return _CompactChannelLayout(
            playlist: playlist,
            channels: channels,
            selectedGroup: _selectedGroup,
            query: _query,
            onGroupSelected: (group) => setState(() => _selectedGroup = group),
            onQueryChanged: (value) => setState(() => _query = value),
            onPlayChannel: (channel) => _openChannel(
              context,
              channels,
              channel,
              provider,
            ),
            onFavoriteToggle: provider.toggleFavorite,
            isFavorite: provider.isFavorite,
          );
        },
      ),
    );
  }

  List<Channel> _filteredChannels(Playlist playlist) {
    Iterable<Channel> result = playlist.channels;

    if (_selectedGroup != null) {
      result = result.where((channel) => channel.group == _selectedGroup);
    }

    final normalized = _query.trim().toLowerCase();
    if (normalized.isNotEmpty) {
      result = result.where((channel) {
        final name = channel.name.toLowerCase();
        final group = channel.group?.toLowerCase() ?? '';
        return name.contains(normalized) || group.contains(normalized);
      });
    }

    return result.toList(growable: false);
  }

  Channel? _effectiveFocused(List<Channel> channels) {
    final focused = _focusedChannel;
    if (focused != null && channels.contains(focused)) return focused;
    return channels.isEmpty ? null : channels.first;
  }

  void _openChannel(
    BuildContext context,
    List<Channel> channels,
    Channel channel,
    IptvProvider provider,
  ) {
    final index = channels.indexOf(channel);
    if (index < 0) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          channel: channel,
          playlist: channels,
          initialIndex: index,
          settings: provider.playbackSettings,
        ),
      ),
    );
  }
}

class _DesktopChannelLayout extends StatelessWidget {
  final Playlist playlist;
  final List<Channel> channels;
  final String? selectedGroup;
  final String query;
  final Channel? focusedChannel;
  final ValueChanged<String?> onGroupSelected;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Channel> onChannelFocused;
  final ValueChanged<Channel> onPlayChannel;
  final ValueChanged<Channel> onFavoriteToggle;
  final bool Function(Channel) isFavorite;

  const _DesktopChannelLayout({
    required this.playlist,
    required this.channels,
    required this.selectedGroup,
    required this.query,
    required this.focusedChannel,
    required this.onGroupSelected,
    required this.onQueryChanged,
    required this.onChannelFocused,
    required this.onPlayChannel,
    required this.onFavoriteToggle,
    required this.isFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 230,
          child: _CategorySidebar(
            playlist: playlist,
            selectedGroup: selectedGroup,
            onGroupSelected: onGroupSelected,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 5,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: TextFormField(
                  initialValue: query,
                  decoration: const InputDecoration(
                    hintText: 'Buscar canal o categoría…',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: onQueryChanged,
                ),
              ),
              Expanded(
                child: channels.isEmpty
                    ? const Center(child: Text('No se encontraron canales'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                        itemCount: channels.length,
                        itemBuilder: (context, index) {
                          final channel = channels[index];
                          return MouseRegion(
                            onEnter: (_) => onChannelFocused(channel),
                            child: ChannelTile(
                              channel: channel,
                              isFavorite: isFavorite(channel),
                              onFavoriteToggle: () =>
                                  onFavoriteToggle(channel),
                              onTap: () => onPlayChannel(channel),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        if (MediaQuery.sizeOf(context).width >= 1220) ...[
          const VerticalDivider(width: 1),
          SizedBox(
            width: 310,
            child: _ChannelInfoPanel(
              channel: focusedChannel,
              isFavorite: focusedChannel == null
                  ? false
                  : isFavorite(focusedChannel!),
              onFavoriteToggle: focusedChannel == null
                  ? null
                  : () => onFavoriteToggle(focusedChannel!),
              onPlay: focusedChannel == null
                  ? null
                  : () => onPlayChannel(focusedChannel!),
            ),
          ),
        ],
      ],
    );
  }
}

class _CategorySidebar extends StatelessWidget {
  final Playlist playlist;
  final String? selectedGroup;
  final ValueChanged<String?> onGroupSelected;

  const _CategorySidebar({
    required this.playlist,
    required this.selectedGroup,
    required this.onGroupSelected,
  });

  int _countFor(String? group) {
    if (group == null) return playlist.channels.length;
    return playlist.channels.where((channel) => channel.group == group).length;
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String?>[null, ...playlist.groups];

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Text(
              'CATEGORÍAS',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                final selected = group == selectedGroup;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: ListTile(
                    dense: true,
                    selected: selected,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Icon(
                      group == null ? Icons.apps : Icons.folder_outlined,
                    ),
                    title: Text(
                      group ?? 'Todos los canales',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text('${_countFor(group)}'),
                    onTap: () => onGroupSelected(group),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelInfoPanel extends StatelessWidget {
  final Channel? channel;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onPlay;

  const _ChannelInfoPanel({
    required this.channel,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final channel = this.channel;
    if (channel == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Pasá el cursor sobre un canal para ver sus datos.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 150,
              height: 110,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: _Logo(channel: channel),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            channel.name,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.folder_outlined, size: 18),
              const SizedBox(width: 7),
              Expanded(child: Text(channel.group ?? 'Sin categoría')),
            ],
          ),
          const SizedBox(height: 6),
          if (channel.tvgId != null && channel.tvgId!.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.badge_outlined, size: 18),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    channel.tvgId!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Reproducir canal'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onFavoriteToggle,
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
              ),
              label: Text(
                isFavorite ? 'Quitar de favoritos' : 'Agregar a favoritos',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactChannelLayout extends StatelessWidget {
  final Playlist playlist;
  final List<Channel> channels;
  final String? selectedGroup;
  final String query;
  final ValueChanged<String?> onGroupSelected;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Channel> onPlayChannel;
  final ValueChanged<Channel> onFavoriteToggle;
  final bool Function(Channel) isFavorite;

  const _CompactChannelLayout({
    required this.playlist,
    required this.channels,
    required this.selectedGroup,
    required this.query,
    required this.onGroupSelected,
    required this.onQueryChanged,
    required this.onPlayChannel,
    required this.onFavoriteToggle,
    required this.isFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextFormField(
            initialValue: query,
            decoration: const InputDecoration(
              hintText: 'Buscar canal…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: onQueryChanged,
          ),
        ),
        if (playlist.groups.isNotEmpty)
          SizedBox(
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              children: [
                _GroupChip(
                  label: 'Todos',
                  selected: selectedGroup == null,
                  onTap: () => onGroupSelected(null),
                ),
                ...playlist.groups.map(
                  (group) => _GroupChip(
                    label: group,
                    selected: selectedGroup == group,
                    onTap: () => onGroupSelected(group),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: channels.isEmpty
              ? const Center(child: Text('No se encontraron canales'))
              : ListView.builder(
                  itemCount: channels.length,
                  itemBuilder: (context, index) {
                    final channel = channels[index];
                    return ChannelTile(
                      channel: channel,
                      isFavorite: isFavorite(channel),
                      onFavoriteToggle: () => onFavoriteToggle(channel),
                      onTap: () => onPlayChannel(channel),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _GroupChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GroupChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final Channel channel;

  const _Logo({required this.channel});

  @override
  Widget build(BuildContext context) {
    final logo = channel.logoUrl;
    if (logo == null || logo.isEmpty) {
      return const Center(child: Icon(Icons.live_tv, size: 50));
    }

    return Image.network(
      logo,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          const Center(child: Icon(Icons.live_tv, size: 50)),
    );
  }
}
