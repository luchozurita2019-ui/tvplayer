import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

const String _vodUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/96.0.4664.18 Safari/537.36';

const Map<String, String> _trackLanguageNames = {
  'es': 'Español',
  'spa': 'Español',
  'en': 'Inglés',
  'eng': 'Inglés',
  'pt': 'Portugués',
  'por': 'Portugués',
  'fr': 'Francés',
  'fra': 'Francés',
  'fre': 'Francés',
  'it': 'Italiano',
  'ita': 'Italiano',
  'de': 'Alemán',
  'deu': 'Alemán',
  'ger': 'Alemán',
  'ja': 'Japonés',
  'jpn': 'Japonés',
  'ko': 'Coreano',
  'kor': 'Coreano',
  'zh': 'Chino',
  'zho': 'Chino',
  'chi': 'Chino',
  'ru': 'Ruso',
  'rus': 'Ruso',
  'ar': 'Árabe',
  'ara': 'Árabe',
  'hi': 'Hindi',
  'hin': 'Hindi',
  'tr': 'Turco',
  'tur': 'Turco',
  'nl': 'Neerlandés',
  'nld': 'Neerlandés',
  'dut': 'Neerlandés',
  'pl': 'Polaco',
  'pol': 'Polaco',
  'ca': 'Catalán',
  'cat': 'Catalán',
  'eu': 'Euskera',
  'eus': 'Euskera',
  'baq': 'Euskera',
  'gl': 'Gallego',
  'glg': 'Gallego',
  'ro': 'Rumano',
  'ron': 'Rumano',
  'rum': 'Rumano',
  'uk': 'Ucraniano',
  'ukr': 'Ucraniano',
  'cs': 'Checo',
  'ces': 'Checo',
  'cze': 'Checo',
  'da': 'Danés',
  'dan': 'Danés',
  'sv': 'Sueco',
  'swe': 'Sueco',
  'no': 'Noruego',
  'nor': 'Noruego',
  'fi': 'Finlandés',
  'fin': 'Finlandés',
  'el': 'Griego',
  'ell': 'Griego',
  'gre': 'Griego',
  'he': 'Hebreo',
  'heb': 'Hebreo',
  'id': 'Indonesio',
  'ind': 'Indonesio',
  'vi': 'Vietnamita',
  'vie': 'Vietnamita',
  'th': 'Tailandés',
  'tha': 'Tailandés',
  'hu': 'Húngaro',
  'hun': 'Húngaro',
  'bg': 'Búlgaro',
  'bul': 'Búlgaro',
  'hr': 'Croata',
  'hrv': 'Croata',
  'sr': 'Serbio',
  'srp': 'Serbio',
  'sk': 'Eslovaco',
  'slk': 'Eslovaco',
  'slo': 'Eslovaco',
  'sl': 'Esloveno',
  'slv': 'Esloveno',
  'fa': 'Persa',
  'fas': 'Persa',
  'per': 'Persa',
};

String _friendlyTrackLanguage(String language, String label) {
  final rawLanguage = language.trim().toLowerCase();
  final rawLabel = label.trim();
  final probe = '$rawLanguage ${rawLabel.toLowerCase()}';

  if (probe.contains('latino') || probe.contains('latin spanish')) {
    return 'Español Latino';
  }
  if (probe.contains('castellano') ||
      probe.contains('spanish') ||
      probe.contains('español') ||
      probe.contains('espanol')) {
    return 'Español';
  }
  if (probe.contains('english') || probe.contains('inglés') || probe.contains('ingles')) {
    return 'Inglés';
  }
  if (probe.contains('portuguese') || probe.contains('português') || probe.contains('portugues')) {
    return 'Portugués';
  }
  if (probe.contains('french') || probe.contains('français') || probe.contains('frances')) {
    return 'Francés';
  }
  if (probe.contains('italian') || probe.contains('italiano')) return 'Italiano';
  if (probe.contains('german') || probe.contains('deutsch') || probe.contains('alemán')) {
    return 'Alemán';
  }

  final code = rawLanguage.split(RegExp(r'[-_]')).first;
  final mapped = _trackLanguageNames[code];
  if (mapped != null) return mapped;

  if (rawLabel.isNotEmpty) {
    final technical = RegExp(
      r'^(audio/|text/|application/)|\b(aac|ac3|eac3|mp3|opus|stereo|mono|5\.1|7\.1|track|pista)\b',
      caseSensitive: false,
    ).hasMatch(rawLabel);
    if (!technical) return rawLabel;
  }

  if (code.isNotEmpty && code != 'und') return code.toUpperCase();
  return 'Idioma no especificado';
}

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

  final FocusNode _rootFocus = FocusNode(debugLabel: 'tvfull-vod-root');
  final FocusNode _rewindFocus = FocusNode(debugLabel: 'tvfull-vod-rewind');
  final FocusNode _playFocus = FocusNode(debugLabel: 'tvfull-vod-play');
  final FocusNode _forwardFocus = FocusNode(debugLabel: 'tvfull-vod-forward');
  final FocusNode _tracksFocus = FocusNode(debugLabel: 'tvfull-vod-tracks');

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
  bool _seekable = false;
  String? _error;
  String? _codecWarning;
  int _positionMs = 0;
  int _bufferedMs = 0;
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
      const Duration(seconds: 1),
      (_) => unawaited(_refreshProgress()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rootFocus.requestFocus();
      _showOverlay();
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final id = await _player.invokeMethod<int>(
        'initialize',
        <String, Object?>{
          // VOD gets its own buffering profile. LIVE uses a separate call and
          // keeps its existing low-latency values untouched.
          'minBuffer': 15000,
          'maxBuffer': 90000,
          'bufferForPlayback': 1500,
          'bufferForPlaybackAfterRebuffer': 2500,
          'backBuffer': 30000,
          'retainBackBufferFromKeyframe': true,
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
      _seekable = false;
      _error = null;
      _codecWarning = null;
      _positionMs = positionMs;
      _bufferedMs = positionMs;
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
        .where((track) => track.supported)
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
            _bufferedMs = _durationMs;
            _overlayVisible = true;
          });
        }
        break;
    }
  }

  Future<void> _refreshProgress() async {
    if (!_ready || !mounted) return;
    try {
      final raw = await _player.invokeMethod<Map<dynamic, dynamic>>(
        'getPlaybackSnapshot',
      );
      if (!mounted || raw == null) return;
      final position = (raw['position'] as num?)?.toInt() ?? 0;
      final buffered = (raw['bufferedPosition'] as num?)?.toInt() ?? position;
      final duration = (raw['duration'] as num?)?.toInt() ?? 0;
      final seekable = raw['seekable'] == true;
      final nativeLive = raw['live'] == true;
      if (nativeLive) {
        debugPrint(
          'TV FULL PRO VOD: el proveedor reportó timeline LIVE para ${_channel.name}',
        );
      }
      final safeDuration = duration < 0 ? 0 : duration;
      final maxPosition = safeDuration > 0 ? safeDuration : 1 << 31;
      final safePosition = position.clamp(0, maxPosition);
      final safeBuffered = buffered.clamp(safePosition, maxPosition);
      if (safePosition != _positionMs ||
          safeBuffered != _bufferedMs ||
          safeDuration != _durationMs ||
          seekable != _seekable) {
        setState(() {
          _positionMs = safePosition;
          _bufferedMs = safeBuffered;
          _durationMs = safeDuration;
          _seekable = seekable;
        });
      }
    } catch (_) {}
  }

  void _showOverlay({FocusNode? focus}) {
    _overlayTimer?.cancel();
    if (mounted && !_overlayVisible) setState(() => _overlayVisible = true);
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && focus.canRequestFocus) focus.requestFocus();
      });
    }
    _overlayTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted || _error != null || _buffering) return;
      setState(() => _overlayVisible = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rootFocus.requestFocus();
      });
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
    _showOverlay(focus: _playFocus);
  }

  Future<void> _seekBy(int deltaMs) async {
    if (!_ready) return;
    final max = _durationMs > 0 ? _durationMs : 1 << 31;
    final target = (_positionMs + deltaMs).clamp(0, max);
    await _player.invokeMethod<void>('seekTo', <String, Object?>{
      'position': target,
    });
    if (!mounted) return;
    setState(() {
      _positionMs = target;
      if (_bufferedMs < target) _bufferedMs = target;
    });
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

  Future<void> _selectAudio(_TrackOption track) async {
    await _player.invokeMethod<void>('setAudioTrack', <String, Object?>{
      'groupIndex': track.groupIndex,
      'trackIndex': track.trackIndex,
    });
    _showOverlay(focus: _tracksFocus);
  }

  Future<void> _selectSubtitle(_TrackOption? track, {bool off = false}) async {
    if (!off && track == null) return;
    await _player.invokeMethod<void>(
      'setSubtitleTrack',
      off
          ? <String, Object?>{'off': true}
          : <String, Object?>{
              'groupIndex': track!.groupIndex,
              'trackIndex': track.trackIndex,
            },
    );
    _showOverlay(focus: _tracksFocus);
  }

  String _menuTrackName(_TrackOption track, List<_TrackOption> tracks) {
    final base = track.friendlyLanguageName;
    final sameLanguage = tracks
        .where((item) => item.friendlyLanguageName == base)
        .toList(growable: false);
    if (sameLanguage.length <= 1) return base;
    final index = sameLanguage.indexWhere(
      (item) =>
          item.groupIndex == track.groupIndex && item.trackIndex == track.trackIndex,
    );
    return '$base ${index >= 0 ? index + 1 : track.trackIndex + 1}';
  }

  Future<void> _showTrackMenu() async {
    _overlayTimer?.cancel();
    final subtitlesOff = !_subtitleTracks.any((track) => track.selected);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Idioma de audio y subtítulos'),
        content: SizedBox(
          width: 620,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'IDIOMA DE AUDIO',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              if (_audioTracks.isEmpty)
                const ListTile(
                  enabled: false,
                  leading: Icon(Icons.volume_off_rounded),
                  title: Text('No hay pistas de audio seleccionables'),
                )
              else
                ...List.generate(_audioTracks.length, (index) {
                  final track = _audioTracks[index];
                  return ListTile(
                    autofocus: index == 0,
                    focusColor: const Color(0xFF12324A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                    leading: const Icon(Icons.volume_up_rounded),
                    title: Text(_menuTrackName(track, _audioTracks)),
                    trailing:
                        track.selected ? const Icon(Icons.check_rounded) : null,
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      unawaited(_selectAudio(track));
                    },
                  );
                }),
              const Divider(),
              const Text(
                'SUBTÍTULOS',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              ListTile(
                autofocus: _audioTracks.isEmpty,
                focusColor: const Color(0xFF12324A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                leading: const Icon(Icons.subtitles_off_rounded),
                title: const Text('Desactivados'),
                trailing: subtitlesOff ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(_selectSubtitle(null, off: true));
                },
              ),
              if (_subtitleTracks.isEmpty)
                const ListTile(
                  enabled: false,
                  leading: Icon(Icons.subtitles_rounded),
                  title: Text('Este contenido no incluye subtítulos'),
                )
              else
                ...List.generate(_subtitleTracks.length, (index) {
                  final track = _subtitleTracks[index];
                  return ListTile(
                    focusColor: const Color(0xFF12324A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                    leading: const Icon(Icons.subtitles_rounded),
                    title: Text(_menuTrackName(track, _subtitleTracks)),
                    trailing:
                        track.selected ? const Icon(Icons.check_rounded) : null,
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      unawaited(_selectSubtitle(track));
                    },
                  );
                }),
            ],
          ),
        ),
      ),
    );
    if (mounted) _showOverlay(focus: _tracksFocus);
  }

  KeyEventResult _onRootKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !node.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.mediaPlayPause) {
      unawaited(_togglePlayPause());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      unawaited(_previous());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      unawaited(_next());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _showOverlay(focus: _rewindFocus);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _showOverlay(focus: _forwardFocus);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _showOverlay(focus: _playFocus);
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
    _rootFocus.dispose();
    _rewindFocus.dispose();
    _playFocus.dispose();
    _forwardFocus.dispose();
    _tracksFocus.dispose();
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

    final played = _durationMs > 0
        ? (_positionMs / _durationMs).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final buffered = _durationMs > 0
        ? (_bufferedMs / _durationMs).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _onRootKey,
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
                            autofocus: true,
                            onPressed: () => unawaited(
                              _prepareCurrent(positionMs: _positionMs),
                            ),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Reintentar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('Volver'),
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: const Color(0xD90A1018),
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
                                _channel.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (!_seekable && _durationMs > 0)
                              const Text(
                                'Buscando información de navegación…',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        _VodTimeline(played: played, buffered: buffered),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              _clock(_positionMs),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (_durationMs > 0)
                              Text(
                                'Cargado hasta ${_clock(_bufferedMs)}',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                ),
                              ),
                            const Spacer(),
                            Text(
                              _durationMs > 0 ? _clock(_durationMs) : '--:--',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        FocusTraversalGroup(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _VodControlButton(
                                focusNode: _rewindFocus,
                                tooltip: 'Retroceder 10 segundos',
                                icon: Icons.replay_10_rounded,
                                onPressed: _ready
                                    ? () => unawaited(_seekBy(-10000))
                                    : null,
                                onFocus: _showOverlay,
                              ),
                              const SizedBox(width: 8),
                              _VodControlButton(
                                focusNode: _playFocus,
                                tooltip: _playing ? 'Pausar' : 'Reproducir',
                                icon: _playing
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                iconSize: 34,
                                onPressed: _ready
                                    ? () => unawaited(_togglePlayPause())
                                    : null,
                                onFocus: _showOverlay,
                              ),
                              const SizedBox(width: 8),
                              _VodControlButton(
                                focusNode: _forwardFocus,
                                tooltip: 'Adelantar 10 segundos',
                                icon: Icons.forward_10_rounded,
                                onPressed: _ready
                                    ? () => unawaited(_seekBy(10000))
                                    : null,
                                onFocus: _showOverlay,
                              ),
                              const SizedBox(width: 18),
                              _VodControlButton(
                                focusNode: _tracksFocus,
                                tooltip: 'Idioma de audio y subtítulos',
                                icon: Icons.tune_rounded,
                                onPressed: _ready
                                    ? () => unawaited(_showTrackMenu())
                                    : null,
                                onFocus: _showOverlay,
                              ),
                            ],
                          ),
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

class _VodTimeline extends StatelessWidget {
  final double played;
  final double buffered;

  const _VodTimeline({required this.played, required this.buffered});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final playedWidth = width * played.clamp(0.0, 1.0);
          final bufferedWidth = width * buffered.clamp(0.0, 1.0);
          return ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0x33FFFFFF)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: bufferedWidth,
                    child: const ColoredBox(color: Color(0x66FFFFFF)),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: playedWidth,
                    child: const ColoredBox(color: Color(0xFF42AFFF)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VodControlButton extends StatefulWidget {
  final FocusNode focusNode;
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final VoidCallback? onPressed;
  final VoidCallback onFocus;

  const _VodControlButton({
    required this.focusNode,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.onFocus,
    this.iconSize = 26,
  });

  @override
  State<_VodControlButton> createState() => _VodControlButtonState();
}

class _VodControlButtonState extends State<_VodControlButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Material(
        color: _focused ? const Color(0xFF12324A) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          focusNode: widget.focusNode,
          canRequestFocus: widget.onPressed != null,
          borderRadius: BorderRadius.circular(12),
          onFocusChange: (value) {
            setState(() => _focused = value);
            if (value) widget.onFocus();
          },
          onTap: widget.onPressed,
          child: Container(
            width: 52,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused ? const Color(0xFF58B9FF) : Colors.transparent,
              ),
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: widget.onPressed == null ? Colors.white30 : Colors.white,
            ),
          ),
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
  final bool supported;

  const _TrackOption({
    required this.groupIndex,
    required this.trackIndex,
    required this.label,
    required this.language,
    required this.mimeType,
    required this.selected,
    required this.supported,
  });

  factory _TrackOption.fromMap(Map<Object?, Object?> value) {
    return _TrackOption(
      groupIndex: (value['groupIndex'] as num?)?.toInt() ?? 0,
      trackIndex: (value['trackIndex'] as num?)?.toInt() ?? 0,
      label: value['label']?.toString() ?? '',
      language: value['language']?.toString() ?? '',
      mimeType: value['mimeType']?.toString() ?? '',
      selected: value['selected'] == true,
      supported: value['supported'] != false,
    );
  }

  String get friendlyLanguageName => _friendlyTrackLanguage(language, label);
}
