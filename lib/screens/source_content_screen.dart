import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../providers/iptv_provider.dart';
import '../services/app_update_service.dart';
import '../services/artwork_cache_service.dart';
import '../services/section_catalog_service.dart';
import '../services/manual_playlist_refresh_service.dart';
import '../services/parental_control_service.dart';
import '../services/xtream_fast_catalog_service.dart';
import '../widgets/app_version_badge.dart';
import '../widgets/tv_cinematic_home.dart';
import '../widgets/parental_unlock_dialog.dart';
import '../widgets/tv_full_premium_ui.dart';
import 'parental_control_screen.dart';
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
  bool _refreshingLists = false;
  DateTime? _lastBackPressedAt;
  List<CinematicTile> _homeItems = const [];
  String? _homeSourceKey;
  int _homeGeneration = 0;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active =
        context.watch<IptvProvider>().selectedPlaylist ?? widget.playlist;
    final key = '${active.id}|${active.source}';
    if (_homeSourceKey == key) return;
    _homeSourceKey = key;
    _homeItems = const [];
    unawaited(_loadHomeArtwork(active));
  }

  Future<void> _loadHomeArtwork(Playlist playlist) async {
    final generation = ++_homeGeneration;
    final tiles = <CinematicTile>[];
    try {
      await _parental.init();
      if (!mounted || generation != _homeGeneration) return;
      await ArtworkCacheService.instance.switchProvider(playlist.id);
      if (!mounted || generation != _homeGeneration) return;
      // Cached catalogs only: entering Home never downloads the full provider.
      if (playlist.sourceType == PlaylistSourceType.xtream) {
        final service = XtreamFastCatalogService.instance;
        final movies = await service.loadCachedMovies(playlist.source);
        if (!mounted || generation != _homeGeneration) return;
        for (final movie in movies?.movies ?? []) {
          if (!_parental.canShowItem(name: movie.name, group: movie.category)) {
            continue;
          }
          tiles.add(
            CinematicTile(
              id: 'movie:${movie.id}',
              title: movie.name,
              imageUrl: movie.cover,
              category: movie.category,
              section: CinematicSection.movies,
            ),
          );
          if (tiles.length >= 6) break;
        }
        final series = await service.loadCachedSeries(playlist.source);
        if (!mounted || generation != _homeGeneration) return;
        var count = 0;
        for (final item in series?.series ?? []) {
          if (!_parental.canShowItem(name: item.name, group: item.category)) {
            continue;
          }
          tiles.add(
            CinematicTile(
              id: 'series:${item.id}',
              title: item.name,
              imageUrl:
                  item.backdrops.isNotEmpty ? item.backdrops.first : item.cover,
              category: item.category,
              section: CinematicSection.series,
            ),
          );
          if (++count >= 6) break;
        }
      } else {
        for (final kind in [TvSectionKind.movies, TvSectionKind.series]) {
          final cached = await SectionCatalogService.instance.loadCached(
            playlist,
            kind,
          );
          if (!mounted || generation != _homeGeneration) return;
          var count = 0;
          for (final channel in cached?.channels ?? []) {
            if (!_parental.canShowChannel(channel)) continue;
            tiles.add(
              CinematicTile(
                id: '${kind.name}:${channel.uniqueKey}',
                title: channel.name,
                imageUrl: channel.logoUrl,
                category: channel.group,
                section: kind == TvSectionKind.movies
                    ? CinematicSection.movies
                    : CinematicSection.series,
              ),
            );
            if (++count >= 6) break;
          }
        }
      }
    } catch (_) {
      // Section shortcuts stay available when a cached catalog cannot be read.
    }
    if (!mounted || generation != _homeGeneration) return;
    // Alternate movies and series so both sections appear above the fold.
    final movies =
        tiles.where((t) => t.section == CinematicSection.movies).toList();
    final series =
        tiles.where((t) => t.section == CinematicSection.series).toList();
    final ordered = <CinematicTile>[];
    for (var i = 0; i < 6; i++) {
      if (i < movies.length) ordered.add(movies[i]);
      if (i < series.length) ordered.add(series[i]);
    }
    setState(() => _homeItems = ordered);
  }

  Future<void> _openSection(
    Playlist playlist,
    CinematicSection section, {
    String initialQuery = '',
  }) async {
    if (_openingSection) return;
    _openingSection = true;
    try {
      final screen = switch (section) {
        CinematicSection.live => XtreamLiveScreen(playlist: playlist),
        CinematicSection.series => XtreamSeriesScreen(
            playlist: playlist,
            initialQuery: initialQuery,
          ),
        _ => XtreamMoviesScreen(playlist: playlist, initialQuery: initialQuery),
      };
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => screen));
    } finally {
      _openingSection = false;
      if (mounted) {
        final active =
            context.read<IptvProvider>().selectedPlaylist ?? widget.playlist;
        unawaited(_loadHomeArtwork(active));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final active = provider.selectedPlaylist ?? widget.playlist;
    final update = _updates.availableUpdate;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleRootBack());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF08090B),
        body: SafeArea(
          child: TvCinematicHome(
            key: ValueKey(_homeSourceKey),
            playlistName: active.name,
            items: _homeItems
                .where(
                  (item) => _parental.canShowItem(
                    name: item.title,
                    group: item.category,
                  ),
                )
                .toList(growable: false),
            onOpenSection: (section) =>
                unawaited(_openSection(active, section)),
            onOpenItem: (item) => unawaited(
              _openSection(active, item.section, initialQuery: item.title),
            ),
            actions: [
              IconButton(
                tooltip: 'Control parental',
                onPressed: () => unawaited(_handleParentalLock()),
                icon: Icon(
                  !_parental.enabled || _parental.isUnlocked
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline,
                ),
              ),
              IconButton(
                tooltip:
                    _refreshingLists ? 'Actualizando…' : 'Actualizar listas',
                onPressed:
                    _refreshingLists ? null : () => unawaited(_refreshLists()),
                icon: _refreshingLists
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              if (provider.hasMultiplePlaylists)
                IconButton(
                  tooltip: 'Cambiar lista',
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: () => unawaited(_choosePlaylist(context)),
                ),
              if (MediaQuery.sizeOf(context).width >= 900) ...[
                const SizedBox(width: 20),
                const TvFullClock(),
              ],
            ],
            notice: update == null
                ? null
                : _UpdateBanner(
                    versionName: update.versionName,
                    onUpdate: () => unawaited(_openUpdate()),
                  ),
            footer: const Align(
              alignment: Alignment.centerRight,
              child: AppVersionBadge(),
            ),
          ),
        ),
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
      await ManualPlaylistRefreshService.instance.refresh(active);
      if (mounted) unawaited(_loadHomeArtwork(active));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Listas actualizadas correctamente.')),
        );
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

  Future<void> _handleParentalLock() async {
    await _parental.init();
    if (!mounted) return;

    if (!_parental.pinConfigured || !_parental.enabled) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ParentalControlScreen()));
      return;
    }

    if (_parental.isUnlocked) {
      _parental.lockNow();
      return;
    }

    await requestParentalUnlock(
      context,
      title: 'Desbloquear contenido para adultos',
    );
  }

  Future<void> _openUpdate() async {
    final openedInstaller = await _updates.openInstaller();
    if (openedInstaller) return;

    final update = _updates.availableUpdate;
    final code = update?.downloaderCode ?? '';
    if (code.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No hay un código de actualización válido.'),
          ),
        );
      return;
    }

    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0C141E),
        title: const Row(
          children: [
            Icon(Icons.system_update_alt_rounded, color: Color(0xFF58B9FF)),
            SizedBox(width: 10),
            Text('Actualizar TV FULL PRO'),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nueva versión ${update?.versionName ?? ''}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              const Text(
                'Código para Downloader',
                style: TextStyle(fontSize: 13, color: Colors.white54),
              ),
              const SizedBox(height: 6),
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  color: Color(0xFF58B9FF),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'TV FULL Installer no está instalado. El código ya quedó copiado. Abrí Downloader e ingresalo para instalar el actualizador. '
                'TV FULL PRO ya no envía el enlace directamente a Downloader, '
                'evitando que la aplicación se abra y se cierre sola.',
                style: TextStyle(color: Colors.white60, height: 1.35),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('Código copiado.')),
                  );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar código'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _choosePlaylist(BuildContext context) async {
    final provider = context.read<IptvProvider>();
    final currentId = provider.selectedPlaylistId;
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF0C141E),
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
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
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
                              const Color(0xFF1677FF).withValues(alpha: .18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
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
}

class _UpdateBanner extends StatelessWidget {
  final String versionName;
  final VoidCallback onUpdate;

  const _UpdateBanner({required this.versionName, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFFF626B);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: red.withValues(alpha: .075),
        border: Border.all(color: red.withValues(alpha: .38)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_alt_rounded, color: red, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ACTUALIZACIÓN DISPONIBLE',
                  style: TextStyle(
                    color: red,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .45,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Nueva versión $versionName · Presioná para abrir TV FULL Installer.',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onUpdate,
            style: OutlinedButton.styleFrom(
              foregroundColor: red,
              side: const BorderSide(color: red),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              'INSTALAR ACTUALIZACIÓN',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
