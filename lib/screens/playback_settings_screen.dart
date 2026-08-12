import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playback_settings.dart';
import '../providers/iptv_provider.dart';
import '../services/playback_metrics_service.dart';
import '../services/internet_speed_test_service.dart';

class PlaybackSettingsScreen extends StatefulWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  State<PlaybackSettingsScreen> createState() => _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  late PlaybackSettings _draft;
  bool _speedTestRunning = false;
  InternetSpeedTestResult? _speedTestResult;
  String? _speedTestError;

  @override
  void initState() {
    super.initState();
    _draft = context.read<IptvProvider>().playbackSettings;
  }

  void _applyPreset(BufferProfile profile) {
    setState(() {
      _draft = switch (profile) {
        BufferProfile.auto => PlaybackSettings.auto,
        BufferProfile.ultraFast => PlaybackSettings.ultraFast,
        BufferProfile.balanced => PlaybackSettings.balanced,
        BufferProfile.stable => PlaybackSettings.stable,
        BufferProfile.slowConnection => PlaybackSettings.slowConnection,
        BufferProfile.custom => _draft.copyWith(profile: BufferProfile.custom),
      };
    });
  }

  void _makeCustom(PlaybackSettings settings) {
    setState(() => _draft = settings.copyWith(profile: BufferProfile.custom));
  }

  Future<void> _runInternetSpeedTest() async {
    if (_speedTestRunning) return;
    setState(() {
      _speedTestRunning = true;
      _speedTestError = null;
    });
    try {
      final result = await InternetSpeedTestService.instance.run();
      if (!mounted) return;
      setState(() => _speedTestResult = result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speedTestResult = null;
        _speedTestError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _speedTestRunning = false);
    }
  }

  String _speedQuality(double mbps) {
    if (mbps >= 40) return 'Muy buena';
    if (mbps >= 20) return 'Buena';
    if (mbps >= 10) return 'Aceptable';
    if (mbps >= 6) return 'Limitada';
    return 'Muy baja';
  }

  String _speedGuidance(double mbps) {
    if (mbps < 6) {
      return 'La descarga es baja para IPTV y puede provocar pausas o buffering, especialmente en canales HD.';
    }
    if (mbps < 10) {
      return 'La conexión puede alcanzar para señales livianas, pero tiene poco margen para canales HD de bitrate alto.';
    }
    if (mbps < 20) {
      return 'Hay un margen razonable para TV HD. Si un canal sigue fallando, conviene revisar también Wi‑Fi, servidor y estabilidad.';
    }
    if (mbps < 40) {
      return 'La velocidad de descarga es buena para la mayoría de señales IPTV. Un fallo aislado probablemente necesita diagnóstico adicional.';
    }
    return 'La velocidad de descarga es muy buena. Si hay cortes, TV FULL debería revisar estabilidad, Wi‑Fi y el servidor del proveedor antes de atribuirlos al ancho de banda.';
  }

  Widget _buildInternetSpeedCard() {
    final result = _speedTestResult;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Probar velocidad de Internet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _speedTestRunning ? null : _runInternetSpeedTest,
                  icon: _speedTestRunning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded),
                  label: Text(_speedTestRunning ? 'Midiendo…' : 'Iniciar test'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Mide la bajada y la latencia contra la red de Cloudflare. Sirve para soporte y para comprobar si el cliente tiene ancho de banda suficiente antes de diagnosticar la aplicación o el proveedor.',
            ),
            const SizedBox(height: 6),
            const Text(
              'El test usa aproximadamente 10–15 MB. No mide la velocidad del servidor IPTV y una buena bajada no descarta Wi‑Fi inestable, pérdida de paquetes o un proveedor saturado.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            if (_speedTestRunning) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Midiendo conexión… puede tardar algunos segundos.'),
            ],
            if (_speedTestError != null) ...[
              const SizedBox(height: 14),
              Text(
                'No se pudo completar el test: $_speedTestError',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (result != null && !_speedTestRunning) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _SpeedMetric(
                    label: 'DESCARGA',
                    value: '${result.downloadMbps.toStringAsFixed(1)} Mbps',
                    icon: Icons.download_rounded,
                  ),
                  _SpeedMetric(
                    label: 'LATENCIA',
                    value: '${result.latencyMs} ms',
                    icon: Icons.timer_outlined,
                  ),
                  _SpeedMetric(
                    label: 'CALIDAD',
                    value: _speedQuality(result.downloadMbps),
                    icon: Icons.network_check_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _speedGuidance(result.downloadMbps),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (result.downloadMbps < 15) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_tethering_error_rounded),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Para esta velocidad conviene probar Conexión lenta. TV FULL reservará más video por adelantado y será más paciente ante microcortes.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () =>
                            _applyPreset(BufferProfile.slowConnection),
                        child: const Text('Activar'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showLearnedStats() async {
    final stats = await PlaybackMetricsService.instance.allStats();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rendimiento aprendido'),
        content: SizedBox(
          width: 520,
          child: stats.isEmpty
              ? const Text(
                  'Todavía no hay suficientes mediciones. Usá algunos canales y el modo automático empezará a aprender cómo responde cada servidor.',
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: stats.take(10).length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = stats[index];
                    final average = item.averageStartupMs;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Arranques: ${item.startupCount} · Fallos: ${item.failures} · Cortes: ${item.stalls} · Fallbacks: ${item.fastProbeFallbacks}',
                      ),
                      trailing: Text(
                        average == null ? '—' : '${average.round()} ms',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    );
                  },
                ),
        ),
        actions: [
          if (stats.isNotEmpty)
            TextButton(
              onPressed: () async {
                await PlaybackMetricsService.instance.clear();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Borrar aprendizaje'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rendimiento de reproducción'),
        actions: [
          TextButton(
            onPressed: () async {
              await context.read<IptvProvider>().updatePlaybackSettings(_draft);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Elegí un perfil o dejá que TVPlayer aprenda automáticamente cómo responde cada servidor.',
          ),
          const SizedBox(height: 16),
          _buildInternetSpeedCard(),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ProfileChip(
                label: 'Automático',
                icon: Icons.auto_awesome,
                selected: _draft.profile == BufferProfile.auto,
                onTap: () => _applyPreset(BufferProfile.auto),
              ),
              _ProfileChip(
                label: 'Ultra rápido',
                icon: Icons.bolt,
                selected: _draft.profile == BufferProfile.ultraFast,
                onTap: () => _applyPreset(BufferProfile.ultraFast),
              ),
              _ProfileChip(
                label: 'Equilibrado',
                icon: Icons.tune,
                selected: _draft.profile == BufferProfile.balanced,
                onTap: () => _applyPreset(BufferProfile.balanced),
              ),
              _ProfileChip(
                label: 'Estable',
                icon: Icons.shield_outlined,
                selected: _draft.profile == BufferProfile.stable,
                onTap: () => _applyPreset(BufferProfile.stable),
              ),
              _ProfileChip(
                label: 'Conexión lenta',
                icon: Icons.wifi_tethering_error_rounded,
                selected: _draft.profile == BufferProfile.slowConnection,
                onTap: () => _applyPreset(BufferProfile.slowConnection),
              ),
              _ProfileChip(
                label: 'Personalizado',
                icon: Icons.settings,
                selected: _draft.profile == BufferProfile.custom,
                onTap: () => _applyPreset(BufferProfile.custom),
              ),
            ],
          ),
          if (_draft.profile == BufferProfile.auto) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.psychology_alt_outlined),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Buffer adaptativo',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'TVPlayer mide arranque, fallos y cortes por servidor. Con esas muestras puede usar una configuración rápida en servidores buenos y reforzar el buffer cuando detecta inestabilidad.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _showLearnedStats,
                      icon: const Icon(Icons.query_stats),
                      label: const Text('Ver diagnóstico aprendido'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_draft.profile == BufferProfile.slowConnection) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.wifi_tethering_error_rounded),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Modo conexión lenta',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Prioriza continuidad sobre velocidad de arranque. En TV en vivo usa una reserva moderada para no alejarse demasiado del directo; en Películas y Series anticipa más datos. Durante la reproducción, TV FULL mantiene pausadas las descargas de portadas y logos.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No reduce automáticamente la calidad y no puede compensar un stream cuyo bitrate sea permanentemente mayor que la velocidad disponible.',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _SliderTile(
            title: 'Memoria de buffer',
            subtitle: '${_draft.bufferMb} MB',
            value: _draft.bufferMb.toDouble(),
            min: 4,
            max: 128,
            divisions: 31,
            onChanged: (value) =>
                _makeCustom(_draft.copyWith(bufferMb: value.round())),
          ),
          _SliderTile(
            title: 'Lectura anticipada',
            subtitle: '${_draft.readaheadSeconds.toStringAsFixed(1)} s',
            value: _draft.readaheadSeconds,
            min: 0.5,
            max: 12,
            divisions: 23,
            onChanged: (value) =>
                _makeCustom(_draft.copyWith(readaheadSeconds: value)),
          ),
          _SliderTile(
            title: 'Buffer tras un corte',
            subtitle: '${_draft.recoveryBufferSeconds.toStringAsFixed(1)} s',
            value: _draft.recoveryBufferSeconds,
            min: 0.5,
            max: 8,
            divisions: 15,
            onChanged: (value) =>
                _makeCustom(_draft.copyWith(recoveryBufferSeconds: value)),
          ),
          _SliderTile(
            title: 'Timeout de conexión',
            subtitle: '${_draft.connectTimeoutSeconds} s',
            value: _draft.connectTimeoutSeconds.toDouble(),
            min: 3,
            max: 20,
            divisions: 17,
            onChanged: (value) => _makeCustom(
              _draft.copyWith(connectTimeoutSeconds: value.round()),
            ),
          ),
          _SliderTile(
            title: 'Reintentos automáticos',
            subtitle: '${_draft.maxRetries}',
            value: _draft.maxRetries.toDouble(),
            min: 0,
            max: 6,
            divisions: 6,
            onChanged: (value) =>
                _makeCustom(_draft.copyWith(maxRetries: value.round())),
          ),
          _SliderTile(
            title: 'Detección de stream trabado',
            subtitle: '${_draft.stallThresholdSeconds} s',
            value: _draft.stallThresholdSeconds.toDouble(),
            min: 4,
            max: 20,
            divisions: 16,
            onChanged: (value) => _makeCustom(
              _draft.copyWith(stallThresholdSeconds: value.round()),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Ultra rápido prioriza el zapping. Estable usa más margen para redes irregulares. Conexión lenta aumenta la reserva y la tolerancia a microcortes. Automático aprende por servidor. Si movés cualquier control manual, el perfil cambia a Personalizado.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SpeedMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white60,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title)),
                Text(subtitle, style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
