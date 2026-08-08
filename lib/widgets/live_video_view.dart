import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Controles de reproducción para TV en vivo.
///
/// Esta capa es deliberadamente pasiva: observa el estado del Player y el
/// avance real de la posición, pero nunca toca cache, red ni reconexiones.
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
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  Timer? _statusTimer;

  Duration _position = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _hasStarted = false;
  DateTime _lastProgressAt = DateTime.now();

  @override
  void initState() {
    super.initState();

    _positionSub = widget.player.stream.position.listen((value) {
      if (!mounted) return;
      if (value != _position) {
        _position = value;
        _lastProgressAt = DateTime.now();
      }
      setState(() {});
    });

    _playingSub = widget.player.stream.playing.listen((value) {
      if (!mounted) return;
      _playing = value;
      if (value) {
        _hasStarted = true;
        _lastProgressAt = DateTime.now();
      }
      setState(() {});
    });

    _bufferingSub = widget.player.stream.buffering.listen((value) {
      if (!mounted) return;
      _buffering = value;
      if (!value && _playing) _lastProgressAt = DateTime.now();
      setState(() {});
    });

    // El timer hace que el LED se apague aunque mpv deje de emitir eventos
    // mientras la imagen está congelada.
    _statusTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  bool get _isLive {
    if (!_hasStarted || !_playing || _buffering) return false;
    return DateTime.now().difference(_lastProgressAt) <
        const Duration(milliseconds: 2500);
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
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _statusTimer?.cancel();
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
    const liveRed = Color(0xFFFF2D2D);

    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: active ? liveRed : Colors.white30,
              shape: BoxShape.circle,
              boxShadow: active
                  ? const [
                      BoxShadow(
                        color: Color(0x99FF2D2D),
                        blurRadius: 9,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: active ? liveRed : Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.35,
            ),
          ),
        ],
      ),
    );
  }
}
