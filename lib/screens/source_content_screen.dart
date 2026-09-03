import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../providers/iptv_provider.dart';
import '../services/app_update_service.dart';
import '../services/device_performance_service.dart';
import '../services/parental_control_service.dart';
import '../services/xtream_fast_catalog_service.dart';
import '../widgets/app_version_badge.dart';
import '../widgets/parental_lock_button.dart';
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TvFullPremiumBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(52, 32, 52, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TV FULL PRO',
                            style: TextStyle(
                              fontSize: 38,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.15,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: tvFullBlue,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  active.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ParentalLockButton(
                      unlocked: !_parental.enabled || _parental.isUnlocked,
                      hiddenCategoryCount: 0,
                      onPressed: () => unawaited(_handleParentalLock()),
                    ),
                    const SizedBox(width: 8),
                    if (provider.hasMultiplePlaylists) ...[
                      OutlinedButton.icon(
                        onPressed: () => unawaited(_choosePlaylist(context)),
                        icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                        label: const Text('Cambiar lista'),
                      ),
                      const SizedBox(width: 18),
                    ] else
                      const SizedBox(width: 18),
                    const TvFullClock(),
                  ],
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
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  flex: 10,
                  child: Row(
                    children: [
                      Expanded(
                        child: _SectionButton(
                          autofocus: true,
                          eyebrow: 'EN DIRECTO',
                          title: 'TV EN VIVO',
                          subtitle: 'Disfrutá de la mejor programación en vivo',
                          icon: Icons.live_tv_rounded,
                          accent: tvFullCyan,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  XtreamLiveScreen(playlist: active),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 26),
                      Expanded(
                        child: _SectionButton(
                          eyebrow: 'CATÁLOGO',
                          title: 'PELÍCULAS',
                          subtitle:
                              'Miles de películas para ver cuando quieras',
                          icon: Icons.movie_outlined,
                          accent: tvFullViolet,
                          onFocused: () => _prewarmMovies(active),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  XtreamMoviesScreen(playlist: active),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 26),
                      Expanded(
                        child: _SectionButton(
                          eyebrow: 'TEMPORADAS',
                          title: 'SERIES',
                          subtitle: 'Las mejores series en un solo lugar',
                          icon: Icons.ondemand_video_rounded,
                          accent: const Color(0xFFA04CFF),
                          onFocused: () => _prewarmSeries(active),
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
                Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      color: tvFullViolet,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Contenido actualizado',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Tu contenido listo para disfrutar',
                          style: TextStyle(
                              color: Color(0x73FFFFFF), fontSize: 11.5),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const AppVersionBadge(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _prewarmMovies(Playlist playlist) {
    if (playlist.sourceType != PlaylistSourceType.xtream) return;
    unawaited(
      XtreamFastCatalogService.instance.prewarmCachedMovies(playlist.source),
    );
  }

  void _prewarmSeries(Playlist playlist) {
    if (playlist.sourceType != PlaylistSourceType.xtream) return;
    unawaited(
      XtreamFastCatalogService.instance.prewarmCachedSeries(playlist.source),
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
              content: Text('No hay un código de actualización válido.')),
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
                      const SnackBar(content: Text('Código copiado.')));
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

class _SectionButton extends StatefulWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onFocused;
  final bool autofocus;

  const _SectionButton({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.onFocused,
    this.autofocus = false,
  });

  @override
  State<_SectionButton> createState() => _SectionButtonState();
}

class _SectionButtonState extends State<_SectionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    final scale = _focused ? (lowRam ? 1.035 : 1.065) : 1.0;
    return AnimatedScale(
      scale: scale,
      duration: Duration(milliseconds: lowRam ? 90 : 150),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: Duration(milliseconds: lowRam ? 90 : 150),
        curve: Curves.easeOutCubic,
        decoration: tvFullGlassDecoration(
          focused: _focused,
          radius: 22,
          accent: widget.accent,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            autofocus: widget.autofocus,
            borderRadius: BorderRadius.circular(22),
            onFocusChange: (value) {
              if (_focused != value) setState(() => _focused = value);
              if (value) widget.onFocused?.call();
            },
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          widget.accent.withValues(alpha: _focused ? .28 : .16),
                          tvFullViolet.withValues(alpha: _focused ? .20 : .09),
                        ],
                      ),
                      border: Border.all(
                        color: widget.accent
                            .withValues(alpha: _focused ? .75 : .28),
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 37,
                      color: _focused ? widget.accent : Colors.white70,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.eyebrow,
                    style: TextStyle(
                      color: _focused ? widget.accent : Color(0x73FFFFFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.25,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 25,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 11),
                  Text(
                    widget.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
