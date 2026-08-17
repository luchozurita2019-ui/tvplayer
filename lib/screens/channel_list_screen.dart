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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final playlist = provider.playlistById(widget.playlist.id) ?? widget.playlist;

    var channels = playlist.channels;
    if (_selectedGroup != null) {
      channels = channels.where((c) => c.group == _selectedGroup).toList();
    }
    channels = provider.filterChannels(channels);

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
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
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar canal...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) =>
                  context.read<IptvProvider>().setSearchQuery(value),
            ),
          ),
          if (playlist.groups.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  _GroupChip(
                    label: 'Todos',
                    selected: _selectedGroup == null,
                    onTap: () => setState(() => _selectedGroup = null),
                  ),
                  ...playlist.groups.map((g) => _GroupChip(
                        label: g,
                        selected: _selectedGroup == g,
                        onTap: () => setState(() => _selectedGroup = g),
                      )),
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
                        isFavorite: provider.isFavorite(channel),
                        onFavoriteToggle: () =>
                            context.read<IptvProvider>().toggleFavorite(channel),
                        onTap: () => _openPlayer(
                          context,
                          channels,
                          index,
                          provider,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openPlayer(
    BuildContext context,
    List<Channel> channels,
    int index,
    IptvProvider provider,
  ) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        channel: channels[index],
        playlist: channels,
        initialIndex: index,
        settings: provider.playbackSettings,
      ),
    ));
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
