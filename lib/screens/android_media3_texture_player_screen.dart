import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';
import '../services/device_performance_service.dart';
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
  static const EventChannel _events = EventChannel(
    'tvfull/media3_texture_events',
  );

  final FocusNode _rootFocus = FocusNode(debugLabel: 'tvfull-pro-live');
  final FocusNode _channelListFocus = FocusNode(
    debugLabel: 'tvfull-pro-live-selected-channel',
  );
  final FocusNode _retryFocus = FocusNode(debugLabel: 'tvfull-pro-live-retry');
  final ScrollController _channelScrollController = ScrollController();
  StreamSubscription<dynamic>? _eventSub;
  Timer? _overlayTimer;
  Timer? _retryTimer;

  late int _index;
  int? _textureId;
  double _aspectRatio = 16 / 9;
  bool _overlayVisible = false;
  bool _channelListVisible = false;
  bool _buffering = true;
  String? _friendlyError;
  int _openGeneration = 0;
  int _autoRetryCount = 0;
  List<_LiveAudioTrack> _audioTracks = const <_LiveAudioTrack>[];

  Channel get _channel => widget.playlist[_index];
  Map<String, String> get _headers =>
      _channel.resolvedHttpHeaders(_media3DefaultUserAgent);

  List<_LiveAudioTrack> get _selectableAudioTracks =>
      _audioTracks.where((track) => track.supported).toList(growable: false);

  bool get _hasMultipleAudioTracks => _selectableAudioTracks.length > 1;

  @override
  void initState() {
    super.initState();
    _index = widget.playlist.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.playlist.length - 1);
    _eventSub = _events.receiveBroadcastStream().listen(
          _onNativeEvent,
          onError: (Object error) =>
              _finishWithError('Problema de reproducción', error.toString()),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rootFocus.requestFocus();
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final lowRam = DevicePerformanceService.instance.lowRam;
      var adaptiveLevel = 0;
      if (widget.playlist.isNotEmpty) {
        try {
          adaptiveLevel =
              await _player.invokeMethod<int>('getLiveAdaptiveLevel', {
                    'url': _channel.url,
                  }) ??
                  0;
        } on PlatformException {
          adaptiveLevel = 0;
        }
      }
      final level = adaptiveLevel.clamp(0, 3).toInt();
      final normalMin = <int>[5000, 6000, 7000, 8000][level];
      final normalMax = <int>[15000, 19000, 23000, 28000][level];
      final normalRebuffer = <int>[2500, 3000, 3500, 4000][level];
      final lowRamMin = <int>[4000, 4500, 5000, 5500][level];
      final lowRamMax = <int>[12000, 14000, 16000, 18000][level];
      final lowRamRebuffer = <int>[2200, 2500, 2800, 3000][level];
      final id = await _player.invokeMethod<int>('initialize', {
        // Perfil aprendido por canal: la primera imagen sigue arrancando con
        // 1 s, pero canales problemáticos reciben más reserva de forma local.
        // LOW_RAM mantiene límites estrictos para no castigar hardware modesto.
        'minBuffer': lowRam ? lowRamMin : normalMin,
        'maxBuffer': lowRam ? lowRamMax : normalMax,
        'bufferForPlayback': 1000,
        'bufferForPlaybackAfterRebuffer':
            lowRam ? lowRamRebuffer : normalRebuffer,
      });
      if (!mounted) return;
      setState(() => _textureId = id);
      if (widget.playlist.isNotEmpty) await _prepareCurrent();
    } on PlatformException catch (error) {
      _finishWithError(
        'No se pudo iniciar el reproductor',
        error.message ?? error.code,
      );
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
        _friendlyError = null;
        _channelListVisible = false;
        _audioTracks = const <_LiveAudioTrack>[];
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
          _friendlyError = null;
        });
        break;
      case 'tracksChanged':
        final rawTracks = event['audioTracks'];
        final tracks = <_LiveAudioTrack>[];
        if (rawTracks is List) {
          for (final rawTrack in rawTracks) {
            if (rawTrack is Map) {
              tracks.add(
                _LiveAudioTrack.fromMap(rawTrack.cast<Object?, Object?>()),
              );
            }
          }
        }
        setState(() => _audioTracks = tracks);
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
            event['errorCode']?.toString() ??
            '';
        final detail = event['error']?.toString() ?? codeName;
        _handleTechnicalError(codeName, detail);
        break;
      case 'completed':
        // Media3 nativo ya hizo sus recuperaciones LIVE estilo Hot Player.
        // No repetimos otra cascada desde Dart.
        _finishWithError(
          'Canal no disponible',
          'STREAM_ENDED · La señal terminó inesperadamente.',
        );
        break;
      case 'liveRecovery':
        debugPrint(
          'TV FULL PRO LIVE recovery: ${event['reason']} '
          'attempt=${event['attempt']}',
        );
        break;
      case 'adaptiveProfile':
        debugPrint(
          'TV FULL PRO LIVE adaptive level=${event['level']} '
          'reason=${event['reason']} rebuffers=${event['rebufferCount']} '
          'bandwidth=${event['bandwidthEstimate']} bitrate=${event['videoBitrate']}',
        );
        break;
      case 'codecError':
        debugPrint('TV FULL PRO LIVE codec: ${event['error']}');
        break;
    }
  }

  void _handleTechnicalError(String code, String detail) {
    debugPrint('TV FULL PRO LIVE [$code] $detail');
    final combined = '$code $detail'.toLowerCase();
    final permanentHttp = combined.contains('401') ||
        combined.contains('403') ||
        combined.contains('404');
    final transient = !permanentHttp &&
        (combined.contains('network') ||
            combined.contains('timeout') ||
            combined.contains('connection') ||
            combined.contains('io_bad_http_status') ||
            combined.contains('response_code_5'));

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
    _retryTimer?.cancel();
    debugPrint('TV FULL PRO LIVE error: $technical');
    if (!mounted) return;
    _overlayTimer?.cancel();
    setState(() {
      _buffering = false;
      _friendlyError = friendly;
      _overlayVisible = false;
      _channelListVisible = false;
      _audioTracks = const <_LiveAudioTrack>[];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _retryFocus.canRequestFocus) _retryFocus.requestFocus();
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

  Future<void> _showAudioPicker() async {
    final tracks = _selectableAudioTracks;
    if (!mounted || tracks.length < 2) return;
    _overlayTimer?.cancel();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF101A26),
        title: const Row(
          children: [
            Icon(Icons.language_rounded, color: Color(0xFF58B9FF)),
            SizedBox(width: 10),
            Text('Idioma / pista de audio'),
          ],
        ),
        content: SizedBox(
          width: 430,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                autofocus: !tracks.any((track) => track.selected),
                leading: const Icon(Icons.auto_awesome_rounded),
                title: const Text('Automático'),
                subtitle: const Text('Usar la pista predeterminada del canal'),
                onTap: () async {
                  await _player.invokeMethod<void>('setAudioTrack', {
                    'auto': true,
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
              ),
              const Divider(height: 1),
              ...tracks.asMap().entries.map((entry) {
                final index = entry.key;
                final track = entry.value;
                return ListTile(
                  autofocus: track.selected,
                  leading: const Icon(Icons.audiotrack_rounded),
                  title: Text(track.displayName(index + 1)),
                  subtitle: track.mimeType.isEmpty
                      ? null
                      : Text(track.mimeType
                          .replaceFirst('audio/', '')
                          .toUpperCase()),
                  trailing: track.selected
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF58B9FF),
                        )
                      : null,
                  onTap: () async {
                    await _player.invokeMethod<void>('setAudioTrack', {
                      'groupIndex': track.groupIndex,
                      'trackIndex': track.trackIndex,
                      'auto': false,
                    });
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    if (mounted) {
      _rootFocus.requestFocus();
      _showOverlay();
    }
  }

  void _openChannelList() {
    _overlayTimer?.cancel();
    setState(() {
      _overlayVisible = true;
      _channelListVisible = true;
    });
    _scrollChannelListToCurrent();
  }

  void _closeChannelList() {
    if (!mounted) return;
    setState(() => _channelListVisible = false);
    _rootFocus.requestFocus();
    _showOverlay();
  }

  void _scrollChannelListToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_channelListVisible ||
          !_channelScrollController.hasClients) {
        return;
      }
      const rowExtent = 58.0;
      final max = _channelScrollController.position.maxScrollExtent;
      final target =
          (_index * rowExtent - rowExtent * 2).clamp(0.0, max).toDouble();
      _channelScrollController.jumpTo(target);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _channelListVisible &&
            _channelListFocus.canRequestFocus) {
          _channelListFocus.requestFocus();
        }
      });
    });
  }

  void _selectChannel(int index) {
    if (index < 0 || index >= widget.playlist.length) return;
    setState(() {
      _index = index;
      _channelListVisible = false;
      _overlayVisible = true;
    });
    _rootFocus.requestFocus();
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
    final key = event.logicalKey;
    final isBack =
        key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape;

    // La lista abierta tiene prioridad total, incluso si el canal anterior
    // dejó un error visible. Así el D-pad vuelve a navegar los canales normal.
    if (_channelListVisible) {
      if (isBack) {
        _closeChannelList();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_friendlyError != null) {
      if (isBack) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.arrowDown) {
        _openChannelList();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        unawaited(_prepareCurrent());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp) {
        _retryFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (isBack && _overlayVisible) {
      _overlayTimer?.cancel();
      setState(() => _overlayVisible = false);
      _rootFocus.requestFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp && _hasMultipleAudioTracks) {
      unawaited(_showAudioPicker());
      return KeyEventResult.handled;
    }
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
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      _previous();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown) {
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
    _channelScrollController.dispose();
    _channelListFocus.dispose();
    _retryFocus.dispose();
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
                    : Texture(
                        textureId: _textureId!,
                        filterQuality: FilterQuality.none,
                      ),
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
            height: 54,
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xE80A1017),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: CachedArtworkImage(
                      url: _channel.logoUrl,
                      fit: BoxFit.contain,
                      cacheWidth: 68,
                      cacheHeight: 68,
                      prefetchExtent: 0,
                      fallback: const Icon(Icons.live_tv_rounded, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_hasMultipleAudioTracks) ...[
                  SizedBox(
                    height: 34,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => unawaited(_showAudioPicker()),
                      icon: const Icon(Icons.language_rounded, size: 18),
                      label: const Text('Audio'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Container(width: 1, height: 24, color: Colors.white12),
                const SizedBox(width: 10),
                const Icon(Icons.circle, size: 8, color: Colors.redAccent),
                const SizedBox(width: 5),
                const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 34,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _openChannelList,
                    icon: const Icon(Icons.list_rounded, size: 18),
                    label: const Text('Catálogo'),
                  ),
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
              width: 350,
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
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _closeChannelList,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _channelScrollController,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
                      scrollCacheExtent: const ScrollCacheExtent.pixels(70),
                      itemCount: widget.playlist.length,
                      itemBuilder: (context, index) {
                        final item = widget.playlist[index];
                        final selected = index == _index;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: ListTile(
                            focusNode: selected ? _channelListFocus : null,
                            autofocus: selected,
                            selected: selected,
                            minTileHeight: 54,
                            selectedTileColor:
                                const Color(0xFF1677FF).withValues(alpha: .18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                            leading: SizedBox(
                              width: 36,
                              height: 36,
                              child: CachedArtworkImage(
                                url: item.logoUrl,
                                fit: BoxFit.contain,
                                cacheWidth: 72,
                                cacheHeight: 72,
                                prefetchExtent: 0,
                                fallback: const Icon(
                                  Icons.live_tv_rounded,
                                  size: 20,
                                ),
                              ),
                            ),
                            title: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
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
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Probá nuevamente o elegí otro canal.',
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 18),
              _LiveErrorButton(
                focusNode: _retryFocus,
                autofocus: true,
                filled: true,
                label: 'Reintentar',
                icon: Icons.refresh_rounded,
                onTap: () => unawaited(_prepareCurrent()),
              ),
              const SizedBox(height: 14),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: Colors.white54),
                  SizedBox(width: 5),
                  Text(
                    'Flecha abajo: lista de canales',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _LiveErrorButton extends StatefulWidget {
  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool autofocus;
  final bool filled;

  const _LiveErrorButton({
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.onTap,
    this.autofocus = false,
    this.filled = false,
  });

  @override
  State<_LiveErrorButton> createState() => _LiveErrorButtonState();
}

class _LiveErrorButtonState extends State<_LiveErrorButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF58B9FF);
    return AnimatedScale(
      scale: _focused ? 1.07 : 1,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        decoration: BoxDecoration(
          color: widget.filled
              ? const Color(0xFF1677FF).withValues(alpha: _focused ? .42 : .28)
              : const Color(0xFF101A26),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: _focused ? accent : Colors.white24,
            width: _focused ? 2 : 1,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: .28),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon,
                      size: 19, color: _focused ? accent : Colors.white70),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontWeight: _focused ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveAudioTrack {
  final int groupIndex;
  final int trackIndex;
  final String label;
  final String language;
  final String mimeType;
  final bool selected;
  final bool supported;

  const _LiveAudioTrack({
    required this.groupIndex,
    required this.trackIndex,
    required this.label,
    required this.language,
    required this.mimeType,
    required this.selected,
    required this.supported,
  });

  factory _LiveAudioTrack.fromMap(Map<Object?, Object?> map) {
    return _LiveAudioTrack(
      groupIndex: (map['groupIndex'] as num?)?.toInt() ?? -1,
      trackIndex: (map['trackIndex'] as num?)?.toInt() ?? -1,
      label: map['label']?.toString().trim() ?? '',
      language: map['language']?.toString().trim() ?? '',
      mimeType: map['mimeType']?.toString().trim() ?? '',
      selected: map['selected'] == true,
      supported: map['supported'] != false,
    );
  }

  String displayName(int fallbackIndex) {
    final languageName = _languageName(language);
    if (languageName != null && label.isNotEmpty) {
      if (!label.toLowerCase().contains(languageName.toLowerCase())) {
        return '$languageName · $label';
      }
    }
    if (languageName != null) return languageName;
    if (label.isNotEmpty) return label;
    return 'Audio $fallbackIndex';
  }

  String? _languageName(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value == 'und') return null;
    final normalized = value.split(RegExp(r'[-_]')).first;
    return switch (normalized) {
      'es' || 'spa' => 'Español',
      'en' || 'eng' => 'Inglés',
      'pt' || 'por' => 'Portugués',
      'fr' || 'fra' || 'fre' => 'Francés',
      'it' || 'ita' => 'Italiano',
      'de' || 'deu' || 'ger' => 'Alemán',
      'ja' || 'jpn' => 'Japonés',
      'ko' || 'kor' => 'Coreano',
      'zh' || 'zho' || 'chi' => 'Chino',
      'ru' || 'rus' => 'Ruso',
      'ar' || 'ara' => 'Árabe',
      _ => raw.trim().toUpperCase(),
    };
  }
}
