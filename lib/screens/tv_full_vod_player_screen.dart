import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/channel.dart';
import '../models/playback_settings.dart';

const String _vodUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/96.0.4664.18 Safari/537.36';

class TvFullVodPlayerScreen extends StatefulWidget {
  final Channel channel;
  final PlaybackSettings settings;

  const TvFullVodPlayerScreen({
    super.key,
    required this.channel,
    required this.settings,
  });

  @override
  State<TvFullVodPlayerScreen> createState() => _TvFullVodPlayerScreenState();
}

class _TvFullVodPlayerScreenState extends State<TvFullVodPlayerScreen> {
  static const Duration _startupTimeout = Duration(seconds: 15);

  late final Player _player;
  late final VideoController _controller;
  final FocusNode _rootFocus = FocusNode(debugLabel: 'tvfull-pro-vod');

  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _bufferingSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _tracksSub;
  StreamSubscription? _trackSub;
  StreamSubscription? _completedSub;
  Timer? _overlayTimer;
  Timer? _startupWatchdog;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _overlayVisible = false;
  String? _error;
  Tracks _tracks = const Tracks();
  Track _track = const Track();

  @override
  void initState() {
    super.initState();
    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: widget.settings.bufferBytes,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        // El decoder es CPU para evitar el MediaCodec/Realtek problemático;
        // el render sigue usando la salida GPU de media_kit_video.
        hwdec: 'no',
        enableHardwareAcceleration: true,
      ),
    );
    _positionSub = _player.stream.position.listen((value) {
      if (!mounted) return;
      if (value > Duration.zero) _cancelStartupWatchdog();
      setState(() => _position = value);
    });
    _durationSub = _player.stream.duration.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _playingSub = _player.stream.playing.listen((value) {
      if (!mounted) return;
      if (value) _cancelStartupWatchdog();
      setState(() => _playing = value);
    });
    _bufferingSub = _player.stream.buffering.listen((value) {
      if (mounted) setState(() => _buffering = value);
    });
    _errorSub = _player.stream.error.listen((value) {
      final detail = value.toString();
      debugPrint('TV FULL PRO VOD: $detail');
      if (!mounted) return;
      _cancelStartupWatchdog();
      setState(() {
        _buffering = false;
        _error = _friendlyVodError(detail);
        _overlayVisible = true;
      });
    });
    _tracksSub = _player.stream.tracks.listen((value) {
      if (mounted) setState(() => _tracks = value);
    });
    _trackSub = _player.stream.track.listen((value) {
      if (mounted) setState(() => _track = value);
    });
    _completedSub = _player.stream.completed.listen((completed) {
      if (!mounted || !completed) return;
      _cancelStartupWatchdog();
      setState(() {
        _playing = false;
        _overlayVisible = true;
        _position = _duration;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rootFocus.requestFocus();
    });
    unawaited(_open());
  }

  Future<void> _open() async {
    _cancelStartupWatchdog();
    if (mounted) {
      setState(() {
        _buffering = true;
        _error = null;
      });
    }
    _startStartupWatchdog();
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        try {
          await platform.setProperty('hwdec', 'no');
        } catch (_) {}
      }
      final headers = widget.channel.resolvedHttpHeaders(_vodUserAgent);
      await _player.open(
        Media(widget.channel.url, httpHeaders: headers),
        play: true,
      );
    } catch (error) {
      debugPrint('TV FULL PRO VOD open: $error');
      if (!mounted) return;
      _cancelStartupWatchdog();
      setState(() {
        _buffering = false;
        _error = _friendlyVodError(error.toString());
        _overlayVisible = true;
      });
    }
  }

  void _startStartupWatchdog() {
    _startupWatchdog?.cancel();
    _startupWatchdog = Timer(_startupTimeout, () {
      if (!mounted || _error != null || _playing || _position > Duration.zero) {
        return;
      }
      unawaited(_player.stop());
      setState(() {
        _buffering = false;
        _error = 'El servidor tardó demasiado en iniciar este contenido.';
        _overlayVisible = true;
      });
      _rootFocus.requestFocus();
    });
  }

  void _cancelStartupWatchdog() {
    _startupWatchdog?.cancel();
    _startupWatchdog = null;
  }

  String _friendlyVodError(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('403') || value.contains('401')) {
      return 'El servidor no autorizó esta reproducción.';
    }
    if (value.contains('404') || value.contains('not found')) {
      return 'Este contenido ya no está disponible.';
    }
    if (value.contains('timeout') ||
        value.contains('network') ||
        value.contains('connection')) {
      return 'No se pudo conectar con el servidor.';
    }
    if (value.contains('codec') ||
        value.contains('decoder') ||
        value.contains('format')) {
      return 'El formato de este video no es compatible.';
    }
    return 'No se pudo reproducir este contenido.';
  }

  void _showOverlay() {
    _overlayTimer?.cancel();
    if (!_overlayVisible && mounted) setState(() => _overlayVisible = true);
    _overlayTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _error != null) return;
      setState(() => _overlayVisible = false);
      _rootFocus.requestFocus();
    });
  }

  Future<void> _seekBy(Duration delta) async {
    final max = _duration > Duration.zero ? _duration : const Duration(days: 1);
    var target = _position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > max) target = max;
    await _player.seek(target);
    _showOverlay();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (!_overlayVisible) {
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        _showOverlay();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        unawaited(_seekBy(const Duration(seconds: -10)));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        unawaited(_seekBy(const Duration(seconds: 10)));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaPlayPause) {
        unawaited(_player.playOrPause());
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _chooseAudio() async {
    final items = _tracks.audio
        .where((item) => item.id != 'no')
        .toList(growable: false);
    if (items.isEmpty) return;
    final chosen = await showDialog<AudioTrack>(
      context: context,
      builder: (context) => _TrackDialog<AudioTrack>(
        title: 'Audio',
        tracks: items,
        selectedId: _track.audio.id,
        label: (item) =>
            _trackLabel(item.id, item.title, item.language, auto: 'Automático'),
      ),
    );
    if (chosen != null) await _player.setAudioTrack(chosen);
    _showOverlay();
  }

  Future<void> _chooseSubtitle() async {
    final actual = _tracks.subtitle
        .where((item) => item.id != 'auto' && item.id != 'no')
        .toList(growable: false);
    final options = <SubtitleTrack>[SubtitleTrack.no(), ...actual];
    final chosen = await showDialog<SubtitleTrack>(
      context: context,
      builder: (context) => _TrackDialog<SubtitleTrack>(
        title: 'Subtítulos',
        tracks: options,
        selectedId: _track.subtitle.id,
        label: (item) => item.id == 'no'
            ? 'Desactivados'
            : _trackLabel(item.id, item.title, item.language),
      ),
    );
    if (chosen != null) await _player.setSubtitleTrack(chosen);
    _showOverlay();
  }

  String _trackLabel(
    String id,
    String? title,
    String? language, {
    String? auto,
  }) {
    if (id == 'auto' && auto != null) return auto;
    final parts = <String>[];
    final cleanTitle = title?.trim() ?? '';
    final cleanLanguage = language?.trim() ?? '';
    if (cleanLanguage.isNotEmpty && cleanLanguage != 'und')
      parts.add(cleanLanguage.toUpperCase());
    if (cleanTitle.isNotEmpty && !parts.contains(cleanTitle))
      parts.add(cleanTitle);
    return parts.isEmpty ? 'Pista $id' : parts.join(' · ');
  }

  String _clock(Duration value) {
    final seconds = value.inSeconds < 0 ? 0 : value.inSeconds;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _cancelStartupWatchdog();
    _overlayTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _tracksSub?.cancel();
    _trackSub?.cancel();
    _completedSub?.cancel();
    _rootFocus.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: _controller,
              controls: NoVideoControls,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.low,
              subtitleViewConfiguration: const SubtitleViewConfiguration(
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  backgroundColor: Color(0x99000000),
                  height: 1.25,
                ),
                padding: EdgeInsets.fromLTRB(28, 28, 28, 50),
              ),
            ),
            if (_buffering && _error == null)
              const Center(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            if (_error != null) _errorView(),
            if (_overlayVisible && _error == null) _controls(),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.fromLTRB(26, 0, 26, 20),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            color: const Color(0xEA090E14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${_clock(_position)} / ${_clock(_duration)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Colors.white12,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ControlButton(
                    autofocus: true,
                    icon: Icons.replay_10_rounded,
                    label: '-10 s',
                    onPressed: () =>
                        unawaited(_seekBy(const Duration(seconds: -10))),
                  ),
                  _ControlButton(
                    icon: _playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    label: _playing ? 'Pausa' : 'Play',
                    onPressed: () {
                      unawaited(_player.playOrPause());
                      _showOverlay();
                    },
                  ),
                  _ControlButton(
                    icon: Icons.forward_10_rounded,
                    label: '+10 s',
                    onPressed: () =>
                        unawaited(_seekBy(const Duration(seconds: 10))),
                  ),
                  _ControlButton(
                    icon: Icons.volume_up_outlined,
                    label: 'Audio',
                    onPressed: () => unawaited(_chooseAudio()),
                  ),
                  _ControlButton(
                    icon: Icons.subtitles_outlined,
                    label: 'Subtítulos',
                    onPressed: () => unawaited(_chooseSubtitle()),
                  ),
                  _ControlButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'Volver',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorView() => Center(
    child: Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xEE10161D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.movie_filter_outlined,
            size: 44,
            color: Colors.white54,
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(
                autofocus: true,
                onPressed: () => unawaited(_open()),
                child: const Text('Reintentar'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Volver'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    child: OutlinedButton.icon(
      autofocus: autofocus,
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label),
    ),
  );
}

class _TrackDialog<T> extends StatelessWidget {
  final String title;
  final List<T> tracks;
  final String selectedId;
  final String Function(T item) label;

  const _TrackDialog({
    required this.title,
    required this.tracks,
    required this.selectedId,
    required this.label,
  });

  String _id(T item) {
    if (item is AudioTrack) return item.id;
    if (item is SubtitleTrack) return item.id;
    return '';
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: const Color(0xFF0D151E),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 520),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final item = tracks[index];
                  final selected = _id(item) == selectedId;
                  return ListTile(
                    autofocus: selected || (selectedId.isEmpty && index == 0),
                    selected: selected,
                    selectedTileColor: const Color(0xFF1677FF)
                        .withValues(alpha: .18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    title: Text(label(item)),
                    trailing: selected ? const Icon(Icons.check_rounded) : null,
                    onTap: () => Navigator.of(context).pop(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
