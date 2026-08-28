import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/iptv_provider.dart';
import '../services/app_update_service.dart';
import '../services/remote_access_guard.dart';
import 'source_content_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _syncTimer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<IptvProvider>();
      unawaited(provider.init());
      unawaited(AppUpdateService.instance.checkOnce());
      _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        final current = context.read<IptvProvider>();
        if (current.remoteSyncing) return;
        _tick++;
        // Sin listas: respuesta rápida del panel. Con listas: validación cada
        // ~30 s sin volver a descargar catálogos que ya están guardados.
        if (current.playlists.isEmpty || _tick % 10 == 0) {
          unawaited(current.syncRemoteServices());
        }
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final provider = context.read<IptvProvider>();
    if (!provider.remoteSyncing) unawaited(provider.syncRemoteServices());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    if (!provider.initialized) {
      return const _StartupView(message: 'Iniciando TV FULL PRO…');
    }

    final blocked = remoteAccessBlockMessage(provider);
    if (blocked != null) {
      return _StartupView(
        message: blocked,
        deviceCode: provider.remoteDeviceCode,
        busy: false,
        blocked: true,
      );
    }

    final selected = provider.selectedPlaylist;
    if (selected == null) {
      return _StartupView(
        message: provider.remoteSyncError ??
            'Vinculá esta TV desde el panel para comenzar.',
        deviceCode: provider.remoteDeviceCode,
        busy: provider.remoteSyncing,
      );
    }

    return SourceContentScreen(playlist: selected);
  }
}

class _StartupView extends StatelessWidget {
  final String message;
  final String? deviceCode;
  final bool busy;
  final bool blocked;

  const _StartupView({
    required this.message,
    this.deviceCode,
    this.busy = true,
    this.blocked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05090F),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    blocked
                        ? Icons.lock_outline_rounded
                        : Icons.live_tv_rounded,
                    size: blocked ? 48 : 42,
                    color: blocked ? Colors.white70 : const Color(0xFF58B9FF),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'TV FULL PRO',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                  if (blocked) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'El contenido guardado se conserva y se habilitará de nuevo al reactivar el servicio.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                  if (deviceCode != null && deviceCode!.trim().isNotEmpty) ...[
                    const SizedBox(height: 26),
                    const Text(
                      'CÓDIGO DE DISPOSITIVO',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      deviceCode!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                  if (busy) ...[
                    const SizedBox(height: 28),
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
