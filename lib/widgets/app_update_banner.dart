import 'package:flutter/material.dart';

import '../services/app_update_service.dart';

class AppUpdateBanner extends StatelessWidget {
  final String versionName;
  final AppUpdatePhase phase;
  final bool busy;
  final double progress;
  final int downloadedBytes;
  final int? totalBytes;
  final VoidCallback onUpdate;

  const AppUpdateBanner({
    super.key,
    required this.versionName,
    required this.onUpdate,
    this.phase = AppUpdatePhase.idle,
    this.busy = false,
    this.progress = 0,
    this.downloadedBytes = 0,
    this.totalBytes,
  });

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFFF626B);
    final percent = (progress.clamp(0.0, 1.0) * 100).floor();
    final downloading = phase == AppUpdatePhase.downloading;
    final status = switch (phase) {
      AppUpdatePhase.downloading => totalBytes == null
          ? 'Descargando… ${_mb(downloadedBytes)} MB'
          : 'Descargando $percent% · ${_mb(downloadedBytes)} / ${_mb(totalBytes!)} MB',
      AppUpdatePhase.verifying => 'Verificando la APK…',
      AppUpdatePhase.installing => 'Abriendo el instalador de Android…',
      AppUpdatePhase.permission =>
        'APK guardada. Permití instalar aplicaciones y volvé para continuar.',
      AppUpdatePhase.ready =>
        'APK lista. Confirmá la actualización en el instalador de Android.',
      AppUpdatePhase.error => 'No se pudo completar. Presioná para reintentar.',
      AppUpdatePhase.idle =>
        'Nueva versión $versionName · Presioná para iniciar la actualización.',
    };
    final buttonLabel = busy
        ? (downloading ? (totalBytes == null ? 'DESCARGANDO…' : 'DESCARGANDO $percent%') : 'PROCESANDO…')
        : switch (phase) {
            AppUpdatePhase.permission => 'CONTINUAR INSTALACIÓN',
            AppUpdatePhase.ready => 'VOLVER A INSTALAR',
            AppUpdatePhase.error => 'REINTENTAR',
            _ => 'INSTALAR ACTUALIZACIÓN',
          };
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
                Text(
                  'ACTUALIZACIÓN $versionName',
                  style: const TextStyle(
                    color: red,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .45,
                  ),
                ),
                const SizedBox(height: 2),
                Text(status, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                if (busy) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: downloading && totalBytes != null ? progress.clamp(0.0, 1.0).toDouble() : null,
                    minHeight: 5,
                    color: red,
                    backgroundColor: Colors.white12,
                    semanticsLabel: downloading ? 'Descarga de la actualización' : 'Verificación e instalación',
                    semanticsValue: downloading && totalBytes != null ? '$percent%' : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: busy ? null : onUpdate,
            style: OutlinedButton.styleFrom(
              foregroundColor: red,
              disabledForegroundColor: Colors.white60,
              side: const BorderSide(color: red),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(buttonLabel, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}
