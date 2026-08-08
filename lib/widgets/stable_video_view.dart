import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Capa de UI/diagnóstico deliberadamente PASIVA.
///
/// No cambia cache, demuxer, timeouts, reconexiones ni ninguna propiedad
/// de red del Player. Esto permite medir resolución/buffer sin alterar el
/// comportamiento estable del motor de reproducción.
class StableVideoView extends StatefulWidget {
  final Player player;
  final VideoController controller;

  const StableVideoView({
    super.key,
    required this.player,
    required this.controller,
  });

  @override
  State<StableVideoView> createState() => _StableVideoViewState();
}

class _StableVideoViewState extends State<StableVideoView> {
  StreamSubscription? _videoParamsSub;
  StreamSubscription? _trackSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _bufferSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _bufferingSub;

  int? _width;
  int? _height;
  double? _fps;
  String? _videoCodec;
  String? _audioCodec;
  double? _videoBitrate;
  double? _audioBitrate;
  Duration _position = Duration.zero;
  Duration _bufferPosition = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();

    _videoParamsSub = widget.player.stream.videoParams.listen((params) {
      if (!mounted) return;
      final width = params.w ?? params.dw;
      final height = params.h ?? params.dh;
      if (width == _width && height == _height) return;
      setState(() {
        _width = width;
        _height = height;
      });
    });

    _trackSub = widget.player.stream.track.listen((track) {
      if (!mounted) return;
      final video = track.video;
      final audio = track.audio;
      setState(() {
        _fps = video.fps ?? _fps;
        _videoCodec = video.codec;
        _audioCodec = audio.codec;
        if (video.bitrate != null && video.bitrate! > 0) {
          _videoBitrate = video.bitrate!.toDouble();
        }
        if (audio.bitrate != null && audio.bitrate! > 0) {
          _audioBitrate = audio.bitrate!.toDouble();
        }
        _width ??= video.w;
        _height ??= video.h;
      });
    });

    // media_kit define stream.buffer como la POSICIÓN hasta la cual existen
    // datos decodificados/cacheados. La diferencia buffer - position es el
    // colchón útil por delante de la reproducción.
    _positionSub = widget.player.stream.position.listen((value) {
      if (!mounted) return;
      setState(() => _position = value);
    });
    _bufferSub = widget.player.stream.buffer.listen((value) {
      if (!mounted) return;
      setState(() => _bufferPosition = value);
    });
    _playingSub = widget.player.stream.playing.listen((value) {
      if (!mounted) return;
      setState(() {
        _playing = value;
        if (value) _hasStarted = true;
      });
    });
    _bufferingSub = widget.player.stream.buffering.listen((value) {
      if (!mounted) return;
      setState(() => _buffering = value);
    });
  }

  Duration get _bufferAhead {
    final delta = _bufferPosition - _position;
    return delta.isNegative ? Duration.zero : delta;
  }

  String get _resolutionLabel {
    if (_width == null || _height == null) return 'Detectando…';
    final fps = _fps;
    if (fps == null || fps <= 0) return '${_width}×$_height';
    return '${_width}×$_height · ${fps.toStringAsFixed(fps >= 10 ? 0 : 1)} fps';
  }

  String _formatBitrate(double? bitsPerSecond) {
    if (bitsPerSecond == null || bitsPerSecond <= 0) return 'No disponible';
    if (bitsPerSecond >= 1000000) {
      return '${(bitsPerSecond / 1000000).toStringAsFixed(2)} Mbps';
    }
    return '${(bitsPerSecond / 1000).toStringAsFixed(0)} kbps';
  }

  String get _bufferAheadText =>
      '${(_bufferAhead.inMilliseconds / 1000).toStringAsFixed(1)} s';

  Future<void> _showTechnicalInfo() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Información real del stream'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resolución real: ${_width ?? '—'} × ${_height ?? '—'}'),
            Text('FPS: ${_fps?.toStringAsFixed(2) ?? 'No disponible'}'),
            Text('Codec de video: ${_videoCodec ?? 'No disponible'}'),
            Text('Bitrate de video: ${_formatBitrate(_videoBitrate)}'),
            const SizedBox(height: 8),
            Text('Codec de audio: ${_audioCodec ?? 'No disponible'}'),
            Text('Bitrate de audio: ${_formatBitrate(_audioBitrate)}'),
            const SizedBox(height: 8),
            Text('Buffer real por delante: $_bufferAheadText'),
            Text('Reproduciendo: ${_playing ? 'sí' : 'no'}'),
            Text('Buffering: ${_buffering ? 'sí' : 'no'}'),
            const SizedBox(height: 8),
            const Text(
              'Diagnóstico pasivo: estos datos no modifican el buffer ni la conexión.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _videoParamsSub?.cancel();
    _trackSub?.cancel();
    _positionSub?.cancel();
    _bufferSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveIndicator = _LiveControlIndicator(
      active: _hasStarted && _playing && !_buffering,
    );

    final bottomBar = <Widget>[
      const MaterialDesktopSkipPreviousButton(),
      const MaterialDesktopPlayOrPauseButton(),
      const MaterialDesktopSkipNextButton(),
      const MaterialDesktopVolumeButton(),
      const MaterialDesktopPositionIndicator(),
      liveIndicator,
      const Spacer(),
      const MaterialDesktopFullscreenButton(),
    ];

    final topBar = <Widget>[
      const Spacer(),
      MaterialDesktopCustomButton(
        onPressed: _showTechnicalInfo,
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.high_quality, size: 20),
            const SizedBox(width: 6),
            Text(
              _resolutionLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ];

    final theme = MaterialDesktopVideoControlsThemeData(
      topButtonBar: topBar,
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

  const _LiveControlIndicator({required this.active});

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
            'EN VIVO',
            style: TextStyle(
              color: active ? Colors.white : Colors.white54,
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
