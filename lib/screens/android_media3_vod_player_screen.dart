import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

const String _vodUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/96.0.4664.18 Safari/537.36';

class AndroidMedia3VodPlayerScreen extends StatefulWidget {
  final List<Channel> playlist;
  final int initialIndex;

  const AndroidMedia3VodPlayerScreen({
    super.key,
    required this.playlist,
    required this.initialIndex,
  });

  @override
  State<AndroidMedia3VodPlayerScreen> createState() =>
      _AndroidMedia3VodPlayerScreenState();
}

class _AndroidMedia3VodPlayerScreenState
    extends State<AndroidMedia3VodPlayerScreen> {
  static const MethodChannel _player = MethodChannel('tvfull/media3_texture');
  static const EventChannel _events = EventChannel(
    'tvfull/media3_texture_events',
  );

  final FocusNode _focusNode = FocusNode(debugLabel: 'tvfull-vod-player');
  StreamSubscription<dynamic>? _eventSub;
  Timer? _progressTimer;
  Timer? _overlayTimer;

  late int _index;
  int? _textureId;
  double _aspectRatio = 16 / 9;
  bool _buffering = true;
  bool _ready = false;
  bool _playing = true;
  bool _overlayVisible = true;
  String? _error;
  String? _codecWarning;
  int _positionMs = 0;
  int _durationMs = 0;
  int _openGeneration = 0;
  List<_TrackOption> _audioTracks = const [];
  List<_TrackOption> _subtitleTracks = const [];

  Channel get _channel => widget.playlist[_index];

  Map<String, String> get _headers =>
      _channel.resolvedHttpHeaders(_vodUserAgent);

  @override
  void initState() {
    super.initState();
    _index = widget.playlist.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.playlist.length - 1);
    _eventSub = _events.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _buffering = false;
          _ready = false;
          _error = 'Error del reproductor: $error';
          _overlayVisible = true;
        });
      },
    );
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 850),
      (_) => unawaited(_refreshProgress()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _showOverlay();
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final id = await _player.invokeMethod<int>(
        'initialize',
        <String, Object?>{
          'minBuffer': 5000,
          'maxBuffer': 18000,
          'bufferForPlayback': 2500,
          'bufferForPlaybackAfterRebuffer': 1200,
        },
      );
      if (!mounted) return;
      setState(() => _textureId = id);
      await _prepareCurrent();
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _buffering = false;
        _ready = false;
        _error = e.message ?? e.code;
        _overlayVisible = true;
      });
    }
  }

  Future<void> _prepareCurrent({int positionMs = 0}) async {
    if (widget.playlist.isEmpty || _textureId == null) return;
    final generation = ++_openGeneration;
    setState(() {
      _buffering = true;
      _ready = false;
      _playing = true;
      _error = null;
      _codecWarning = null;
      _positionMs = positionMs;
      _durationMs = 0;
      _audioTracks = const [];
      _subtitleTracks = const [];
    });

    final headers = Map<String, String>.from(_headers);
    String? userAgent;
    for (final key in headers.keys.toList()) {
      if (key.toLowerCase() == 'user-agent') {
        userAgent = headers.remove(key);
        break;
      }
    }

    try {
      await _player.invokeMethod<void>('prepare', <String, Object?>{
        'url': _channel.url,
        'headers': headers,
        'userAgent': userAgent ?? _vodUserAgent,
        'isLive': false,
        'position': positionMs,
      });
      if (!mounted || generation != _openGeneration) return;
      _showOverlay();
    } on PlatformException catch (e) {
      if (!mounted || generation != _openGeneration) return;
      setState(() {
        _buffering = false;
        _ready = false;
        _error = e.message ?? e.code;
        _overlayVisible = true;
      });
    }
  }

  List<_TrackOption> _readTracks(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((value) => _TrackOption.fromMap(value.cast<Object?, Object?>()))
        .toList(growable: false);
  }

  void _onNativeEvent(dynamic raw) {
    if (!mounted || raw is! Map) return;
    final event = raw.cast<Object?, Object?>();
    switch (event['eventType']?.toString()) {
      case 'bufferingStart':
        setState(() => _buffering = true);
        break;
      case 'prepared':
      case 'bufferingEnd':
        setState(() {
          _buffering = false;
          _ready = true;
          _playing = true;
          _error = null;
        });
        unawaited(_refreshProgress());
        _showOverlay();
        break;
      case 'tracksChanged':
        setState(() {
          _audioTracks = _readTracks(event['audioTracks']);
          _subtitleTracks = _readTracks(event['textTracks']);
        });
        break;
      case 'codecError':
        setState(() {
          _codecWarning =
              '${event['kind'] ?? 'codec'}: ${event['error'] ?? 'error'}';
        });
        break;
      case 'videoSize':
        final width = (event['width'] as num?)?.toDouble() ?? 0.0;
        final height = (event['height'] as num?)?.toDouble() ?? 0.0;
        final pixelRatio =
            (event['pixelWidthHeightRatio'] as num?)?.toDouble() ?? 1.0;
        if (width > 0 && height > 0) {
          final ratio = (width * (pixelRatio > 0 ? pixelRatio : 1.0)) / height;
          if (ratio > 0.5 && ratio < 3.0) setState(() => _aspectRatio = ratio);
        }
        break;
      case 'videoError':
        _overlayTimer?.cancel();
        final base = event['error']?.toString() ?? 'No se pudo abrir el video';
        setState(() {
          _buffering = false;
          _ready = false;
          _playing = false;
          _error = _codecWarning == null ? base : '$base\n$_codecWarning';
          _overlayVisible = true;
        });
        break;
      case 'completed':
        if (_index < widget.playlist.length - 1) {
          unawaited(_next());
        } else {
          setState(() {
            _playing = false;
            _positionMs = _durationMs;
            _overlayVisible = true;
          });
        }
        break;
    }
  }

  Future<void> _refreshProgress() async {
    if (!_ready || !mounted) return;
    try {
      final values = await Future.wait<Object?>([
        _player.invokeMethod<int>('getCurrentPosition'),
        _player.invokeMethod<int>('getDuration'),
      ]);
      if (!mounted) return;
      final position = (values[0] as int?) ?? 0;
      final duration = (values[1] as int?) ?? 0;
      if (position != _positionMs || duration != _durationMs) {
        setState(() {
          _positionMs = position.clamp(0, duration > 0 ? duration : 1 << 31);
          _durationMs = duration < 0 ? 0 : duration;
        });
      }
    } catch (_) {}
  }

  void _showOverlay() {
    _overlayTimer?.cancel();
    if (mounted && !_overlayVisible) setState(() => _overlayVisible = true);
    _overlayTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _error != null || _buffering) return;
      setState(() => _overlayVisible = false);
    });
  }

  Future<void> _togglePlayPause() async {
    if (!_ready) return;
    if (_playing) {
      await _player.invokeMethod<void>('pause');
    } else {
      await _player.invokeMethod<void>('play');
    }
    if (!mounted) return;
    setState(() => _playing = !_playing);
    _showOverlay();
  }

  Future<void> _seekBy(int deltaMs) async {
    if (!_ready) return;
    final max = _durationMs > 0 ? _durationMs : 1 << 31;
    final target = (_positionMs + deltaMs).clamp(0, max);
    await _player.invokeMethod<void>('seekTo', <String, Object?>{
      'position': target,
    });
    if (mounted) setState(() => _positionMs = target);
    _showOverlay();
  }

  Future<void> _previous() async {
    if (_index <= 0) {
      await _seekBy(-10000);
      return;
    }
    setState(() => _index--);
    await _prepareCurrent();
  }

  Future<void> _next() async {
    if (_index >= widget.playlist.length - 1) return;
    setState(() => _index++);
    await _prepareCurrent();
  }

  Future<void> _selectAudio(_TrackOption? track) async {
    await _player.invokeMethod<void>(
      'setAudioTrack',
      track == null
          ? <String, Object?>{'auto': true}
          : <String, Object?>{
              'groupIndex': track.groupIndex,
              'trackIndex': track.trackIndex,
            },
    );
    _showOverlay();
  }

  Future<void> _selectSubtitle(_TrackOption? track, {bool off = false}) async {
    await _player.invokeMethod<void>(
      'setSubtitleTrack',
      off
          ? <String, Object?>{'off': true}
          : track == null
              ? <String, Object?>{'auto': true}
              : <String, Object?>{
                  'groupIndex': track.groupIndex,
                  'trackIndex': track.trackIndex,
                },
    );
    _showOverlay();
  }

  Future<void> _showTrackMenu() async {
    _overlayTimer?.cancel();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Audio y subtítulos'),
        content: SizedBox(
          width: 620,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'AUDIO',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded),
                title: const Text('Automático'),
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(_selectAudio(null));
                },
              ),
              ..._audioTracks.map(
                (track) => ListTile(
                  leading: const Icon(Icons.volume_up_rounded),
                  title: Text(track.displayName),
                  trailing:
                      track.selected ? const Icon(Icons.check_rounded) : null,
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    unawaited(_selectAudio(track));
                  },
                ),
              ),
              const Divider(),
              const Text(
                'SUBTÍTULOS',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              ListTile(
                leading: const Icon(Icons.subtitles_off_rounded),
                title: const Text('Desactivados'),
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(_selectSubtitle(null, off: true));
                },
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded),
                title: const Text('Automático'),
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(_selectSubtitle(null));
                },
              ),
              ..._subtitleTracks.map(
                (track) => ListTile(
                  leading: const Icon(Icons.subtitles_rounded),
                  title: Text(track.displayName),
                  trailing:
                      track.selected ? const Icon(Icons.check_rounded) : null,
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    unawaited(_selectSubtitle(track));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) _showOverlay();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final wasVisible = _overlayVisible;
    _showOverlay();

    if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(_seekBy(-10000));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(_seekBy(10000));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.arrowUp) {
      unawaited(_previous());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.arrowDown) {
      unawaited(_next());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (wasVisible) unawaited(_togglePlayPause());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _clock(int ms) {
    final total = (ms / 1000).floor().clamp(0, 24 * 60 * 60 * 10);
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _openGeneration++;
    _overlayTimer?.cancel();
    _progressTimer?.cancel();
    _eventSub?.cancel();
    _focusNode.dispose();
    unawaited(_player.invokeMethod<void>('dispose'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.playlist.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('No hay contenido para reproducir.')),
      );
    }

    final progress = _durationMs > 0
        ? (_positionMs / _durationMs).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _aspectRatio,
                child: _textureId == null
                    ? const SizedBox.shrink()
                    : Texture(
                        textureId: _textureId!,
                        filterQuality: FilterQuality.none,
                      ),
              ),
            ),
            if (_buffering && _error == null)
              const Center(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            if (_error != null)
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 620),
                  margin: const EdgeInsets.all(30),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xE814202D),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.movie_filter_rounded, size: 42),
                      const SizedBox(height: 10),
                      Text(
                        _channel.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: () => unawaited(
                              _prepareCurrent(positionMs: _positionMs),
                            ),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Reintentar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('Volver al catálogo'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (_overlayVisible && _error == null)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xD90A1018),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(value: progress, minHeight: 2),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _channel.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(_clock(_positionMs)),
                            IconButton(
                              tooltip: 'Retroceder 10 segundos',
                              onPressed: () => unawaited(_seekBy(-10000)),
                              icon: const Icon(Icons.replay_10_rounded),
                            ),
                            IconButton(
                              tooltip: _playing ? 'Pausar' : 'Reproducir',
                              onPressed: () => unawaited(_togglePlayPause()),
                              icon: Icon(
                                _playing
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                size: 34,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Adelantar 10 segundos',
                              onPressed: () => unawaited(_seekBy(10000)),
                              icon: const Icon(Icons.forward_10_rounded),
                            ),
                            Text(
                              _durationMs > 0 ? _clock(_durationMs) : '--:--',
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Audio y subtítulos',
                              onPressed: _ready
                                  ? () => unawaited(_showTrackMenu())
                                  : null,
                              icon: const Icon(Icons.tune_rounded),
                            ),
                            TextButton.icon(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(
                                Icons.grid_view_rounded,
                                size: 20,
                              ),
                              label: const Text('Catálogo'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrackOption {
  final int groupIndex;
  final int trackIndex;
  final String label;
  final String language;
  final String mimeType;
  final bool selected;

  const _TrackOption({
    required this.groupIndex,
    required this.trackIndex,
    required this.label,
    required this.language,
    required this.mimeType,
    required this.selected,
  });

  factory _TrackOption.fromMap(Map<Object?, Object?> value) {
    return _TrackOption(
      groupIndex: (value['groupIndex'] as num?)?.toInt() ?? 0,
      trackIndex: (value['trackIndex'] as num?)?.toInt() ?? 0,
      label: value['label']?.toString() ?? '',
      language: value['language']?.toString() ?? '',
      mimeType: value['mimeType']?.toString() ?? '',
      selected: value['selected'] == true,
    );
  }

  String get displayName {
    if (label.trim().isNotEmpty && language.trim().isNotEmpty) {
      return '$label · $language';
    }
    if (label.trim().isNotEmpty) return label;
    if (language.trim().isNotEmpty) return language;
    if (mimeType.trim().isNotEmpty) return mimeType;
    return 'Pista ${trackIndex + 1}';
  }
}
