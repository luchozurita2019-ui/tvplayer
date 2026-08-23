from pathlib import Path
import re

ROOT = Path('.')
PLAYER = ROOT / 'lib/screens/player_screen.dart'
VOD_SCREEN = ROOT / 'lib/screens/android_media3_vod_player_screen.dart'
REMOTE = ROOT / 'lib/services/remote_provisioning_service.dart'
MAIN = next((ROOT / 'android/app/src/main/kotlin').rglob('MainActivity.kt'))
GRADLE = ROOT / 'android/app/build.gradle.kts'
MANIFEST = ROOT / 'android/app/src/main/AndroidManifest.xml'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Marcador no encontrado: {label}')
    return text.replace(old, new, 1)


def patch_player_wrapper():
    text = PLAYER.read_text()
    live_import = "import 'android_media3_texture_player_screen.dart';"
    vod_import = "import 'android_media3_vod_player_screen.dart';"
    if vod_import not in text:
        text = replace_once(
            text,
            live_import,
            live_import + "\n" + vod_import,
            'import Media3 VOD',
        )

    old = '''    if (useNativeMedia3Texture) {
      return AndroidMedia3TexturePlayerScreen(
        playlist: playlist,
        initialIndex: initialIndex,
      );
    }

    return _MpvPlayerScreen(
'''
    new = '''    if (useNativeMedia3Texture) {
      return AndroidMedia3TexturePlayerScreen(
        playlist: playlist,
        initialIndex: initialIndex,
      );
    }

    final useNativeMedia3Vod =
        _androidTvBuild &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        !isLiveContent;

    if (useNativeMedia3Vod) {
      return AndroidMedia3VodPlayerScreen(
        playlist: playlist,
        initialIndex: initialIndex,
      );
    }

    return _MpvPlayerScreen(
'''
    text = replace_once(text, old, new, 'ruta VOD Android TV')
    PLAYER.write_text(text)


def write_vod_screen():
    VOD_SCREEN.write_text(r'''import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

const String _vodUserAgent =
    'Mozilla/5.0 (Linux; Android 10; Android TV) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/131.0.0.0 Safari/537.36';

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

  final FocusNode _focusNode = FocusNode(debugLabel: 'media3-vod-player');
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
  int _positionMs = 0;
  int _durationMs = 0;
  int _openGeneration = 0;

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
        });
      },
    );
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 700),
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
      final id = await _player.invokeMethod<int>('initialize', <String, Object?>{
        'minBuffer': 5000,
        'maxBuffer': 15000,
        'bufferForPlayback': 2500,
        'bufferForPlaybackAfterRebuffer': 1000,
      });
      if (!mounted) return;
      setState(() => _textureId = id);
      await _prepareCurrent();
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _buffering = false;
        _ready = false;
        _error = e.message ?? e.code;
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
      _positionMs = positionMs;
      _durationMs = 0;
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
      });
      if (positionMs > 0) {
        await _player.invokeMethod<void>('seekTo', <String, Object?>{
          'position': positionMs,
        });
      }
      if (!mounted || generation != _openGeneration) return;
      _showOverlay();
    } on PlatformException catch (e) {
      if (!mounted || generation != _openGeneration) return;
      setState(() {
        _buffering = false;
        _ready = false;
        _error = e.message ?? e.code;
      });
    }
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
      case 'videoSize':
        final width = (event['width'] as num?)?.toDouble() ?? 0.0;
        final height = (event['height'] as num?)?.toDouble() ?? 0.0;
        final pixelRatio =
            (event['pixelWidthHeightRatio'] as num?)?.toDouble() ?? 1.0;
        if (width > 0 && height > 0) {
          final ratio = (width * (pixelRatio > 0 ? pixelRatio : 1.0)) / height;
          if (ratio > 0.5 && ratio < 3.0) {
            setState(() => _aspectRatio = ratio);
          }
        }
        break;
      case 'videoError':
        setState(() {
          _buffering = false;
          _ready = false;
          _playing = false;
          _error = event['error']?.toString() ?? 'No se pudo abrir el video';
        });
        _overlayTimer?.cancel();
        setState(() => _overlayVisible = true);
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
    } catch (_) {
      // El progreso es auxiliar; nunca debe cerrar la reproducción.
    }
  }

  void _showOverlay() {
    _overlayTimer?.cancel();
    if (mounted && !_overlayVisible) {
      setState(() => _overlayVisible = true);
    }
    _overlayTimer = Timer(const Duration(seconds: 5), () {
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
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
    if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.arrowDown) {
      unawaited(_next());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      unawaited(_togglePlayPause());
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

    return PopScope(
      canPop: true,
      child: Scaffold(
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
                    width: 46,
                    height: 46,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              if (_error != null)
                Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 620),
                    margin: const EdgeInsets.all(32),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xE814202D),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: .4)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.movie_filter_rounded, size: 46),
                        const SizedBox(height: 12),
                        Text(
                          _channel.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: () => unawaited(_prepareCurrent(positionMs: _positionMs)),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_overlayVisible && _error == null)
                SafeArea(
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.all(18),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xD9101722),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Volver',
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _channel.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (widget.playlist.length > 1)
                              Text('${_index + 1}/${widget.playlist.length}'),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        margin: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                        decoration: BoxDecoration(
                          color: const Color(0xE0101722),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LinearProgressIndicator(value: progress, minHeight: 5),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Text(_clock(_positionMs)),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Retroceder 10 segundos',
                                  onPressed: () => unawaited(_seekBy(-10000)),
                                  icon: const Icon(Icons.replay_10_rounded),
                                ),
                                IconButton(
                                  tooltip: _playing ? 'Pausar' : 'Reproducir',
                                  onPressed: () => unawaited(_togglePlayPause()),
                                  icon: Icon(
                                    _playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                                    size: 38,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Adelantar 10 segundos',
                                  onPressed: () => unawaited(_seekBy(10000)),
                                  icon: const Icon(Icons.forward_10_rounded),
                                ),
                                const Spacer(),
                                Text(_durationMs > 0 ? _clock(_durationMs) : '--:--'),
                              ],
                            ),
                            if (widget.playlist.length > 1)
                              Text(
                                '↑ episodio anterior · ↓ episodio siguiente · ←/→ 10 s',
                                style: const TextStyle(fontSize: 11, color: Colors.white60),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
''')


def patch_native_bridge():
    text = MAIN.read_text()

    dispose_marker = '''            "dispose" -> {
                disposePlayer()
                result.success(null)
            }
'''
    methods = '''            "seekTo" -> {
                val raw = call.argument<Number>("position")?.toLong() ?: 0L
                val duration = player?.duration ?: 0L
                val target = if (duration > 0) raw.coerceIn(0L, duration) else raw.coerceAtLeast(0L)
                player?.seekTo(target)
                result.success(null)
            }
            "getCurrentPosition" -> {
                result.success((player?.currentPosition ?: 0L).coerceAtLeast(0L))
            }
            "getBufferedPosition" -> {
                result.success((player?.bufferedPosition ?: 0L).coerceAtLeast(0L))
            }
            "getDuration" -> {
                val value = player?.duration ?: 0L
                result.success(if (value < 0L || value == C.TIME_UNSET) 0L else value)
            }
            "dispose" -> {
                disposePlayer()
                result.success(null)
            }
'''
    text = replace_once(text, dispose_marker, methods, 'metodos VOD nativos')

    old_timeout = '''        startupTimeout = Runnable {
            if (generation != playbackGeneration) return@Runnable
            val current = player ?: return@Runnable
            if (current.playbackState != Player.STATE_READY) {
                current.stop()
                eventSink?.success(
                    mapOf(
                        "eventType" to "videoError",
                        "error" to "El canal no entregó señal en 5 segundos",
                    )
                )
            }
        }.also { handler.postDelayed(it, STARTUP_TIMEOUT_MS) }
'''
    new_timeout = '''        val timeoutMs = if (isLive) STARTUP_TIMEOUT_MS else 12000L
        startupTimeout = Runnable {
            if (generation != playbackGeneration) return@Runnable
            val current = player ?: return@Runnable
            if (current.playbackState != Player.STATE_READY) {
                current.stop()
                eventSink?.success(
                    mapOf(
                        "eventType" to "videoError",
                        "error" to if (isLive)
                            "El canal no entregó señal en 5 segundos"
                        else
                            "El video no pudo iniciar en 12 segundos",
                    )
                )
            }
        }.also { handler.postDelayed(it, timeoutMs) }
'''
    text = replace_once(text, old_timeout, new_timeout, 'timeout VOD')

    old_video = '''                    "width" to videoSize.width,
                    "height" to videoSize.height,
'''
    new_video = '''                    "width" to videoSize.width,
                    "height" to videoSize.height,
                    "pixelWidthHeightRatio" to videoSize.pixelWidthHeightRatio,
'''
    text = replace_once(text, old_video, new_video, 'pixel aspect ratio')

    MAIN.write_text(text)


def patch_package_and_version():
    gradle = GRADLE.read_text()
    gradle = gradle.replace(
        'applicationId = "com.tvfull.pro.tv.v6texture"',
        'applicationId = "com.tvfull.pro.tv.v8media3"',
    )
    GRADLE.write_text(gradle)

    manifest = MANIFEST.read_text()
    manifest = manifest.replace('TV FULL PRO V6 TEXTURE', 'TV FULL PRO V8 MEDIA3')
    MANIFEST.write_text(manifest)

    if REMOTE.exists():
        remote = REMOTE.read_text()
        remote = re.sub(
            r'1\.0\.0\+1-android-tv-[A-Za-z0-9._-]+',
            '1.0.0+1-android-tv-v6-vod-media3-v8',
            remote,
        )
        REMOTE.write_text(remote)


def validate():
    p = PLAYER.read_text()
    for marker in [
        "import 'android_media3_vod_player_screen.dart';",
        'AndroidMedia3VodPlayerScreen(',
        '!isLiveContent',
    ]:
        if marker not in p:
            raise SystemExit(f'Falta marcador PlayerScreen: {marker}')

    v = VOD_SCREEN.read_text()
    for marker in ['Texture(', "invokeMethod<int>('getDuration')", "'isLive': false"]:
        if marker not in v:
            raise SystemExit(f'Falta marcador VOD: {marker}')

    n = MAIN.read_text()
    for marker in ['"seekTo" ->', '"getDuration" ->', 'timeoutMs = if (isLive)']:
        if marker not in n:
            raise SystemExit(f'Falta marcador nativo: {marker}')


patch_player_wrapper()
write_vod_screen()
patch_native_bridge()
patch_package_and_version()
validate()
print('V8: LIVE V6 intacto + VOD/Series Media3 nativo aplicado correctamente.')
