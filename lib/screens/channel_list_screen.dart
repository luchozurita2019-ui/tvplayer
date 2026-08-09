import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../providers/iptv_provider.dart';
import '../services/artwork_cache_service.dart';
import '../widgets/cached_artwork_image.dart';
import 'player_screen.dart';

enum _CatalogMode { live, movies, series, radios }

extension on _CatalogMode {
  String get title => switch (this) {
        _CatalogMode.live => 'TV en vivo',
        _CatalogMode.movies => 'Películas',
        _CatalogMode.series => 'Series',
        _CatalogMode.radios => 'Radios',
      };

  String get itemLabel => switch (this) {
        _CatalogMode.live => 'canales',
        _CatalogMode.movies => 'películas',
        _CatalogMode.series => 'series',
        _CatalogMode.radios => 'radios',
      };

  IconData get icon => switch (this) {
        _CatalogMode.live => Icons.live_tv_rounded,
        _CatalogMode.movies => Icons.movie_creation_rounded,
        _CatalogMode.series => Icons.video_library_rounded,
        _CatalogMode.radios => Icons.radio_rounded,
      };

  bool get usesPoster =>
      this == _CatalogMode.movies || this == _CatalogMode.series;
}

class ChannelListScreen extends StatefulWidget {
  final Playlist playlist;

  const ChannelListScreen({super.key, required this.playlist});

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  String? _selectedGroup;
  String _query = '';
  late List<String> _groups;
  late Map<String, int> _groupCounts;
  bool _initialArtworkReady = false;

  _CatalogMode get _mode {
    final id = widget.playlist.id;
    if (id.endsWith('::movies')) return _CatalogMode.movies;
    if (id.endsWith('::series')) return _CatalogMode.series;
    if (id.endsWith('::radios')) return _CatalogMode.radios;
    return _CatalogMode.live;
  }

  @override
  void initState() {
    super.initState();
    _rebuildCategoryCache(widget.playlist);
    unawaited(_prepareInitialArtwork());
  }

  @override
  void didUpdateWidget(covariant ChannelListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.playlist.channels, widget.playlist.channels) ||
        oldWidget.playlist.lastUpdated != widget.playlist.lastUpdated) {
      _rebuildCategoryCache(widget.playlist);
      if (_selectedGroup != null && !_groups.contains(_selectedGroup)) {
        _selectedGroup = null;
      }
    }
  }

  void _rebuildCategoryCache(Playlist playlist) {
    final counts = <String, int>{};
    for (final channel in playlist.channels) {
      final group = channel.group?.trim();
      if (group == null || group.isEmpty) continue;
      counts[group] = (counts[group] ?? 0) + 1;
    }
    final groups = counts.keys.toList()..sort();
    _groups = List.unmodifiable(groups);
    _groupCounts = Map.unmodifiable(counts);
  }

  Future<void> _prepareInitialArtwork() async {
    final limit = _mode.usesPoster ? 12 : 24;
    await ArtworkCacheService.instance.warmSection(
      widget.playlist.channels,
      limit: limit,
    );
    if (!mounted) return;
    setState(() => _initialArtworkReady = true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final playlist = provider.playlistById(widget.playlist.id) ?? widget.playlist;
    final channels = _filteredChannels(playlist);
    final mode = _mode;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                mode.icon,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TV FULL',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Text(
                    '${mode.title} · ${channels.length} ${mode.itemLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (playlist.isRemote)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
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
      body: !_initialArtworkReady
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Preparando logos y portadas…'),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return _DesktopCatalogLayout(
              mode: mode,
              playlist: playlist,
              channels: channels,
              groups: _groups,
              groupCounts: _groupCounts,
              selectedGroup: _selectedGroup,
              query: _query,
              onGroupSelected: (group) {
                setState(() => _selectedGroup = group);
              },
              onQueryChanged: (value) => setState(() => _query = value),
              onPlay: (channel) => _openChannel(
                context,
                channels,
                channel,
                provider,
              ),
              onFavoriteToggle: provider.toggleFavorite,
              isFavorite: provider.isFavorite,
            );
          }

          return _CompactCatalogLayout(
            mode: mode,
            channels: channels,
            groups: _groups,
            selectedGroup: _selectedGroup,
            query: _query,
            onGroupSelected: (group) {
              setState(() => _selectedGroup = group);
            },
            onQueryChanged: (value) => setState(() => _query = value),
            onPlay: (channel) => _openChannel(
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
    final normalized = _query.trim().toLowerCase();
    if (_selectedGroup == null && normalized.isEmpty) {
      return playlist.channels;
    }

    return playlist.channels.where((channel) {
      if (_selectedGroup != null && channel.group?.trim() != _selectedGroup) {
        return false;
      }
      if (normalized.isEmpty) return true;

      final name = channel.name.toLowerCase();
      final group = channel.group?.toLowerCase() ?? '';
      return name.contains(normalized) || group.contains(normalized);
    }).toList(growable: false);
  }

  Future<void> _openChannel(
    BuildContext context,
    List<Channel> channels,
    Channel channel,
    IptvProvider provider,
  ) async {
    final index = channels.indexOf(channel);
    if (index < 0) return;

    ArtworkCacheService.instance.pauseForPlayback();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          channel: channel,
          playlist: channels,
          initialIndex: index,
          settings: provider.playbackSettings,
          isLiveContent:
              _mode == _CatalogMode.live || _mode == _CatalogMode.radios,
        ),
      ),
    );
    ArtworkCacheService.instance.resumeBrowsing();
  }
}

class _DesktopCatalogLayout extends StatelessWidget {
  final _CatalogMode mode;
  final Playlist playlist;
  final List<Channel> channels;
  final List<String> groups;
  final Map<String, int> groupCounts;
  final String? selectedGroup;
  final String query;
  final ValueChanged<String?> onGroupSelected;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Channel> onPlay;
  final ValueChanged<Channel> onFavoriteToggle;
  final bool Function(Channel) isFavorite;

  const _DesktopCatalogLayout({
    required this.mode,
    required this.playlist,
    required this.channels,
    required this.groups,
    required this.groupCounts,
    required this.selectedGroup,
    required this.query,
    required this.onGroupSelected,
    required this.onQueryChanged,
    required this.onPlay,
    required this.onFavoriteToggle,
    required this.isFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 268,
          child: _CategorySidebar(
            mode: mode,
            totalCount: playlist.channels.length,
            groups: groups,
            groupCounts: groupCounts,
            selectedGroup: selectedGroup,
            onGroupSelected: onGroupSelected,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CatalogToolbar(
                mode: mode,
                query: query,
                visibleCount: channels.length,
                selectedGroup: selectedGroup,
                onQueryChanged: onQueryChanged,
              ),
              Expanded(
                child: _CatalogGrid(
                  mode: mode,
                  channels: channels,
                  onPlay: onPlay,
                  onFavoriteToggle: onFavoriteToggle,
                  isFavorite: isFavorite,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CatalogToolbar extends StatelessWidget {
  final _CatalogMode mode;
  final String query;
  final int visibleCount;
  final String? selectedGroup;
  final ValueChanged<String> onQueryChanged;

  const _CatalogToolbar({
    required this.mode,
    required this.query,
    required this.visibleCount,
    required this.selectedGroup,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedGroup ?? mode.title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$visibleCount ${mode.itemLabel}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white60,
                      ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 360,
            child: TextFormField(
              initialValue: query,
              decoration: InputDecoration(
                hintText: 'Buscar en ${mode.title.toLowerCase()}…',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.4,
                  ),
                ),
                isDense: true,
              ),
              onChanged: onQueryChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySidebar extends StatelessWidget {
  final _CatalogMode mode;
  final int totalCount;
  final List<String> groups;
  final Map<String, int> groupCounts;
  final String? selectedGroup;
  final ValueChanged<String?> onGroupSelected;

  const _CategorySidebar({
    required this.mode,
    required this.totalCount,
    required this.groups,
    required this.groupCounts,
    required this.selectedGroup,
    required this.onGroupSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF081728),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  Icon(
                    mode.icon,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      mode.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Text(
                'CATEGORÍAS',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white54,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
                itemCount: groups.length + 1,
                itemBuilder: (context, index) {
                  final group = index == 0 ? null : groups[index - 1];
                  final selected = group == selectedGroup;
                  final count = group == null
                      ? totalCount
                      : (groupCounts[group] ?? 0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: ListTile(
                      minTileHeight: 54,
                      selected: selected,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      selectedTileColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.20),
                      leading: Icon(
                        group == null
                            ? Icons.grid_view_rounded
                            : Icons.folder_rounded,
                        size: 24,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white70,
                      ),
                      title: Text(
                        group ?? 'Todos',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      onTap: () => onGroupSelected(group),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogGrid extends StatelessWidget {
  final _CatalogMode mode;
  final List<Channel> channels;
  final ValueChanged<Channel> onPlay;
  final ValueChanged<Channel> onFavoriteToggle;
  final bool Function(Channel) isFavorite;

  const _CatalogGrid({
    required this.mode,
    required this.channels,
    required this.onPlay,
    required this.onFavoriteToggle,
    required this.isFavorite,
  });

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(mode.icon, size: 64, color: Colors.white24),
            const SizedBox(height: 14),
            Text(
              'No se encontraron ${mode.itemLabel}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = mode.usesPoster
            ? (width >= 1500
                ? 7
                : width >= 1250
                    ? 6
                    : width >= 1000
                        ? 5
                        : 4)
            : (width >= 1500
                ? 6
                : width >= 1250
                    ? 5
                    : width >= 1000
                        ? 4
                        : 3);

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 34),
          cacheExtent: 80,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 18,
            mainAxisSpacing: 18,
            childAspectRatio: mode.usesPoster ? 0.68 : 1.34,
          ),
          itemCount: channels.length,
          itemBuilder: (context, index) {
            final channel = channels[index];
            return _CatalogCard(
              mode: mode,
              channel: channel,
              isFavorite: isFavorite(channel),
              onFavoriteToggle: () => onFavoriteToggle(channel),
              onTap: () => onPlay(channel),
            );
          },
        );
      },
    );
  }
}

class _CompactCatalogLayout extends StatelessWidget {
  final _CatalogMode mode;
  final List<Channel> channels;
  final List<String> groups;
  final String? selectedGroup;
  final String query;
  final ValueChanged<String?> onGroupSelected;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Channel> onPlay;
  final ValueChanged<Channel> onFavoriteToggle;
  final bool Function(Channel) isFavorite;

  const _CompactCatalogLayout({
    required this.mode,
    required this.channels,
    required this.groups,
    required this.selectedGroup,
    required this.query,
    required this.onGroupSelected,
    required this.onQueryChanged,
    required this.onPlay,
    required this.onFavoriteToggle,
    required this.isFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextFormField(
            initialValue: query,
            decoration: InputDecoration(
              hintText: 'Buscar en ${mode.title.toLowerCase()}…',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
            onChanged: onQueryChanged,
          ),
        ),
        if (groups.isNotEmpty)
          SizedBox(
            height: 58,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _GroupChip(
                  label: 'Todos',
                  selected: selectedGroup == null,
                  onTap: () => onGroupSelected(null),
                ),
                ...groups.map(
                  (group) => _GroupChip(
                    label: group,
                    selected: selectedGroup == group,
                    onTap: () => onGroupSelected(group),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Text(
            selectedGroup ?? mode.title.toUpperCase(),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        Expanded(
          child: channels.isEmpty
              ? Center(child: Text('No se encontraron ${mode.itemLabel}'))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = mode.usesPoster
                        ? (constraints.maxWidth >= 700 ? 4 : 3)
                        : (constraints.maxWidth >= 700 ? 3 : 2);
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: mode.usesPoster ? 0.68 : 1.25,
                      ),
                      itemCount: channels.length,
                      itemBuilder: (context, index) {
                        final channel = channels[index];
                        return _CatalogCard(
                          mode: mode,
                          channel: channel,
                          isFavorite: isFavorite(channel),
                          onFavoriteToggle: () => onFavoriteToggle(channel),
                          onTap: () => onPlay(channel),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CatalogCard extends StatefulWidget {
  final _CatalogMode mode;
  final Channel channel;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onTap;

  const _CatalogCard({
    required this.mode,
    required this.channel,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onTap,
  });

  @override
  State<_CatalogCard> createState() => _CatalogCardState();
}

class _CatalogCardState extends State<_CatalogCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.025 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Card(
          elevation: _hovered ? 7 : 1,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: _hovered
                  ? primary.withValues(alpha: 0.75)
                  : Colors.white.withValues(alpha: 0.08),
              width: _hovered ? 1.4 : 1,
            ),
          ),
          child: InkWell(
            onTap: widget.onTap,
            child: widget.mode.usesPoster
                ? _PosterCardBody(
                    mode: widget.mode,
                    channel: widget.channel,
                    isFavorite: widget.isFavorite,
                    onFavoriteToggle: widget.onFavoriteToggle,
                  )
                : _LiveCardBody(
                    mode: widget.mode,
                    channel: widget.channel,
                    isFavorite: widget.isFavorite,
                    onFavoriteToggle: widget.onFavoriteToggle,
                  ),
          ),
        ),
      ),
    );
  }
}

class _LiveCardBody extends StatelessWidget {
  final _CatalogMode mode;
  final Channel channel;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;

  const _LiveCardBody({
    required this.mode,
    required this.channel,
    required this.isFavorite,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF071526),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _Artwork(
              channel: channel,
              mode: mode,
              fit: BoxFit.contain,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 8, 12),
          child: Row(
            children: [
              if (mode == _CatalogMode.live) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF2D2D),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x88FF2D2D),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: isFavorite
                    ? 'Quitar de favoritos'
                    : 'Agregar a favoritos',
                onPressed: onFavoriteToggle,
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PosterCardBody extends StatelessWidget {
  final _CatalogMode mode;
  final Channel channel;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;

  const _PosterCardBody({
    required this.mode,
    required this.channel,
    required this.isFavorite,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _Artwork(
          channel: channel,
          mode: mode,
          fit: BoxFit.cover,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x12000000),
                Color(0x30000000),
                Color(0xE9000000),
              ],
              stops: [0, 0.55, 1],
            ),
          ),
        ),
        Positioned(
          top: 9,
          right: 9,
          child: Material(
            color: const Color(0xB0000000),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: isFavorite
                  ? 'Quitar de favoritos'
                  : 'Agregar a favoritos',
              onPressed: onFavoriteToggle,
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                size: 20,
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                channel.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  height: 1.1,
                ),
              ),
              if (channel.group != null && channel.group!.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  channel.group!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Artwork extends StatelessWidget {
  final Channel channel;
  final _CatalogMode mode;
  final BoxFit fit;

  const _Artwork({
    required this.channel,
    required this.mode,
    required this.fit,
  });

  @override
  Widget build(BuildContext context) {
    final logo = channel.logoUrl?.trim();
    if (logo == null || logo.isEmpty) {
      return _ArtworkFallback(mode: mode);
    }

    return CachedArtworkImage(
      url: logo,
      fit: fit,
      cacheWidth: mode.usesPoster ? 420 : 300,
      fallback: _ArtworkFallback(mode: mode),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  final _CatalogMode mode;

  const _ArtworkFallback({required this.mode});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B1B2F),
      alignment: Alignment.center,
      child: Icon(
        mode.icon,
        size: mode.usesPoster ? 62 : 54,
        color: Colors.white30,
      ),
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
