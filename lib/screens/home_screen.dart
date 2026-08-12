import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/playback_settings.dart';
import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../providers/iptv_provider.dart';
import '../services/artwork_cache_service.dart';
import '../services/parental_control_service.dart';
import '../services/player_route_guard.dart';
import '../widgets/cached_artwork_image.dart';
import 'add_source_screen.dart';
import 'edit_source_screen.dart';
import 'parental_control_screen.dart';
import 'playback_settings_screen.dart';
import 'player_screen.dart';
import 'source_content_screen.dart';

const _proBlue = Color(0xFF16A8FF);
const _proBlueDeep = Color(0xFF0875D1);
const _proGold = Color(0xFFE4B94F);
const _proSilver = Color(0xFFB9C2CE);
const _proBackground = Color(0xFF070B12);
const _proPanel = Color(0xFF0D141E);
const _proPanelSoft = Color(0xFF111B28);
const _proBorder = Color(0xFF233043);
const _proText = Color(0xFFF4F7FB);
const _proMuted = Color(0xFF8D9AAD);
const bool _androidTvBuild = bool.fromEnvironment('TV_FULL_ANDROID_TV');

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
    if (!next.add(playlist.id)) {
      next.remove(playlist.id);
    }

    setState(() => _favoritePlaylistIds = next);
    final prefs = await SharedPreferences.getInstance();
    final ordered = next.toList()..sort();
    await prefs.setStringList(_favoritePlaylistsKey, ordered);
  }

  Future<void> _openAddSource(BuildContext context) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AddSourceScreen()));
  }

  void _selectSection(int section) {
    if (_section == section) return;
    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = _androidTvBuild || constraints.maxWidth >= 860;

        if (desktop) {
          return Scaffold(
            backgroundColor: _proBackground,
            body: SafeArea(
              child: Row(
                children: [
                  _PremiumSidebar(
                    selectedIndex: _section,
                    onSelected: _selectSection,
                  ),
                  Container(width: 1, color: _proBorder),
                  Expanded(
                    child: Column(
                      children: [
                        _PremiumTopBar(
                          title: _sectionTitle,
                          subtitle: _sectionSubtitle,
                          showAddButton: _section == 0 || _section == 1,
                          onAdd: () => _openAddSource(context),
                          onParental: () =>
                              unawaited(_openParentalSettings(context)),
                          onInfo: () => _selectSection(4),
                          onProfile: () => _selectSection(5),
                        ),
                        Expanded(child: _sectionBody(provider)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: _proBackground,
          drawer: Drawer(
            width: 286,
            backgroundColor: _proBackground,
            child: SafeArea(
              child: _PremiumSidebar(
                selectedIndex: _section,
                onSelected: (index) {
                  Navigator.of(context).pop();
                  _selectSection(index);
                },
                compact: true,
              ),
            ),
          ),
          appBar: AppBar(
            backgroundColor: _proPanel,
            foregroundColor: _proText,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            title: const _CompactBrand(),
            actions: [
              IconButton(
                tooltip: 'Información',
                onPressed: () => _selectSection(4),
                icon: const Icon(Icons.info_outline_rounded),
              ),
              IconButton(
                tooltip: 'Perfil · Próximamente',
                onPressed: () => _selectSection(5),
                icon: const Icon(Icons.account_circle_outlined),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: _sectionBody(provider),
          floatingActionButton: _section == 0 || _section == 1
              ? FloatingActionButton.extended(
                  backgroundColor: _proBlue,
                  foregroundColor: Colors.white,
                  onPressed: () => _openAddSource(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Agregar lista',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                )
              : null,
        );
      },
    );
  }

  String get _sectionTitle => switch (_section) {
    0 => 'Servicios',
    1 => 'Listas favoritas',
    2 => 'Canales favoritos',
    3 => 'TV FULL PRO',
    4 => 'Información',
    _ => 'Perfil',
  };

  String get _sectionSubtitle => switch (_section) {
    0 => 'Administrá tus listas y accesos desde un solo lugar.',
    1 => 'Tus servicios preferidos, siempre primero.',
    2 => 'Acceso rápido a los canales que marcaste como favoritos.',
    3 => 'Rendimiento avanzado y configuración premium.',
    4 => 'Actualizaciones, novedades y datos de TV FULL.',
    _ => 'Una nueva experiencia de perfiles llegará próximamente.',
  };

  Widget _sectionBody(IptvProvider provider) {
    return switch (_section) {
      0 => _PlaylistsView(
        playlists: provider.playlists,
        loading: provider.loading,
        favoriteIds: _favoritePlaylistIds,
        onToggleFavorite: (playlist) =>
            unawaited(_togglePlaylistFavorite(playlist)),
        onAddPlaylist: () => _openAddSource(context),
      ),
      1 => _FavoritePlaylistsView(
        playlists: provider.playlists,
        loading: provider.loading,
        favoriteIds: _favoritePlaylistIds,
        onToggleFavorite: (playlist) =>
            unawaited(_togglePlaylistFavorite(playlist)),
        onAddPlaylist: () => _openAddSource(context),
      ),
      2 => const _ChannelFavoritesView(),
      3 => _PerformanceView(
        settings: provider.playbackSettings,
        onOpenSettings: () => _openPlaybackSettings(context),
      ),
      4 => const _InformationView(),
      _ => const _ProfileComingSoonView(),
    };
  }

  void _openPlaybackSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PlaybackSettingsScreen()));
  }

  Future<void> _openParentalSettings(BuildContext context) async {
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
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
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
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ParentalControlScreen()));
  }
}

class _PremiumSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool compact;

  const _PremiumSidebar({
    required this.selectedIndex,
    required this.onSelected,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? double.infinity : (_androidTvBuild ? 238 : 270),
      color: _proBackground,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TvFullProBrand(),
          const SizedBox(height: 28),
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              'NAVEGACIÓN',
              style: TextStyle(
                color: _proMuted,
                fontSize: 10,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _SidebarItem(
            selected: selectedIndex == 0,
            icon: Icons.grid_view_rounded,
            label: 'Servicios',
            onTap: () => onSelected(0),
          ),
          _SidebarItem(
            selected: selectedIndex == 1,
            icon: Icons.star_rounded,
            label: 'Listas favoritas',
            onTap: () => onSelected(1),
          ),
          _SidebarItem(
            selected: selectedIndex == 2,
            icon: Icons.favorite_rounded,
            label: 'Canales favoritos',
            onTap: () => onSelected(2),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              'TV FULL',
              style: TextStyle(
                color: _proMuted,
                fontSize: 10,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _SidebarItem(
            selected: selectedIndex == 3,
            icon: Icons.workspace_premium_rounded,
            label: 'TV FULL PRO',
            iconColor: _proGold,
            onTap: () => onSelected(3),
          ),
          _SidebarItem(
            selected: selectedIndex == 4,
            icon: Icons.info_outline_rounded,
            label: 'Información',
            onTap: () => onSelected(4),
          ),
          _SidebarItem(
            selected: selectedIndex == 5,
            icon: Icons.account_circle_outlined,
            label: 'Perfil',
            badge: 'PRÓX.',
            onTap: () => onSelected(5),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _proPanel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _proBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: _proBlue, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Interfaz TV FULL PRO',
                    style: TextStyle(
                      color: _proSilver,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final String? badge;

  const _SidebarItem({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? _proBlue.withValues(alpha: 0.13) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: selected
                  ? Border.all(color: _proBlue.withValues(alpha: 0.42))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: iconColor ?? (selected ? _proBlue : _proMuted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? _proText : _proSilver,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _proGold.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _proGold.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: _proGold,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
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

class _TvFullProBrand extends StatelessWidget {
  const _TvFullProBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _TvLogo(size: 56, favorite: true),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFF2F5F8),
                        _proSilver,
                        Color(0xFF737F8F),
                      ],
                    ).createShader(bounds),
                    blendMode: BlendMode.srcIn,
                    child: const Text(
                      'TV FULL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'PRO',
                    style: TextStyle(
                      color: _proGold,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'SERVICE',
                style: TextStyle(
                  color: _proMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TvLogo(size: 38, favorite: true),
        SizedBox(width: 10),
        Text(
          'TV FULL',
          style: TextStyle(
            color: _proSilver,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
        SizedBox(width: 5),
        Text(
          'PRO',
          style: TextStyle(color: _proGold, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _TvLogo extends StatelessWidget {
  final double size;
  final bool favorite;

  const _TvLogo({required this.size, required this.favorite});

  @override
  Widget build(BuildContext context) {
    final borderColor = favorite ? _proGold : _proBlue.withValues(alpha: 0.35);
    final glowColor = favorite ? _proGold : _proBlue;

    return Container(
      width: size,
      height: size * 0.78,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_proBlue, _proBlueDeep],
        ),
        borderRadius: BorderRadius.circular(size * 0.23),
        border: Border.all(color: borderColor, width: favorite ? 2.2 : 1.2),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: favorite ? 0.26 : 0.18),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: size * 0.46,
      ),
    );
  }
}

class _PremiumTopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool showAddButton;
  final VoidCallback onAdd;
  final VoidCallback onParental;
  final VoidCallback onInfo;
  final VoidCallback onProfile;

  const _PremiumTopBar({
    required this.title,
    required this.subtitle,
    required this.showAddButton,
    required this.onAdd,
    required this.onParental,
    required this.onInfo,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: _proBackground,
        border: Border(bottom: BorderSide(color: _proBorder)),
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
                    color: _proText,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _proMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (showAddButton) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _proBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                'Agregar lista',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 14),
          ],
          _TopBarIcon(
            tooltip: 'Control parental',
            icon: Icons.shield_outlined,
            onPressed: onParental,
          ),
          const SizedBox(width: 8),
          _TopBarIcon(
            tooltip: 'Información',
            icon: Icons.info_outline_rounded,
            onPressed: onInfo,
          ),
          const SizedBox(width: 8),
          _TopBarIcon(
            tooltip: 'Perfil · Próximamente',
            icon: Icons.account_circle_outlined,
            onPressed: onProfile,
          ),
        ],
      ),
    );
  }
}

class _TopBarIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _TopBarIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _proPanel,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _proBorder),
            ),
            child: Icon(icon, color: _proSilver, size: 21),
          ),
        ),
      ),
    );
  }
}

class _PlaylistsView extends StatelessWidget {
  final List<Playlist> playlists;
  final bool loading;
  final Set<String> favoriteIds;
  final ValueChanged<Playlist> onToggleFavorite;
  final VoidCallback onAddPlaylist;

  const _PlaylistsView({
    required this.playlists,
    required this.loading,
    required this.favoriteIds,
    required this.onToggleFavorite,
    required this.onAddPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: _proBlue));
    }

    if (playlists.isEmpty) {
      return _EmptyState(
        icon: Icons.playlist_add_rounded,
        title: 'Todavía no hay servicios',
        message: 'Agregá una lista M3U/M3U8, Xtream Codes o Portal Stalker para comenzar.',
        actionLabel: 'Agregar lista',
        onAction: onAddPlaylist,
      );
    }

    final ordered = List<Playlist>.from(playlists)
      ..sort((a, b) {
        final aFavorite = favoriteIds.contains(a.id);
        final bFavorite = favoriteIds.contains(b.id);
        if (aFavorite != bFavorite) return aFavorite ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final totalItems = playlists.fold<int>(
      0,
      (total, item) => total + item.channels.length,
    );
    final totalGroups = playlists.fold<int>(
      0,
      (total, item) => total + item.groups.length,
    );
    final favoriteCount = playlists
        .where((item) => favoriteIds.contains(item.id))
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth >= 900 ? 28 : 18,
            24,
            constraints.maxWidth >= 900 ? 28 : 18,
            42,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ServicesHero(onAddPlaylist: onAddPlaylist),
              const SizedBox(height: 18),
              _StatsStrip(
                services: playlists.length,
                favoriteLists: favoriteCount,
                items: totalItems,
                groups: totalGroups,
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mis listas',
                          style: TextStyle(
                            color: _proText,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tus favoritos aparecen primero.',
                          style: TextStyle(color: _proMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _proPanel,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _proBorder),
                    ),
                    child: Text(
                      '${playlists.length} servicios',
                      style: const TextStyle(
                        color: _proSilver,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              _PlaylistGrid(
                playlists: ordered,
                favoriteIds: favoriteIds,
                onToggleFavorite: onToggleFavorite,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FavoritePlaylistsView extends StatelessWidget {
  final List<Playlist> playlists;
  final bool loading;
  final Set<String> favoriteIds;
  final ValueChanged<Playlist> onToggleFavorite;
  final VoidCallback onAddPlaylist;

  const _FavoritePlaylistsView({
    required this.playlists,
    required this.loading,
    required this.favoriteIds,
    required this.onToggleFavorite,
    required this.onAddPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: _proBlue));
    }

    final favorites =
        playlists
            .where((playlist) => favoriteIds.contains(playlist.id))
            .toList(growable: false)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

    if (favorites.isEmpty) {
      return _EmptyState(
        icon: Icons.star_border_rounded,
        title: 'Todavía no tenés listas favoritas',
        message: 'Tocá la estrella de una lista para destacarla con el contorno dorado.',
        actionLabel: playlists.isEmpty ? 'Agregar lista' : null,
        onAction: playlists.isEmpty ? onAddPlaylist : null,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _proGold.withValues(alpha: 0.13),
                  _proBlue.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _proGold.withValues(alpha: 0.32)),
            ),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, color: _proGold, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '${favorites.length} ${favorites.length == 1 ? 'lista favorita' : 'listas favoritas'}',
                    style: const TextStyle(
                      color: _proText,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const Text(
                  'Contorno dorado activo',
                  style: TextStyle(
                    color: _proGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _PlaylistGrid(
            playlists: favorites,
            favoriteIds: favoriteIds,
            onToggleFavorite: onToggleFavorite,
          ),
        ],
      ),
    );
  }
}

class _ServicesHero extends StatelessWidget {
  final VoidCallback onAddPlaylist;

  const _ServicesHero({required this.onAddPlaylist});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 158),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B2238), Color(0xFF0A1625), _proPanel],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _proBlue.withValues(alpha: 0.32)),
        boxShadow: [
          BoxShadow(
            color: _proBlue.withValues(alpha: 0.08),
            blurRadius: 30,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _proBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _proBlue.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Text(
                        'TV FULL PRO',
                        style: TextStyle(
                          color: _proBlue,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _proGold.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _proGold.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Text(
                        'SERVICE',
                        style: TextStyle(
                          color: _proGold,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Tu entretenimiento.\nTu control.',
                  style: TextStyle(
                    color: _proText,
                    fontSize: 27,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Accedé a tus servicios, organizalos y destacá tus favoritos sin cambiar la reproducción.',
                  style: TextStyle(color: _proMuted, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _TvLogo(size: 94, favorite: true),
              const SizedBox(height: 15),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _proSilver,
                  side: const BorderSide(color: _proBorder),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onAddPlaylist,
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text(
                  'Nuevo servicio',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  final int services;
  final int favoriteLists;
  final int items;
  final int groups;

  const _StatsStrip({
    required this.services,
    required this.favoriteLists,
    required this.items,
    required this.groups,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final width = compact
            ? (constraints.maxWidth - 10) / 2
            : (constraints.maxWidth - 30) / 4;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: width,
              child: _StatCard(
                icon: Icons.dns_rounded,
                value: '$services',
                label: 'Servicios',
                color: _proBlue,
              ),
            ),
            SizedBox(
              width: width,
              child: _StatCard(
                icon: Icons.star_rounded,
                value: '$favoriteLists',
                label: 'Listas favoritas',
                color: _proGold,
              ),
            ),
            SizedBox(
              width: width,
              child: _StatCard(
                icon: Icons.view_list_rounded,
                value: '$items',
                label: 'Elementos',
                color: const Color(0xFF5DD6A8),
              ),
            ),
            SizedBox(
              width: width,
              child: _StatCard(
                icon: Icons.category_rounded,
                value: '$groups',
                label: 'Categorías',
                color: const Color(0xFF9B8CFF),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _proPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _proBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _proText,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _proMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistGrid extends StatelessWidget {
  final List<Playlist> playlists;
  final Set<String> favoriteIds;
  final ValueChanged<Playlist> onToggleFavorite;

  const _PlaylistGrid({
    required this.playlists,
    required this.favoriteIds,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _androidTvBuild
            ? (constraints.maxWidth >= 1180 ? 3 : 2)
            : constraints.maxWidth >= 1250
            ? 3
            : constraints.maxWidth >= 760
            ? 2
            : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: playlists.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: columns == 1 ? 2.8 : 2.25,
          ),
          itemBuilder: (context, index) {
            final playlist = playlists[index];
            return _PlaylistCard(
              playlist: playlist,
              isFavorite: favoriteIds.contains(playlist.id),
              onToggleFavorite: () => onToggleFavorite(playlist),
            );
          },
        );
      },
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const _PlaylistCard({
    required this.playlist,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  Future<void> _openPlaylist(BuildContext context) async {
    final navigator = Navigator.of(context);
    await ParentalControlService.instance.init();
    if (!context.mounted) return;

    await ArtworkCacheService.instance.switchProvider(playlist.id);
    if (!context.mounted) return;

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => SourceContentScreen(playlist: playlist),
      ),
    );
  }

  Future<void> _editPlaylist(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditSourceScreen(playlist: playlist)),
    );
  }

  Future<void> _refreshPlaylist(BuildContext context) async {
    final provider = context.read<IptvProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await provider.refreshPlaylist(playlist.id);
    if (!context.mounted) return;
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

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _openPlaylist(context),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                isFavorite
                    ? _proGold.withValues(alpha: 0.055)
                    : _proBlue.withValues(alpha: 0.035),
                _proPanel,
                _proPanelSoft,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isFavorite ? _proGold.withValues(alpha: 0.46) : _proBorder,
              width: isFavorite ? 1.35 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (isFavorite ? _proGold : _proBlue).withValues(
                  alpha: 0.055,
                ),
                blurRadius: 18,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TvLogo(size: 60, favorite: isFavorite),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _proText,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _proBlue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _proBlue.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Text(
                                playlist.sourceType.label,
                                style: const TextStyle(
                                  color: _proBlue,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Tooltip(
                      message: isFavorite
                          ? 'Quitar de listas favoritas'
                          : 'Agregar a listas favoritas',
                      child: IconButton(
                        onPressed: onToggleFavorite,
                        icon: Icon(
                          isFavorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: isFavorite ? _proGold : _proMuted,
                          size: 23,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Opciones',
                      iconColor: _proMuted,
                      onSelected: (value) async {
                        switch (value) {
                          case 'edit':
                            await _editPlaylist(context);
                            break;
                          case 'refresh':
                            await _refreshPlaylist(context);
                            break;
                          case 'delete':
                            await provider.removePlaylist(playlist.id);
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined),
                              SizedBox(width: 10),
                              Text('Editar lista'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'refresh',
                          enabled: playlist.isRemote,
                          child: const Row(
                            children: [
                              Icon(Icons.refresh_rounded),
                              SizedBox(width: 10),
                              Text('Actualizar lista'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
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
                const Spacer(),
                Row(
                  children: [
                    const Icon(
                      Icons.playlist_play_rounded,
                      color: _proMuted,
                      size: 17,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${playlist.channels.length} elementos',
                      style: const TextStyle(
                        color: _proSilver,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 14),
                    if (playlist.groups.isNotEmpty) ...[
                      const Icon(
                        Icons.category_outlined,
                        color: _proMuted,
                        size: 15,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${playlist.groups.length} categorías',
                        style: const TextStyle(
                          color: _proSilver,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: _proBlue,
                      size: 18,
                    ),
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

class _ChannelFavoritesView extends StatelessWidget {
  const _ChannelFavoritesView();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final parental = ParentalControlService.instance;
    final favorites = parental.enabled && parental.isLocked
        ? provider.favorites
              .where(parental.canShowChannel)
              .toList(growable: false)
        : provider.favorites;

    if (favorites.isEmpty) {
      return const _EmptyState(
        icon: Icons.favorite_border_rounded,
        title: 'Sin canales favoritos',
        message: 'Marcá tus canales preferidos para encontrarlos acá.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 42),
      itemCount: favorites.length,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (context, index) {
        final channel = favorites[index];
        return Material(
          color: _proPanel,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            onTap: () => PlayerRouteGuard.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  channel: channel,
                  playlist: favorites,
                  initialIndex: index,
                  settings: provider.playbackSettings,
                ),
              ),
            ),
            borderRadius: BorderRadius.circular(15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: _proBorder),
              ),
              child: Row(
                children: [
                  _ChannelLogo(channel: channel),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _proText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (channel.group != null)
                          Text(
                            channel.group!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _proMuted,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    color: _proBlue,
                    size: 29,
                  ),
                ],
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
    BufferProfile.slowConnection => 'Conexión lenta',
    BufferProfile.custom => 'Personalizado',
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 42),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _proGold.withValues(alpha: 0.13),
                  _proPanel,
                  _proBlue.withValues(alpha: 0.07),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _proGold.withValues(alpha: 0.34)),
            ),
            child: Row(
              children: [
                const _TvLogo(size: 78, favorite: true),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'TV FULL',
                            style: TextStyle(
                              color: _proSilver,
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'PRO',
                            style: TextStyle(
                              color: _proGold,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Rendimiento avanzado',
                        style: TextStyle(
                          color: _proText,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Tus opciones de rendimiento actuales, presentadas dentro de la experiencia PRO.',
                        style: TextStyle(
                          color: _proMuted,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _proGold.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _proGold.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'PRO',
                    style: TextStyle(
                      color: _proGold,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _proPanel,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _proBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed_rounded, color: _proBlue, size: 27),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Perfil actual · $_profileLabel',
                        style: const TextStyle(
                          color: _proText,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
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
                      value:
                          '${settings.readaheadSeconds.toStringAsFixed(1)} s',
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
                  style: FilledButton.styleFrom(
                    backgroundColor: _proBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text(
                    'Configurar rendimiento',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _proPanelSoft,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _proBorder),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11),
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(
                color: _proMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: _proText,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InformationView extends StatelessWidget {
  const _InformationView();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLead(
            icon: Icons.info_outline_rounded,
            title: 'Información de TV FULL PRO',
            message: 'Este espacio queda preparado para comunicar novedades, versiones y futuras actualizaciones.',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: const [
              _InfoCard(
                icon: Icons.system_update_alt_rounded,
                title: 'Centro de actualizaciones',
                message: 'Acá se mostrarán nuevas versiones, cambios importantes y avisos de actualización.',
                accent: _proBlue,
              ),
              _InfoCard(
                icon: Icons.newspaper_rounded,
                title: 'Novedades',
                message: 'Un lugar para informar mejoras de rendimiento, nuevas funciones y cambios de la aplicación.',
                accent: Color(0xFF9B8CFF),
              ),
              _InfoCard(
                icon: Icons.verified_user_outlined,
                title: 'Seguridad',
                message: 'Acceso rápido a información relacionada con privacidad, control parental y uso seguro.',
                accent: Color(0xFF5DD6A8),
              ),
              _InfoCard(
                icon: Icons.workspace_premium_outlined,
                title: 'TV FULL PRO',
                message: 'Las funciones premium y de rendimiento estarán identificadas con el distintivo dorado PRO.',
                accent: _proGold,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileComingSoonView extends StatelessWidget {
  const _ProfileComingSoonView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: _proPanel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _proBorder),
          boxShadow: [
            BoxShadow(color: _proBlue.withValues(alpha: 0.06), blurRadius: 30),
          ],
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TvLogo(size: 88, favorite: true),
            SizedBox(height: 24),
            Text(
              'Perfiles',
              style: TextStyle(
                color: _proText,
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'PRÓXIMAMENTE',
              style: TextStyle(
                color: _proGold,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'La interfaz ya reserva este espacio para una futura experiencia de perfiles. No hay ninguna función activa todavía.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _proMuted, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLead extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _SectionLead({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_proBlue.withValues(alpha: 0.09), _proPanel],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _proBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _proBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _proBlue, size: 25),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _proText,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: const TextStyle(
                    color: _proMuted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color accent;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 310,
      constraints: const BoxConstraints(minHeight: 165),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _proPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _proBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(height: 15),
          Text(
            title,
            style: const TextStyle(
              color: _proText,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            style: const TextStyle(
              color: _proMuted,
              fontSize: 11,
              height: 1.45,
            ),
          ),
        ],
      ),
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
      return const CircleAvatar(
        backgroundColor: _proPanelSoft,
        child: Icon(Icons.tv_rounded, color: _proBlue),
      );
    }

    return CircleAvatar(
      backgroundColor: _proPanelSoft,
      child: ClipOval(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CachedArtworkImage(
            url: logo,
            fit: BoxFit.contain,
            cacheWidth: 80,
            fallback: const Icon(Icons.tv_rounded, color: _proBlue),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: _proPanel,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _proBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _proBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 32, color: _proBlue),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _proText,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _proMuted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _proBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
