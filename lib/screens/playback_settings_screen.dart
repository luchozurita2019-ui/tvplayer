import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playback_settings.dart';
import '../providers/iptv_provider.dart';

class PlaybackSettingsScreen extends StatefulWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  State<PlaybackSettingsScreen> createState() =>
      _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  late PlaybackSettings _draft;

  @override
  void initState() {
    super.initState();
    _draft = context.read<IptvProvider>().playbackSettings;
  }

  void _applyPreset(BufferProfile profile) {
    setState(() {
      _draft = switch (profile) {
        BufferProfile.ultraFast => PlaybackSettings.ultraFast,
        BufferProfile.balanced => PlaybackSettings.balanced,
        BufferProfile.stable => PlaybackSettings.stable,
        BufferProfile.custom => _draft.copyWith(profile: BufferProfile.custom),
      };
    });
  }

  void _makeCustom(PlaybackSettings settings) {
    setState(() => _draft = settings.copyWith(profile: BufferProfile.custom));
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
            'Elegí un perfil rápido o ajustá manualmente cómo se comporta el buffer y la reconexión.',
          ),
          const SizedBox(height: 16),
          SegmentedButton<BufferProfile>(
            segments: const [
              ButtonSegment(
                value: BufferProfile.ultraFast,
                label: Text('Ultra rápido'),
                icon: Icon(Icons.bolt),
              ),
              ButtonSegment(
                value: BufferProfile.balanced,
                label: Text('Equilibrado'),
                icon: Icon(Icons.tune),
              ),
              ButtonSegment(
                value: BufferProfile.stable,
                label: Text('Estable'),
                icon: Icon(Icons.shield_outlined),
              ),
              ButtonSegment(
                value: BufferProfile.custom,
                label: Text('Personalizado'),
                icon: Icon(Icons.settings),
              ),
            ],
            selected: {_draft.profile},
            onSelectionChanged: (selection) => _applyPreset(selection.first),
            multiSelectionEnabled: false,
            showSelectedIcon: false,
          ),
          const SizedBox(height: 24),
          _SliderTile(
            title: 'Memoria de buffer',
            subtitle: '${_draft.bufferMb} MB',
            value: _draft.bufferMb.toDouble(),
            min: 4,
            max: 128,
            divisions: 31,
            onChanged: (value) => _makeCustom(
              _draft.copyWith(bufferMb: value.round()),
            ),
          ),
          _SliderTile(
            title: 'Lectura anticipada',
            subtitle: '${_draft.readaheadSeconds.toStringAsFixed(1)} s',
            value: _draft.readaheadSeconds,
            min: 0.5,
            max: 12,
            divisions: 23,
            onChanged: (value) => _makeCustom(
              _draft.copyWith(readaheadSeconds: value),
            ),
          ),
          _SliderTile(
            title: 'Buffer tras un corte',
            subtitle: '${_draft.recoveryBufferSeconds.toStringAsFixed(1)} s',
            value: _draft.recoveryBufferSeconds,
            min: 0.5,
            max: 8,
            divisions: 15,
            onChanged: (value) => _makeCustom(
              _draft.copyWith(recoveryBufferSeconds: value),
            ),
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
            onChanged: (value) => _makeCustom(
              _draft.copyWith(maxRetries: value.round()),
            ),
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
                'Ultra rápido prioriza el zapping. Estable usa más margen para redes irregulares. Si un proveedor limita conexiones o responde lento, un buffer mayor puede evitar cortes, pero no acelera el servidor.',
              ),
            ),
          ),
        ],
      ),
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
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            Slider(
              value: value.clamp(min, max),
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
