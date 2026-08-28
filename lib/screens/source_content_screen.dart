import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../providers/iptv_provider.dart';
import '../services/app_update_service.dart';
import '../services/parental_control_service.dart';
import '../widgets/parental_lock_button.dart';
import '../widgets/parental_unlock_dialog.dart';
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

class _SourceContentScreenState extends State<SourceContentScreen> {
  final ParentalControlService _parental = ParentalControlService.instance;
  final AppUpdateService _updates = AppUpdateService.instance;

  @override
  void initState() {
    super.initState();
    _parental.addListener(_refresh);
    _updates.addListener(_refresh);
    unawaited(_parental.init());
    unawaited(_updates.checkOnce());
  }

  @override
  void dispose() {
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

    return Scaffold(
      backgroundColor: const Color(0xFF05090F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(42, 26, 42, 34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'TV FULL PRO',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  ParentalLockButton(
                    unlocked: !_parental.enabled || _parental.isUnlocked,
                    hiddenCategoryCount: 0,
                    onPressed: () => unawaited(_handleParentalLock()),
                  ),
                  const SizedBox(width: 8),
                  if (provider.hasMultiplePlaylists)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_choosePlaylist(context)),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                      label: const Text('Cambiar lista'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                active.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (update != null) ...[
                const SizedBox(height: 14),
                _UpdateBanner(
                  versionName: update.versionName,
                  onUpdate: () => unawaited(_openUpdate()),
                ),
              ],
              const Spacer(flex: 2),
              const Text(
                '¿Qué querés ver?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 22),
              Expanded(
                flex: 9,
                child: Row(
                  children: [
                    Expanded(
                      child: _SectionButton(
                        autofocus: true,
                        eyebrow: 'EN DIRECTO',
                        title: 'TV EN VIVO',
                        icon: Icons.live_tv_rounded,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => XtreamLiveScreen(playlist: active),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _SectionButton(
                        eyebrow: 'CATÁLOGO',
                        title: 'PELÍCULAS',
                        icon: Icons.movie_outlined,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                XtreamMoviesScreen(playlist: active),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _SectionButton(
                        eyebrow: 'TEMPORADAS',
                        title: 'SERIES',
                        icon: Icons.video_library_outlined,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                XtreamSeriesScreen(playlist: active),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
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
      title: 'Desbloquear contenido para adultos',
    );
  }

  Future<void> _openUpdate() async {
    final opened = await _updates.openUpdate();
    if (!mounted || opened) return;
    final code = _updates.availableUpdate?.downloaderCode ?? '';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            code.isEmpty
                ? 'No se pudo abrir el enlace de actualización.'
                : 'No se pudo abrir Downloader. Código: $code',
          ),
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
                  'Mejor rendimiento · versión $versionName',
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
              'ACTUALIZAR',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionButton extends StatefulWidget {
  final String eyebrow;
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool autofocus;

  const _SectionButton({
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_SectionButton> createState() => _SectionButtonState();
}

class _SectionButtonState extends State<_SectionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _focused ? 1.025 : 1,
      duration: const Duration(milliseconds: 120),
      child: Material(
        color: _focused ? const Color(0xFF122A40) : const Color(0xFF0B1622),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(18),
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(widget.icon, size: 34, color: const Color(0xFF58B9FF)),
                const Spacer(),
                Text(
                  widget.eyebrow,
                  style: const TextStyle(
                    color: Color(0x73FFFFFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
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
