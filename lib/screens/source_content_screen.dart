import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../providers/iptv_provider.dart';
import '../services/manual_playlist_refresh_service.dart';
import '../services/parental_control_service.dart';
import '../widgets/parental_unlock_dialog.dart';
import '../widgets/tv_full_premium_ui.dart';
import 'parental_control_screen.dart';
import 'xtream_live_screen.dart';
import 'xtream_movies_screen.dart';
import 'xtream_series_screen.dart';

/// Raíz de contenido de TV FULL PRO V39.
///
/// No existe pantalla Inicio: al terminar la carga de la lista se entra directo
/// a TV en Vivo y se abre la vista teatro con el primer canal disponible.
class SourceContentScreen extends StatefulWidget {
  final Playlist playlist;

  const SourceContentScreen({super.key, required this.playlist});

  @override
  State<SourceContentScreen> createState() => _SourceContentScreenState();
}

class _SourceContentScreenState extends State<SourceContentScreen> {
  final ParentalControlService _parental = ParentalControlService.instance;
  bool _refreshingLists = false;
  bool _openingSection = false;
  DateTime? _lastBackPressedAt;

  @override
  void initState() {
    super.initState();
    _parental.addListener(_refresh);
    unawaited(_parental.init());
  }

  @override
  void dispose() {
    _parental.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final active = provider.selectedPlaylist ?? widget.playlist;

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleRootBack());
      },
      child: Scaffold(
        backgroundColor: tvFullBackground,
        body: XtreamLiveScreen(
          key: ValueKey('root-live:${active.id}|${active.source}'),
          playlist: active,
          autoOpenFirstChannel: true,
          onChangeList: provider.hasMultiplePlaylists
              ? () => unawaited(_choosePlaylist(context))
              : null,
          onRefreshLists:
              _refreshingLists ? null : () => unawaited(_refreshLists()),
          onParentalControl: () => unawaited(_handleParentalLock()),
          onSectionRequested: (section) =>
              unawaited(_openNamedSection(active, section)),
        ),
      ),
    );
  }

  Future<void> _openNamedSection(Playlist playlist, String section) async {
    if (section == 'live' || _openingSection) return;
    _openingSection = true;
    try {
      Widget? screen;
      switch (section) {
        case 'movies':
          screen = XtreamMoviesScreen(
            playlist: playlist,
            onSectionRequested: (next) =>
                unawaited(_replaceSection(playlist, next)),
            onChangeList: context.read<IptvProvider>().hasMultiplePlaylists
                ? () => unawaited(_changeListFromSection())
                : null,
            onRefreshLists: () => unawaited(_refreshLists()),
            onParentalControl: () => unawaited(_handleParentalLock()),
          );
          break;
        case 'series':
          screen = XtreamSeriesScreen(
            playlist: playlist,
            onSectionRequested: (next) =>
                unawaited(_replaceSection(playlist, next)),
            onChangeList: context.read<IptvProvider>().hasMultiplePlaylists
                ? () => unawaited(_changeListFromSection())
                : null,
            onRefreshLists: () => unawaited(_refreshLists()),
            onParentalControl: () => unawaited(_handleParentalLock()),
          );
          break;
        case 'sports':
          screen = XtreamLiveScreen(
            playlist: playlist,
            title: 'DEPORTES',
            sportsPresentation: true,
            onChangeList: context.read<IptvProvider>().hasMultiplePlaylists
                ? () => unawaited(_changeListFromSection())
                : null,
            onRefreshLists: () => unawaited(_refreshLists()),
            onParentalControl: () => unawaited(_handleParentalLock()),
            filterKeywords: const [
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
              'motor',
              'racing',
              'mma',
              'boxeo',
            ],
            autoOpenFirstChannel: false,
            onSectionRequested: (next) =>
                unawaited(_replaceSection(playlist, next)),
          );
          break;
        case 'kids':
          screen = XtreamLiveScreen(
            playlist: playlist,
            title: 'INFANTILES',
            onChangeList: context.read<IptvProvider>().hasMultiplePlaylists
                ? () => unawaited(_changeListFromSection())
                : null,
            onRefreshLists: () => unawaited(_refreshLists()),
            onParentalControl: () => unawaited(_handleParentalLock()),
            filterKeywords: const [
              'infantil',
              'infantiles',
              'kids',
              'kid',
              'niños',
              'ninos',
              'cartoon',
              'dibujos',
              'disney',
              'nick',
              'boomerang',
            ],
            autoOpenFirstChannel: true,
            onSectionRequested: (next) =>
                unawaited(_replaceSection(playlist, next)),
          );
          break;
        case 'adults':
          if (!await _unlockAdultsIfNeeded()) return;
          screen = XtreamLiveScreen(
            playlist: playlist,
            title: 'ADULTOS',
            onChangeList: context.read<IptvProvider>().hasMultiplePlaylists
                ? () => unawaited(_changeListFromSection())
                : null,
            onRefreshLists: () => unawaited(_refreshLists()),
            onParentalControl: () => unawaited(_handleParentalLock()),
            filterKeywords: const [
              'adult',
              'adulto',
              'adultos',
              'xxx',
              '18+',
              '+18',
              'erotic',
              'erotico',
              'erótica',
              'erotica',
            ],
            autoOpenFirstChannel: true,
            onSectionRequested: (next) =>
                unawaited(_replaceSection(playlist, next)),
          );
          break;
      }

      if (screen != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen!),
        );
      }
    } finally {
      _openingSection = false;
    }
  }

  Future<void> _replaceSection(Playlist playlist, String section) async {
    if (!mounted) return;
    _openingSection = false;
    Navigator.of(context).pop();
    await Future<void>.delayed(Duration.zero);
    if (mounted) await _openNamedSection(playlist, section);
  }

  Future<void> _changeListFromSection() async {
    if (!mounted) return;
    final provider = context.read<IptvProvider>();
    if (!provider.hasMultiplePlaylists) return;
    await _choosePlaylist(context);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
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

  Future<void> _handleParentalLock() async {
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
      await ManualPlaylistRefreshService.instance.refresh(active);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Lista actualizada correctamente.')),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo actualizar la lista. Revisá la conexión e intentá de nuevo.',
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
        backgroundColor: Colors.transparent,
        child: Container(
          width: 560,
          constraints: const BoxConstraints(maxHeight: 520),
          padding: const EdgeInsets.all(20),
          decoration: tvFullGlassDecoration(radius: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cambio de lista',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
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
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        autofocus:
                            selected || (currentId == null && index == 0),
                        selected: selected,
                        selectedTileColor: tvFullBlue.withValues(alpha: .20),
                        focusColor: tvFullBlue.withValues(alpha: .20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                          side: BorderSide(
                            color: selected
                                ? tvFullCyan.withValues(alpha: .45)
                                : Colors.transparent,
                          ),
                        ),
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: selected
                            ? const Icon(Icons.check_rounded, color: tvFullCyan)
                            : null,
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
    );
    if (chosen != null) await provider.selectPlaylist(chosen);
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
