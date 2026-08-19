import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../providers/iptv_provider.dart';
import '../services/artwork_cache_service.dart';
import '../services/parental_control_service.dart';
import '../services/player_route_guard.dart';
import '../services/tv_ui_settings_service.dart';
import 'add_source_screen.dart';
import 'edit_source_screen.dart';
import 'parental_control_screen.dart';
import 'playback_settings_screen.dart';
import 'player_screen.dart';
import 'source_content_screen.dart';

const _tvBlue = Color(0xFF1677FF);
const _tvBlueBright = Color(0xFF2D92FF);
const _tvGold = Color(0xFFE4B94F);
const _tvBackground = Color(0xFF060B12);
const _tvSidebar = Color(0xFF08111D);
const _tvPanel = Color(0xFF0C1725);
const _tvPanelSoft = Color(0xFF101D2D);
const _tvBorder = Color(0xFF203149);
const _tvText = Color(0xFFF5F8FC);
const _tvMuted = Color(0xFF8D9CAF);

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  static const _favoritePlaylistsKey = 'tv_full_favorite_playlist_ids_v1';

  int _section = 0;
  Set<String> _favoritePlaylistIds = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_loadFavoritePlaylists());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ParentalControlService.instance.init());
      context.read<IptvProvider>().init();
    });
  }

  Future<void> _loadFavoritePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_favoritePlaylistsKey) ?? const <String>[];
    if (!mounted) return;
    setState(() => _favoritePlaylistIds = ids.toSet());
  }

  Future<void> _togglePlaylistFavorite(Playlist playlist) async {
    final next = Set<String>.from(_favoritePlaylistIds);
    if (!next.add(playlist.id)) next.remove(playlist.id);
    setState(() => _favoritePlaylistIds = next);
    final prefs = await SharedPreferences.getInstance();
    final values = next.toList()..sort();
    await prefs.setStringList(_favoritePlaylistsKey, values);
  }

  Future<void> _openAddSource() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddSourceScreen()),
    );
  }

  Future<void> _openPlaylist(Playlist playlist) async {
    final navigator = Navigator.of(context);
    await ParentalControlService.instance.init();
    if (!mounted) return;
    await ArtworkCacheService.instance.switchProvider(playlist.id);
    if (!mounted) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => SourceContentScreen(playlist: playlist)),
    );
  }

  Future<void> _openParentalSettings() async {
    final parental = ParentalControlService.instance;
    await parental.init();
    if (!mounted) return;

    if (parental.pinConfigured) {
      final controller = TextEditingController();
      final pin = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Control parental'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(
              labelText: 'Ingresá tu PIN',
              counterText: '',
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (!mounted || pin == null) return;
      if (!parental.verifyPin(pin)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('PIN incorrecto.')));
        return;
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ParentalControlScreen()),
    );
  }

  String get _title => switch (_section) {
        0 => 'Servicios',
        1 => 'Listas favoritas',
        2 => 'Canales favoritos',
        3 => 'Ajustes',
        _ => 'Información',
      };

  String get _subtitle => switch (_section) {
        0 => 'Elegí una lista y empezá a disfrutar.',
        1 => 'Tus listas preferidas.',
        2 => 'Acceso rápido a tus canales favoritos.',
        3 => 'Pantalla, rendimiento y control remoto.',
        _ => 'TV FULL PRO para Android TV.',
      };

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();

    return Scaffold(
      backgroundColor: _tvBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1100;
            final sidebarWidth = compact ? 196.0 : 232.0;
            final overscanX = compact ? 14.0 : 24.0;
            final overscanY = compact ? 10.0 : 16.0;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                overscanX,
                overscanY,
                overscanX,
                overscanY,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _tvBackground,
                    border: Border.all(color: _tvBorder),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: sidebarWidth,
                        child: _TvSidebar(
                          selected: _section,
                          compact: compact,
                          onSelected: (value) => setState(() => _section = value),
                        ),
                      ),
                      Container(width: 1, color: _tvBorder),
                      Expanded(
                        child: Column(
                          children: [
                            _TvTopBar(
                              title: _title,
                              subtitle: _subtitle,
                              showAdd: _section == 0 || _section == 1,
                              onAdd: _openAddSource,
                              onParental: _openParentalSettings,
                            ),
                            Expanded(child: _buildSection(provider)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSection(IptvProvider provider) {
    return switch (_section) {
      0 => _TvServicesView(
          playlists: provider.playlists,
          loading: provider.loading,
          favoriteIds: _favoritePlaylistIds,
          onOpen: _openPlaylist,
          onAdd: _openAddSource,
          onToggleFavorite: (playlist) =>
              unawaited(_togglePlaylistFavorite(playlist)),
        ),
      1 => _TvServicesView(
          playlists: provider.playlists
              .where((playlist) => _favoritePlaylistIds.contains(playlist.id))
              .toList(growable: false),
          loading: provider.loading,
          favoriteIds: _favoritePlaylistIds,
          onOpen: _openPlaylist,
          onAdd: _openAddSource,
          onToggleFavorite: (playlist) =>
              unawaited(_togglePlaylistFavorite(playlist)),
          favoritesOnly: true,
        ),
      2 => _TvChannelFavoritesView(
          channels: provider.favorites,
          settings: provider.playbackSettings,
        ),
      3 => _TvSettingsView(
          onOpenPlaybackSettings: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PlaybackSettingsScreen()),
          ),
        ),
      _ => const _TvInformationView(),
    };
  }
}

class _TvSidebar extends StatelessWidget {
  final int selected;
  final bool compact;
  final ValueChanged<int> onSelected;

  const _TvSidebar({
    required this.selected,
    required this.compact,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _tvSidebar,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 18, compact ? 12 : 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _TvBrand(),
            const SizedBox(height: 26),
            _TvNavItem(
              selected: selected == 0,
              icon: Icons.grid_view_rounded,
              label: 'Servicios',
              autofocus: true,
              onTap: () => onSelected(0),
            ),
            _TvNavItem(
              selected: selected == 1,
              icon: Icons.star_rounded,
              label: 'Listas favoritas',
              onTap: () => onSelected(1),
            ),
            _TvNavItem(
              selected: selected == 2,
              icon: Icons.favorite_rounded,
              label: 'Canales favoritos',
              onTap: () => onSelected(2),
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: _tvBorder),
            const SizedBox(height: 14),
            _TvNavItem(
              selected: selected == 3,
              icon: Icons.settings_rounded,
              label: 'Ajustes',
              onTap: () => onSelected(3),
            ),
            _TvNavItem(
              selected: selected == 4,
              icon: Icons.info_outline_rounded,
              label: 'Información',
              onTap: () => onSelected(4),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _tvPanel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _tvBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.tv_rounded, color: _tvBlue, size: 19),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Modo TV',
                      style: TextStyle(
                        color: _tvText,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvBrand extends StatelessWidget {
  const _TvBrand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _TvMark(),
        SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'TV FULL',
                    style: TextStyle(
                      color: _tvText,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'PRO',
                    style: TextStyle(
                      color: _tvGold,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 2),
              Text(
                'ANDROID TV',
                style: TextStyle(
                  color: _tvMuted,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TvMark extends StatelessWidget {
  const _TvMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 36,
      decoration: BoxDecoration(
        color: _tvBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
    );
  }
}

class _TvNavItem extends StatefulWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  const _TvNavItem({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_TvNavItem> createState() => _TvNavItemState();
}

class _TvNavItemState extends State<_TvNavItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: active ? _tvBlue.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          autofocus: widget.autofocus,
          canRequestFocus: true,
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: _focused
                    ? _tvBlueBright
                    : widget.selected
                        ? _tvBlue.withValues(alpha: 0.65)
                        : Colors.transparent,
                width: _focused ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(widget.icon, color: active ? _tvBlueBright : _tvMuted, size: 21),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? _tvText : const Color(0xFFB6C1CF),
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvTopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool showAdd;
  final VoidCallback onAdd;
  final VoidCallback onParental;

  const _TvTopBar({
    required this.title,
    required this.subtitle,
    required this.showAdd,
    required this.onAdd,
    required this.onParental,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: _tvBackground,
        border: Border(bottom: BorderSide(color: _tvBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _tvText,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _tvMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (showAdd) ...[
            _TvActionButton(
              icon: Icons.add_rounded,
              label: 'Agregar lista',
              onTap: onAdd,
              primary: true,
            ),
            const SizedBox(width: 10),
          ],
          _TvActionButton(
            icon: Icons.shield_outlined,
            label: 'Control parental',
            onTap: onParental,
          ),
        ],
      ),
    );
  }
}

class _TvActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _TvActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  State<_TvActionButton> createState() => _TvActionButtonState();
}

class _TvActionButtonState extends State<_TvActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.primary ? _tvBlue : _tvPanel,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        canRequestFocus: true,
        onFocusChange: (value) => setState(() => _focused = value),
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? _tvBlueBright : (widget.primary ? _tvBlue : _tvBorder),
              width: _focused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: Colors.white, size: 19),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: const TextStyle(
                  color: _tvText,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvServicesView extends StatelessWidget {
  final List<Playlist> playlists;
  final bool loading;
  final Set<String> favoriteIds;
  final ValueChanged<Playlist> onOpen;
  final ValueChanged<Playlist> onToggleFavorite;
  final VoidCallback onAdd;
  final bool favoritesOnly;

  const _TvServicesView({
    required this.playlists,
    required this.loading,
    required this.favoriteIds,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onAdd,
    this.favoritesOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: _tvBlue));
    }

    if (playlists.isEmpty) {
      return _TvEmptyState(
        icon: favoritesOnly ? Icons.star_border_rounded : Icons.playlist_add_rounded,
        title: favoritesOnly ? 'No hay listas favoritas' : 'Todavía no hay servicios',
        message: favoritesOnly
            ? 'Marcá una lista con la estrella para verla acá.'
            : 'Agregá una lista para comenzar.',
        actionLabel: favoritesOnly ? null : 'Agregar lista',
        onAction: favoritesOnly ? null : onAdd,
      );
    }

    final ordered = List<Playlist>.from(playlists)
      ..sort((a, b) {
        final af = favoriteIds.contains(a.id);
        final bf = favoriteIds.contains(b.id);
        if (af != bf) return af ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1500
            ? 4
            : constraints.maxWidth >= 1080
                ? 3
                : 2;

        return CustomScrollView(
          key: PageStorageKey<String>(favoritesOnly ? 'tv_favorite_lists' : 'tv_services'),
          cacheExtent: 420,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        favoritesOnly ? 'Tus favoritas' : 'Mis listas',
                        style: const TextStyle(
                          color: _tvText,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${ordered.length} ${ordered.length == 1 ? 'lista' : 'listas'}',
                      style: const TextStyle(color: _tvMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.15,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final playlist = ordered[index];
                    return _TvPlaylistCard(
                      playlist: playlist,
                      favorite: favoriteIds.contains(playlist.id),
                      onOpen: () => onOpen(playlist),
                      onToggleFavorite: () => onToggleFavorite(playlist),
                    );
                  },
                  childCount: ordered.length,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TvPlaylistCard extends StatefulWidget {
  final Playlist playlist;
  final bool favorite;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;

  const _TvPlaylistCard({
    required this.playlist,
    required this.favorite,
    required this.onOpen,
    required this.onToggleFavorite,
  });

  @override
  State<_TvPlaylistCard> createState() => _TvPlaylistCardState();
}

class _TvPlaylistCardState extends State<_TvPlaylistCard> {
  bool _focused = false;

  Future<void> _edit() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditSourceScreen(playlist: widget.playlist)),
    );
  }

  Future<void> _refresh() async {
    final provider = context.read<IptvProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await provider.refreshPlaylist(widget.playlist.id);
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            provider.error == null
                ? 'Lista actualizada correctamente.'
                : 'No se pudo actualizar: ${provider.error}',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<IptvProvider>();
    return RepaintBoundary(
      child: Material(
        color: _focused ? const Color(0xFF10243B) : _tvPanel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          canRequestFocus: true,
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onOpen,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused
                    ? _tvBlueBright
                    : widget.favorite
                        ? _tvGold.withValues(alpha: 0.60)
                        : _tvBorder,
                width: _focused ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _tvBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.live_tv_rounded, color: _tvBlueBright, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _tvText,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: widget.favorite ? 'Quitar favorito' : 'Agregar favorito',
                      onPressed: widget.onToggleFavorite,
                      icon: Icon(
                        widget.favorite ? Icons.star_rounded : Icons.star_border_rounded,
                        color: widget.favorite ? _tvGold : _tvMuted,
                        size: 21,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Opciones',
                      iconColor: _tvMuted,
                      onSelected: (value) async {
                        switch (value) {
                          case 'edit':
                            await _edit();
                            break;
                          case 'refresh':
                            await _refresh();
                            break;
                          case 'delete':
                            await provider.removePlaylist(widget.playlist.id);
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Editar lista')),
                        PopupMenuItem(
                          value: 'refresh',
                          enabled: widget.playlist.isRemote,
                          child: const Text('Actualizar lista'),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(value: 'delete', child: Text('Eliminar lista')),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _tvPanelSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.playlist.sourceType.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _tvBlueBright,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${widget.playlist.channels.length} elementos',
                      style: const TextStyle(color: _tvMuted, fontSize: 10),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_rounded, color: _tvBlueBright, size: 18),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvChannelFavoritesView extends StatelessWidget {
  final List<Channel> channels;
  final dynamic settings;

  const _TvChannelFavoritesView({required this.channels, required this.settings});

  @override
  Widget build(BuildContext context) {
    final parental = ParentalControlService.instance;
    final visible = parental.enabled && parental.isLocked
        ? channels.where(parental.canShowChannel).toList(growable: false)
        : channels;

    if (visible.isEmpty) {
      return const _TvEmptyState(
        icon: Icons.favorite_border_rounded,
        title: 'Sin canales favoritos',
        message: 'Marcá tus canales preferidos para encontrarlos acá.',
      );
    }

    return ListView.builder(
      key: const PageStorageKey<String>('tv_channel_favorites'),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
      itemCount: visible.length,
      cacheExtent: 360,
      itemBuilder: (context, index) {
        final channel = visible[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _TvChannelRow(
            channel: channel,
            onTap: () => PlayerRouteGuard.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  channel: channel,
                  playlist: visible,
                  initialIndex: index,
                  settings: settings,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TvChannelRow extends StatefulWidget {
  final Channel channel;
  final VoidCallback onTap;

  const _TvChannelRow({required this.channel, required this.onTap});

  @override
  State<_TvChannelRow> createState() => _TvChannelRowState();
}

class _TvChannelRowState extends State<_TvChannelRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _focused ? const Color(0xFF10243B) : _tvPanel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        canRequestFocus: true,
        onFocusChange: (value) => setState(() => _focused = value),
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _focused ? _tvBlueBright : _tvBorder, width: _focused ? 2 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _tvPanelSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.live_tv_rounded, color: _tvBlueBright, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _tvText, fontWeight: FontWeight.w800),
                    ),
                    if ((widget.channel.group ?? '').trim().isNotEmpty)
                      Text(
                        widget.channel.group!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _tvMuted, fontSize: 10),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.play_circle_fill_rounded, color: _tvBlueBright, size: 27),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvSettingsView extends StatelessWidget {
  final VoidCallback onOpenPlaybackSettings;

  const _TvSettingsView({required this.onOpenPlaybackSettings});

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<TvUiSettingsService>();
    final playback = context.watch<IptvProvider>().playbackSettings;

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
      children: [
        _TvSettingsCard(
          title: 'Tamaño de texto',
          subtitle: 'Se aplica a toda la interfaz y queda guardado en este televisor.',
          icon: Icons.text_fields_rounded,
          child: Row(
            children: TvTextSize.values
                .map(
                  (value) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: value == TvTextSize.large ? 0 : 10,
                      ),
                      child: _TvTextSizeOption(
                        value: value,
                        selected: ui.textSize == value,
                        onTap: () => unawaited(ui.setTextSize(value)),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 14),
        _TvSettingsCard(
          title: 'Rendimiento',
          subtitle: 'Se conserva el motor de reproducción estable de la V3.',
          icon: Icons.speed_rounded,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Buffer ${playback.bufferMb} MB · reintentos ${playback.maxRetries}',
                  style: const TextStyle(color: _tvMuted, fontSize: 11),
                ),
              ),
              _TvActionButton(
                icon: Icons.tune_rounded,
                label: 'Configurar',
                onTap: onOpenPlaybackSettings,
                primary: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _TvSettingsCard(
          title: 'Control remoto',
          subtitle: 'Navegación diseñada para DPAD de Android TV y TV Box.',
          icon: Icons.settings_remote_rounded,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _RemoteKeyChip('↑ ↓ ← →', 'Navegar'),
              _RemoteKeyChip('OK', 'Seleccionar'),
              _RemoteKeyChip('BACK', 'Volver'),
              _RemoteKeyChip('▶ / ❚❚', 'Reproducir / Pausar'),
              _RemoteKeyChip('⏮ / ⏭', 'Anterior / Siguiente'),
            ],
          ),
        ),
      ],
    );
  }
}

class _TvTextSizeOption extends StatefulWidget {
  final TvTextSize value;
  final bool selected;
  final VoidCallback onTap;

  const _TvTextSizeOption({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_TvTextSizeOption> createState() => _TvTextSizeOptionState();
}

class _TvTextSizeOptionState extends State<_TvTextSizeOption> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;
    return Material(
      color: active ? _tvBlue.withValues(alpha: 0.14) : _tvPanelSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        canRequestFocus: true,
        onFocusChange: (value) => setState(() => _focused = value),
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 74,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused
                  ? _tvBlueBright
                  : widget.selected
                      ? _tvBlue
                      : _tvBorder,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.value.label,
                style: const TextStyle(
                  color: _tvText,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(widget.value.scale * 100).round()}%',
                style: const TextStyle(color: _tvMuted, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvSettingsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _TvSettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _tvPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _tvBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _tvBlue.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: _tvBlueBright, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _tvText,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _tvMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _RemoteKeyChip extends StatelessWidget {
  final String keyName;
  final String label;

  const _RemoteKeyChip(this.keyName, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _tvPanelSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _tvBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            keyName,
            style: const TextStyle(
              color: _tvBlueBright,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: _tvMuted, fontSize: 10)),
        ],
      ),
    );
  }
}

class _TvInformationView extends StatelessWidget {
  const _TvInformationView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _tvPanel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _tvBorder),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TvMark(),
              SizedBox(height: 14),
              Text(
                'TV FULL PRO',
                style: TextStyle(
                  color: _tvText,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Versión optimizada para Android TV y TV Box. La vinculación con el panel, pagos, listas y reproducción mantienen la lógica estable de la versión móvil.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _tvMuted, fontSize: 11, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _TvEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _tvPanel,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: _tvBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _tvBlueBright, size: 42),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _tvText,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _tvMuted, fontSize: 11),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                _TvActionButton(
                  icon: Icons.add_rounded,
                  label: actionLabel!,
                  onTap: onAction!,
                  primary: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
