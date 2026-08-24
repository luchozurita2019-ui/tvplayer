import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

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
  static const EventChannel _events = EventChannel(
    'tvfull/media3_texture_events',
  );

  final FocusNode _focusNode = FocusNode(debugLabel: 'tvfull-live-player');
  StreamSubscription<dynamic>? _eventSub;
  Timer? _overlayTimer;
  late int _index;
  int? _textureId;
  double _aspectRatio = 16 / 9;
  bool _overlayVisible = true;
  bool _buffering = true;
  bool _ready = false;
  String? _error;
  int _openGeneration = 0;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _showOverlay();
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final id =
          await _player.invokeMethod<int>('initialize', <String, Object?>{
        'minBuffer': 5000,
        'maxBuffer': 15000,
        'bufferForPlayback': 2500,
        'bufferForPlaybackAfterRebuffer': 1000,
      });
      if (!mounted) return;
      setState(() => _textureId = id);
      if (widget.playlist.isNotEmpty) await _prepareCurrent();
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _buffering = false;
        _error = e.message ?? e.code;
        _overlayVisible = true;
      });
    }
  }

  Future<void> _prepareCurrent() async {
    if (widget.playlist.isEmpty || _textureId == null) return;
    final generation = ++_openGeneration;
    setState(() {
      _buffering = true;
      _ready = false;
      _error = null;
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
        'userAgent': userAgent ?? _media3DefaultUserAgent,
        'isLive': true,
      });
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
          _error = null;
        });
        _showOverlay();
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
        setState(() {
          _buffering = false;
          _ready = false;
          _error = event['error']?.toString() ?? 'Canal no disponible';
          _overlayVisible = true;
        });
        break;
      case 'completed':
        setState(() {
          _buffering = false;
          _ready = false;
          _error = 'La señal terminó inesperadamente.';
          _overlayVisible = true;
        });
        break;
    }
  }

  void _showOverlay() {
    _overlayTimer?.cancel();
    if (mounted && !_overlayVisible) setState(() => _overlayVisible = true);
    _overlayTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _buffering || _error != null) return;
      setState(() => _overlayVisible = false);
    });
  }

  void _hideOverlay() {
    _overlayTimer?.cancel();
    if (mounted) setState(() => _overlayVisible = false);
  }

  void _previous() {
    if (widget.playlist.isEmpty) return;
    setState(() {
      _index = (_index - 1 + widget.playlist.length) % widget.playlist.length;
    });
    _showOverlay();
    unawaited(_prepareCurrent());
  }

  void _next() {
    if (widget.playlist.isEmpty) return;
    setState(() => _index = (_index + 1) % widget.playlist.length);
    _showOverlay();
    unawaited(_prepareCurrent());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_overlayVisible) {
        _hideOverlay();
      } else {
        _showOverlay();
      }
      return KeyEventResult.handled;
    }

    _showOverlay();
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      _previous();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown) {
      _next();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _channelLogo(Channel channel) {
    final url = channel.logoUrl?.trim() ?? '';
    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: url.isEmpty
          ? const Icon(Icons.live_tv_rounded, size: 28)
          : Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.live_tv_rounded, size: 28),
            ),
    );
  }

  @override
  void dispose() {
    _openGeneration++;
    _overlayTimer?.cancel();
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
        body: Center(child: Text('No hay canales para reproducir.')),
      );
    }

    final channel = _channel;
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
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            if (_error != null)
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 540),
                  margin: const EdgeInsets.all(28),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xE814202D),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tv_off_rounded, size: 42),
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => unawaited(_prepareCurrent()),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Reintentar'),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xD90A1018),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        _channelLogo(channel),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: Text(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          '● LIVE',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 14),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.grid_view_rounded, size: 20),
                          label: const Text('Catálogo'),
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
