import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Controles de reproducción para TV en vivo.
///
/// Esta capa es deliberadamente pasiva: observa posición, buffer, playing y
/// buffering para dibujar el estado EN VIVO/ATRASADO, pero no modifica cache,
/// red, demuxer, reconexiones ni ninguna propiedad del Player.
class LiveVideoView extends StatefulWidget {
  final Player player;
  final VideoController controller;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool canPrevious;
  final bool canNext;

  const LiveVideoView({
    super.key,
    required this.player,
    required this.controller,
    required this.onPrevious,
    required this.onNext,
    required this.canPrevious,
    required this.canNext,
  });

  @override
  State<LiveVideoView> createState() => _LiveVideoViewState();
}

class _LiveVideoViewState extends State<LiveVideoView> {
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;

  Duration _position = Duration.zero;
  Duration _bufferPosition = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _hasStarted = false;

  // El nivel normal de buffer depende mucho del proveedor y del perfil.
  // Tomamos varias muestras estables al comenzar el canal y usamos ese nivel
  // como referencia. Así no confundimos un buffer sano (p.ej. 6-8 s) con un
  // atraso real. El rojo se apaga solo cuando el reproductor se aleja de su
  // comportamiento normal o entra en buffering/pausa.
  final List<double> _baselineSamples = <double>[];
  double? _baselineAheadSeconds;

  @override
  void initState() {
    super.initState();

    _positionSub = widget.player.stream.position.listen((value) {
      if (!mounted) return;
      _position = value;
      _recalculate();
    });

    _bufferSub = widget.player.stream.buffer.listen((value) {
      if (!mounted) return;
      _bufferPosition = value;
      _recalculate();
    });

    _playingSub = widget.player.stream.playing.listen((value) {
      if (!mounted) return;
      _playing = value;
      if (value) _hasStarted = true;
      _recalculate();
    });

    _bufferingSub = widget.player.stream.buffering.listen((value) {
      if (!mounted) return;
      _buffering = value;
      _recalculate();
    });
  }

  double get _bufferAheadSeconds {
    final delta = _bufferPosition - _position;
    if (delta.isNegative) return 0;
    return delta.inMilliseconds / 1000.0;
  }

  void _recalculate() {
    final ahead = _bufferAheadSeconds;

    if (_playing && !_buffering && ahead.isFinite && ahead >= 0 && ahead < 45) {
      if (_baselineAheadSeconds == null) {
        _baselineSamples.add(ahead);
        if (_baselineSamples.length >= 6) {
          final sorted = List<double>.from(_baselineSamples)..sort();
          _baselineAheadSeconds = sorted[sorted.length ~/ 2];
        }
      }
    }

    setState(() {});
  }

  bool get _isLive {
    if (!_hasStarted || !_playing || _buffering) return false;

    final baseline = _baselineAheadSeconds;
    if (baseline == null) {
      // Durante los primeros segundos no penalizamos al canal mientras está
      // reproduciendo sin buffering.
      return true;
    }

    final tolerance = baseline < 2.0 ? 1.5 : (baseline * 0.35).clamp(1.5, 3.0);
    return _bufferAheadSeconds <= baseline + tolerance;
  }

  String get _statusLabel {
    if (!_hasStarted) return 'CARGANDO';
    if (_buffering) return 'BUFFER';
    if (!_playing) return 'PAUSA';
    return _isLive ? 'EN VIVO' : 'ATRASADO';
  }

  Widget _channelButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: MaterialDesktopCustomButton(
        onPressed: enabled ? onPressed : () {},
        icon: Icon(
          icon,
          color: enabled ? Colors.white : Colors.white30,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _bufferSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomBar = <Widget>[
      _channelButton(
        icon: Icons.skip_previous,
        tooltip: 'Canal anterior',
        enabled: widget.canPrevious,
        onPressed: widget.onPrevious,
      ),
      const MaterialDesktopPlayOrPauseButton(),
      _channelButton(
        icon: Icons.skip_next,
        tooltip: 'Canal siguiente',
        enabled: widget.canNext,
        onPressed: widget.onNext,
      ),
      const MaterialDesktopVolumeButton(),
      const MaterialDesktopPositionIndicator(),
      _LiveControlIndicator(
        active: _isLive,
        label: _statusLabel,
      ),
      const Spacer(),
      const MaterialDesktopFullscreenButton(),
    ];

    final theme = MaterialDesktopVideoControlsThemeData(
      bottomButtonBar: bottomBar,
      automaticallyImplySkipNextButton: false,
      automaticallyImplySkipPreviousButton: false,
    );

    return MaterialDesktopVideoControlsTheme(
      normal: theme,
      fullscreen: theme,
      child: Video(
        controller: widget.controller,
        controls: MaterialDesktopVideoControls,
      ),
    );
  }
}

class _LiveControlIndicator extends StatelessWidget {
  final bool active;
  final String label;

  const _LiveControlIndicator({
    required this.active,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? Colors.redAccent : Colors.white38,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
