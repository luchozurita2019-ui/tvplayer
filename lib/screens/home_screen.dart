import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/iptv_provider.dart';
import '../services/app_update_service.dart';
import '../services/remote_access_guard.dart';
import '../widgets/app_version_badge.dart';
import '../widgets/tv_full_brand.dart';
import '../widgets/tv_full_premium_ui.dart';
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
      return const _StartupView(
        title: 'Conectando al servidor',
        message: 'Preparando TV en vivo, películas y series…',
      );
    }

    final blocked = remoteAccessBlockMessage(provider);
    if (blocked != null) {
      return _StartupView(
        title: 'Servicio no disponible',
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
        title: verificationError == null
            ? 'Conectando al servidor'
            : 'Sin conexión con el servidor',
        message: verificationError == null
            ? 'Vinculando esta TV con tu panel…'
            : 'No se pudo verificar el servicio. Revisá la conexión a Internet.',
        deviceCode: provider.remoteDeviceCode,
        busy: provider.remoteSyncing || verificationError == null,
      );
    }

    final selected = provider.selectedPlaylist;
    if (selected == null) {
      return _StartupView(
        title: 'Vinculá esta TV',
        message: provider.remoteSyncError ??
            'Ingresá el código del dispositivo en el panel para comenzar.',
        deviceCode: provider.remoteDeviceCode,
        busy: provider.remoteSyncing,
      );
    }

    return SourceContentScreen(playlist: selected);
  }
}

class _StartupView extends StatelessWidget {
  final String title;
  final String message;
  final String? deviceCode;
  final bool busy;
  final bool blocked;

  const _StartupView({
    required this.title,
    required this.message,
    this.deviceCode,
    this.busy = true,
    this.blocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = blocked ? const Color(0xFFFF6B78) : tvFullCyan;
    return Scaffold(
      backgroundColor: tvFullBackground,
      body: TvFullPremiumBackground(
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(24, 18, 24, 20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TvFullBrand(iconSize: 42),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 58,
                          decoration: BoxDecoration(
                            color: const Color(0x660D192A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .07),
                            ),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _GhostNavIcon(Icons.live_tv_rounded,
                                  active: true),
                              _GhostNavIcon(Icons.movie_rounded),
                              _GhostNavIcon(Icons.video_library_rounded),
                              _GhostNavIcon(Icons.sports_soccer_rounded),
                              _GhostNavIcon(Icons.child_care_rounded),
                              _GhostNavIcon(Icons.lock_outline_rounded),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0x3D101C2D),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: tvFullCyan.withValues(alpha: .10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 250,
                          decoration: BoxDecoration(
                            color: const Color(0x4A101C2D),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .07),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 570),
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.fromLTRB(34, 30, 34, 26),
                  decoration: BoxDecoration(
                    color: const Color(0xE00C1829),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: accent.withValues(alpha: .42),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: .12),
                        blurRadius: 32,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: .10),
                          border: Border.all(
                            color: accent.withValues(alpha: .36),
                          ),
                        ),
                        child: Icon(
                          blocked
                              ? Icons.lock_outline_rounded
                              : Icons.cell_tower_rounded,
                          color: accent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      if (deviceCode != null &&
                          deviceCode!.trim().isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .035),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .08),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'CÓDIGO DE DISPOSITIVO',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.15,
                                ),
                              ),
                              const SizedBox(height: 5),
                              SelectableText(
                                deviceCode!,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (busy) ...[
                        const SizedBox(height: 20),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: const LinearProgressIndicator(
                            minHeight: 4,
                            color: tvFullCyan,
                            backgroundColor: Color(0x26167AFF),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Por favor esperá unos segundos',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      const AppVersionBadge(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostNavIcon extends StatelessWidget {
  final IconData icon;
  final bool active;

  const _GhostNavIcon(this.icon, {this.active = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: active ? tvFullBlue.withValues(alpha: .15) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color:
              active ? tvFullCyan.withValues(alpha: .30) : Colors.transparent,
        ),
      ),
      child: Icon(
        icon,
        size: 20,
        color: active ? tvFullCyan : Colors.white24,
      ),
    );
  }
}
