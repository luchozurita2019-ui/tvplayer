import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../providers/iptv_provider.dart';
import '../services/app_update_service.dart';
import '../services/manual_playlist_refresh_service.dart';
import '../services/parental_control_service.dart';
import '../widgets/app_version_badge.dart';
import '../widgets/parental_unlock_dialog.dart';
import 'filtered_live_screen.dart';
import 'parental_control_screen.dart';
import 'tv_full_dashboard_screen.dart';
import 'xtream_live_screen.dart';
import 'xtream_movies_screen.dart';
import 'xtream_series_screen.dart';

class SourceContentScreen extends StatefulWidget {
  final Playlist playlist;

  const SourceContentScreen({super.key, required this.playlist});

  @override
  State<SourceContentScreen> createState() => _SourceContentScreenState();
}

class _SourceContentScreenState extends State<SourceContentScreen>
    with WidgetsBindingObserver {
  final ParentalControlService _parental = ParentalControlService.instance;
  final AppUpdateService _updates = AppUpdateService.instance;

  Timer? _updatePollTimer;
  DateTime? _lastBackPressedAt;
  bool _refreshingLists = false;
  bool _openingSection = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _parental.addListener(_refresh);
    _updates.addListener(_refresh);
    unawaited(_parental.init());
    unawaited(_updates.checkOnce(force: true));
    _updatePollTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_updates.checkOnce(force: true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_updates.checkOnce(force: true));
    }
  }

  @override
  void dispose() {
    _updatePollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _parental.removeListener(_refresh);
    _updates.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final active = provider.selectedPlaylist ?? widget.playlist;
    final update = _updates.availableUpdate;

    final actions = <TvFullDashboardAction>[
      if (provider.hasMultiplePlaylists)
        TvFullDashboardAction(
          icon: Icons.swap_horiz_rounded,
          tooltip: 'Cambiar lista',
          onPressed: () => unawaited(_choosePlaylist(context)),
        ),
      TvFullDashboardAction(
        icon: Icons.refresh_rounded,
        tooltip: _refreshingLists ? 'Actualizando listas' : 'Actualizar listas',
        onPressed: _refreshingLists ? null : () => unawaited(_refreshLists()),
        child: _refreshingLists
            ? const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Color(0xFF54D7FF),
                ),
              )
            : null,
      ),
      TvFullDashboardAction(
        icon: _parental.enabled && _parental.isLocked
            ? Icons.lock_rounded
            : Icons.lock_open_rounded,
        tooltip: _parental.enabled && _parental.isLocked
            ? 'Desbloquear control parental'
            : 'Control parental',
        onPressed: () => unawaited(_handleParentalControl()),
      ),
      if (update != null)
        TvFullDashboardAction(
          icon: Icons.system_update_alt_rounded,
          tooltip: 'Actualizar a ${update.versionName}',
          onPressed: () => unawaited(_openUpdate()),
        ),
    ];

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleRootBack());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF050B14),
        body: TvFullDashboardScreen(
          key: ValueKey('${active.id}|${active.source}'),
          playlistName: active.name,
          actions: actions,
          footer: const AppVersionBadge(),
          onOpenSection: (section) => unawaited(_openSection(active, section)),
        ),
      ),
    );
  }

  Future<void> _openSection(
    Playlist playlist,
    TvFullDashboardSection section,
  ) async {
    if (_openingSection) return;
    _openingSection = true;
    try {
      Widget screen;
      switch (section) {
        case TvFullDashboardSection.live:
          screen = XtreamLiveScreen(playlist: playlist);
          break;
        case TvFullDashboardSection.movies:
          screen = XtreamMoviesScreen(playlist: playlist);
          break;
        case TvFullDashboardSection.series:
          screen = XtreamSeriesScreen(playlist: playlist);
          break;
        case TvFullDashboardSection.sports:
          screen = FilteredLiveScreen(
            playlist: playlist,
            title: 'DEPORTES',
            icon: Icons.sports_soccer_rounded,
            keywords: const [
              'deporte',
              'sport',
              'futbol',
              'fútbol',
              'football',
              'soccer',
              'liga',
              'copa',
              'champion',
              'tenis',
              'tennis',
              'basket',
              'racing',
              'motor',
            ],
          );
          break;
        case TvFullDashboardSection.kids:
          screen = FilteredLiveScreen(
            playlist: playlist,
            title: 'INFANTILES',
            icon: Icons.child_care_rounded,
            keywords: const [
              'infantil',
              'infantiles',
              'kids',
              'kid',
              'niños',
              'ninos',
              'niño',
              'nino',
              'cartoon',
              'dibujos',
              'disney',
              'nick',
              'boomerang',
            ],
          );
          break;
        case TvFullDashboardSection.adults:
          if (!await _unlockAdultsIfNeeded()) return;
          screen = FilteredLiveScreen(
            playlist: playlist,
            title: 'ADULTOS',
            icon: Icons.lock_rounded,
            requireParentalUnlock: true,
            keywords: const [
              'adult',
              'adulto',
              'adultos',
              'xxx',
              '18+',
              '+18',
              'porno',
              'porn',
              'erotic',
              'erotico',
              'erótica',
              'erotica',
              'playboy',
              'hentai',
            ],
          );
          break;
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => screen),
      );
    } finally {
      _openingSection = false;
    }
  }

  Future<bool> _unlockAdultsIfNeeded() async {
    await _parental.init();
    if (!mounted) return false;

    if (!_parental.pinConfigured || !_parental.enabled) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ParentalControlScreen()),
      );
      if (!mounted || !_parental.pinConfigured || !_parental.enabled) {
        return false;
      }
    }

    if (_parental.isUnlocked) return true;
    return requestParentalUnlock(
      context,
      title: 'Contenido para adultos',
    );
  }

  Future<void> _handleParentalControl() async {
    await _parental.init();
    if (!mounted) return;

    if (!_parental.pinConfigured || !_parental.enabled) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ParentalControlScreen()),
      );
      return;
    }

    if (_parental.isUnlocked) {
      _parental.lockNow();
      return;
    }

    await requestParentalUnlock(
      context,
      title: 'Desbloquear control parental',
    );
  }

  Future<void> _refreshLists() async {
    if (_refreshingLists) return;
    setState(() => _refreshingLists = true);
    try {
      final provider = context.read<IptvProvider>();
      final selectedId = provider.selectedPlaylistId ?? widget.playlist.id;
      if (provider.remoteProvisioningSupported) {
        await provider.syncRemoteServices();
      }
      final active = provider.playlistById(selectedId) ??
          provider.selectedPlaylist ??
          widget.playlist;
      final refreshResult =
          await ManualPlaylistRefreshService.instance.refresh(active);
      if (!mounted) return;
      final message = refreshResult.isPartial
          ? 'Actualización parcial. No se pudo actualizar: '
              '${refreshResult.failedSectionNames.join(', ')}.'
          : 'Actualización de listas completada.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudieron actualizar las listas. Revisá la conexión e intentá de nuevo.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _refreshingLists = false);
    }
  }

  Future<void> _choosePlaylist(BuildContext context) async {
    final provider = context.read<IptvProvider>();
    final currentId = provider.selectedPlaylistId;
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF08111C),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cambiar lista',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: provider.playlists.length,
                    itemBuilder: (context, index) {
                      final item = provider.playlists[index];
                      final selected = item.id == currentId;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          autofocus:
                              selected || (currentId == null && index == 0),
                          selected: selected,
                          selectedTileColor:
                              const Color(0xFF2D8CFF).withValues(alpha: .16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            item.sourceType.name.toUpperCase(),
                            style: const TextStyle(color: Colors.white38),
                          ),
                          trailing:
                              selected ? const Icon(Icons.check_rounded) : null,
                          onTap: () => Navigator.of(dialogContext).pop(item.id),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (chosen != null) await provider.selectPlaylist(chosen);
  }

  Future<void> _openUpdate() async {
    final openedInstaller = await _updates.openInstaller();
    if (openedInstaller) return;

    final update = _updates.availableUpdate;
    final code = update?.downloaderCode ?? '';
    if (!mounted) return;
    if (code.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No hay una actualización válida.')),
        );
      return;
    }

    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF08111C),
        title: const Text('Actualizar TV FULL PRO'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nueva versión ${update?.versionName ?? ''}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            const Text(
              'Código para Downloader',
              style: TextStyle(color: Colors.white38),
            ),
            const SizedBox(height: 7),
            SelectableText(
              code,
              style: const TextStyle(
                color: Color(0xFF54D7FF),
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRootBack() async {
    final now = DateTime.now();
    final previous = _lastBackPressedAt;
    if (previous != null &&
        now.difference(previous) <= const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }
    _lastBackPressedAt = now;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('Presioná Atrás nuevamente para salir de TV FULL PRO.'),
        ),
      );
  }
}
