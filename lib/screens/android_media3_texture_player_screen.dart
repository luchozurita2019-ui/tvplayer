import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';
import '../widgets/cached_artwork_image.dart';

const String _media3DefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/96.0.4664.18 Safari/537.36';

class AndroidMedia3TexturePlayerScreen extends StatefulWidget {
  final List<Channel> playlist;
  final int initialIndex;

  const AndroidMedia3TexturePlayerScreen({
    super.key,
    required this.playlist,
    required this.initialIndex,
  });

  @override
  State<AndroidMedia3TexturePlayerScreen> createState() =>
      _AndroidMedia3TexturePlayerScreenState();
}

class _AndroidMedia3TexturePlayerScreenState
    extends State<AndroidMedia3TexturePlayerScreen> {
  static const MethodChannel _player = MethodChannel('tvfull/media3_texture');
  static const EventChannel _events = EventChannel('tvfull/media3_texture_events');

  final FocusNode _rootFocus = FocusNode(debugLabel: 'tvfull-pro-live');
  StreamSubscription<dynamic>? _eventSub;
  Timer? _overlayTimer;
  Timer? _retryTimer;

  late int _index;
  int? _textureId;
  double _aspectRatio = 16 / 9;
  bool _overlayVisible = false;
  bool _channelListVisible = false;
  bool _buffering = true;
  bool _ready = false;
  String? _friendlyError;
  String? _technicalError;
  int _openGeneration = 0;
  int _autoRetryCount = 0;

  Channel get _channel => widget.playlist[_index];
  Map<String, String> get _headers =>
      _channel.resolvedHttpHeaders(_media3DefaultUserAgent);

  @override
  void initState() {
    super.initState();
    _index = widget.playlist.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.playlist.length - 1);
    _eventSub = _events.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (Object error) => _finishWithError(
        'Problema de reproducción',
        error.toString(),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rootFocus.requestFocus();
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final id = await _player.invokeMethod<int>('initialize', {
        'minBuffer': 3500,
        'maxBuffer': 12000,
        'bufferForPlayback': 1500,
        'bufferForPlaybackAfterRebuffer': 800,
      });
      if (!mounted) return;
      setState(() => _textureId = id);
      if (widget.playlist.isNotEmpty) await _prepareCurrent();
    } on PlatformException catch (error) {
      _finishWithError('No se pudo iniciar el reproductor', error.message ?? error.code);
    }
  }

  Future<void> _prepareCurrent({bool preserveRetry = false}) async {
    if (widget.playlist.isEmpty || _textureId == null) return;
    final generation = ++_openGeneration;
    _retryTimer?.cancel();
    if (!preserveRetry) _autoRetryCount = 0;
    if (mounted) {
      setState(() {
        _buffering = true;
        _ready = false;
        _friendlyError = null;
        _technicalError = null;
        _channelListVisible = false;
      });
    }

    final headers = Map<String, String>.from(_headers);
    String? userAgent;
    for (final key in headers.keys.toList()) {
      if (key.toLowerCase() == 'user-agent') {
        userAgent = headers.remove(key);
        break;
      }
    }

    try {
      await _player.invokeMethod<void>('prepare', {
        'url': _channel.url,
        'headers': headers,
        'userAgent': userAgent ?? _media3DefaultUserAgent,
        'isLive': true,
      });
    } on PlatformException catch (error) {
      if (!mounted || generation != _openGeneration) return;
      _handleTechnicalError(error.code, error.message ?? error.code);
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
        _autoRetryCount = 0;
        setState(() {
          _buffering = false;
          _ready = true;
          _friendlyError = null;
          _technicalError = null;
        });
        break;
      case 'videoSize':
        final width = (event['width'] as num?)?.toDouble() ?? 0;
        final height = (event['height'] as num?)?.toDouble() ?? 0;
        final pixel = (event['pixelWidthHeightRatio'] as num?)?.toDouble() ?? 1;
        if (width > 0 && height > 0) {
          final ratio = width * (pixel > 0 ? pixel : 1) / height;
          if (ratio > .5 && ratio < 3 && mounted) {
            setState(() => _aspectRatio = ratio);
          }
        }
        break;
      case 'videoError':
        final codeName = event['errorCodeName']?.toString() ??
            event['errorCode']?.toString() ?? '';
        final detail = event['error']?.toString() ?? codeName;
        _handleTechnicalError(codeName, detail);
        break;
      case 'completed':
        _handleTechnicalError('STREAM_ENDED', 'La señal terminó inesperadamente.');
        break;
      case 'codecError':
        debugPrint('TV FULL PRO LIVE codec: ${event['error']}');
        break;
    }
  }

  void _handleTechnicalError(String code, String detail) {
    debugPrint('TV FULL PRO LIVE [$code] $detail');
    final combined = '$code $detail'.toLowerCase();
    final transient = combined.contains('http') ||
        combined.contains('network') ||
        combined.contains('timeout') ||
        combined.contains('connection') ||
        combined.contains('stream_ended');

    if (transient && _autoRetryCount < 1) {
      _autoRetryCount++;
      if (mounted) {
        setState(() {
          _buffering = true;
          _friendlyError = null;
        });
      }
      _retryTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) unawaited(_prepareCurrent(preserveRetry: true));
      });
      return;
    }

    _finishWithError(_friendlyMessage(combined), '$code · $detail');
  }

  String _friendlyMessage(String value) {
    if (value.contains('parsing_container') ||
        value.contains('parser') ||
        value.contains('malformed')) {
      return 'Formato de señal no compatible';
    }
    if (value.contains('decoder') || value.contains('codec')) {
      return 'Formato de video no compatible';
    }
    if (value.contains('timeout') ||
        value.contains('network') ||
        value.contains('connection')) {
      return 'Problema de conexión';
    }
    if (value.contains('http') || value.contains('response_code')) {
      return 'Canal no disponible';
    }
    return 'Canal temporalmente no disponible';
  }

  void _finishWithError(String friendly, String technical) {
    debugPrint('TV FULL PRO LIVE error: $technical');
    if (!mounted) return;
    _overlayTimer?.cancel();
    setState(() {
      _buffering = false;
      _ready = false;
      _friendlyError = friendly;
      _technicalError = technical;
      _overlayVisible = false;
      _channelListVisible = false;
    });
  }

  void _showOverlay() {
    _overlayTimer?.cancel();
    if (!_overlayVisible && mounted) setState(() => _overlayVisible = true);
    _overlayTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _channelListVisible || _friendlyError != null) return;
      setState(() => _overlayVisible = false);
    });
  }

  void _openChannelList() {
    _overlayTimer?.cancel();
    setState(() {
      _overlayVisible = true;
      _channelListVisible = true;
    });
  }

  void _selectChannel(int index) {
    if (index < 0 || index >= widget.playlist.length) return;
    setState(() {
      _index = index;
      _channelListVisible = false;
      _overlayVisible = true;
    });
    unawaited(_prepareCurrent());
    _showOverlay();
  }

  void _previous() {
    if (widget.playlist.isEmpty) return;
    _index = (_index - 1 + widget.playlist.length) % widget.playlist.length;
    unawaited(_prepareCurrent());
    _showOverlay();
  }

  void _next() {
    if (widget.playlist.isEmpty) return;
    _index = (_index + 1) % widget.playlist.length;
    unawaited(_prepareCurrent());
    _showOverlay();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_channelListVisible) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_overlayVisible) {
        _openChannelList();
      } else {
        _showOverlay();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.pageUp) {
      _previous();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.pageDown) {
      _next();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _openChannelList();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _openGeneration++;
    _overlayTimer?.cancel();
    _retryTimer?.cancel();
    _eventSub?.cancel();
    _rootFocus.dispose();
    unawaited(_player.invokeMethod<void>('dispose'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.playlist.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('No hay canales para reproducir.')),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootFocus,
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
                    : Texture(textureId: _textureId!, filterQuality: FilterQuality.none),
              ),
            ),
            if (_buffering && _friendlyError == null)
              const Center(
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            if (_friendlyError != null) _errorCard(),
            if (_overlayVisible && _friendlyError == null) _liveHud(),
            if (_channelListVisible) _channelDrawer(),
          ],
        ),
      ),
    );
  }

  Widget _liveHud() => SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 64,
            margin: const EdgeInsets.fromLTRB(24, 0, 24, 18),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: const Color(0xE80A1017),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  width: 130,
                  height: 2,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.circle, size: 10, color: Colors.redAccent),
                const SizedBox(width: 6),
                const Text(
                  'EN VIVO',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 22),
                OutlinedButton.icon(
                  onPressed: _openChannelList,
                  icon: const Icon(Icons.list_rounded, size: 20),
                  label: const Text('Lista de canales'),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _channelDrawer() => Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: const Color(0xF20A1119),
          elevation: 16,
          child: SafeArea(
            child: SizedBox(
              width: 390,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Lista de canales',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() => _channelListVisible = false);
                            _rootFocus.requestFocus();
                            _showOverlay();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
                      cacheExtent: 70,
                      itemCount: widget.playlist.length,
                      itemBuilder: (context, index) {
                        final item = widget.playlist[index];
                        final selected = index == _index;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: ListTile(
                            autofocus: selected,
                            selected: selected,
                            minTileHeight: 54,
                            selectedTileColor: const Color(0xFF1677FF).withValues(alpha: .18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                            leading: SizedBox(
                              width: 36,
                              height: 36,
                              child: CachedArtworkImage(
                                url: item.logoUrl,
                                fit: BoxFit.contain,
                                cacheWidth: 72,
                                cacheHeight: 72,
                                prefetchExtent: 0,
                                fallback: const Icon(Icons.live_tv_rounded, size: 20),
                              ),
                            ),
                            title: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                            onTap: () => _selectChannel(index),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _errorCard() => Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xED10161D),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tv_off_rounded, size: 42, color: Colors.white54),
              const SizedBox(height: 12),
              Text(
                _friendlyError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Probá nuevamente o elegí otro canal.',
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    autofocus: true,
                    onPressed: () => unawaited(_prepareCurrent()),
                    child: const Text('Reintentar'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _openChannelList,
                    child: const Text('Lista de canales'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}
