import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/iptv_provider.dart';
import '../services/app_update_service.dart';
import '../services/remote_access_guard.dart';
import '../widgets/app_version_badge.dart';
import 'source_content_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<IptvProvider>();
      unawaited(provider.init());
      unawaited(AppUpdateService.instance.checkOnce());
    });
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

    if (provider.remoteProvisioningSupported &&
        provider.remoteLastSyncedAt == null) {
      final verificationError = provider.remoteSyncError;
      return _StartupView(
        message: verificationError == null
            ? 'Verificando el estado de tu servicio…'
            : 'No se pudo verificar el servicio. Revisá la conexión a Internet.',
        deviceCode: provider.remoteDeviceCode,
        busy: provider.remoteSyncing || verificationError == null,
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
    final accent = blocked ? const Color(0xFFFF6F8F) : const Color(0xFF54D7FF);

    return Scaffold(
      backgroundColor: const Color(0xFF050B14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _StartupBackground(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 610),
                child: Container(
                  margin: const EdgeInsets.all(30),
                  padding: const EdgeInsets.fromLTRB(40, 34, 40, 28),
                  decoration: BoxDecoration(
                    color: const Color(0xDB0A1422),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: accent.withValues(alpha: .35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .35),
                        blurRadius: 32,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: accent.withValues(alpha: .10),
                          border: Border.all(
                            color: accent.withValues(alpha: .28),
                          ),
                        ),
                        child: Icon(
                          blocked
                              ? Icons.lock_outline_rounded
                              : Icons.play_arrow_rounded,
                          color: accent,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'TV FULL PRO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                      if (deviceCode != null &&
                          deviceCode!.trim().isNotEmpty) ...[
                        const SizedBox(height: 22),
                        const Text(
                          'CÓDIGO DE DISPOSITIVO',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.3,
                          ),
                        ),
                        const SizedBox(height: 7),
                        SelectableText(
                          deviceCode!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: accent,
                            fontSize: 27,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                      if (busy) ...[
                        const SizedBox(height: 24),
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.8,
                            color: accent,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const AppVersionBadge(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartupBackground extends StatelessWidget {
  const _StartupBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: -170,
            top: -210,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF2D8CFF).withValues(alpha: .13),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -220,
            bottom: -250,
            child: Container(
              width: 600,
              height: 600,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF54D7FF).withValues(alpha: .08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
