from pathlib import Path
import re

ROOT = Path('.')
LIVE_PLAYER = ROOT / 'lib/screens/android_media3_texture_player_screen.dart'
VOD_PLAYER = ROOT / 'lib/screens/android_media3_vod_player_screen.dart'
CHANNELS = ROOT / 'lib/screens/channel_list_screen.dart'
SERIES = ROOT / 'lib/screens/xtream_series_screen.dart'
GRADLE = ROOT / 'android/app/build.gradle.kts'
MANIFEST = ROOT / 'android/app/src/main/AndroidManifest.xml'
REMOTE = ROOT / 'lib/services/remote_provisioning_service.dart'
MAIN_KT = next((ROOT / 'android/app/src/main/kotlin').rglob('MainActivity.kt'))


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Marcador no encontrado V10: {label}')
    return text.replace(old, new, 1)


def write_native_bridge():
    original = MAIN_KT.read_text()
    package_line = next(
        (line for line in original.splitlines() if line.startswith('package ')),
        'package com.example.iptv_player',
    )
    native = r'''__PACKAGE__

import android.net.Uri
import android.view.Surface
import android.view.WindowManager
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import io.github.anilbeesetti.nextlib.media3ext.ffdecoder.NextRenderersFactory

@UnstableApi
class MainActivity : FlutterActivity(), Player.Listener, AnalyticsListener {
    companion object {
        private const val METHOD_CHANNEL = "tvfull/media3_texture"
        private const val EVENT_CHANNEL = "tvfull/media3_texture_events"
        private const val DEFAULT_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36"
    }

    private var player: ExoPlayer? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var eventSink: EventChannel.EventSink? = null
    private var currentUrl: String? = null
    private var isLive = false
    private var playbackGeneration = 0L
    private var endedRecoveries = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                handlePlayerCall(flutterEngine, call, result)
            }
    }

    private fun handlePlayerCall(
        flutterEngine: FlutterEngine,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            when (call.method) {
                "initialize" -> {
                    val minBuffer = call.argument<Int>("minBuffer") ?: 5000
                    val maxBuffer = call.argument<Int>("maxBuffer") ?: 15000
                    val playBuffer = call.argument<Int>("bufferForPlayback") ?: 2500
                    val rebuffer = call.argument<Int>("bufferForPlaybackAfterRebuffer") ?: 1000
                    result.success(
                        initializePlayer(
                            flutterEngine,
                            minBuffer,
                            maxBuffer,
                            playBuffer,
                            rebuffer,
                        )
                    )
                }

                "prepare" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("INVALID_URL", "URL vacía", null)
                        return
                    }
                    @Suppress("UNCHECKED_CAST")
                    val headers = (
                        call.argument<Map<String, String>>("headers") ?: emptyMap()
                    ).toMutableMap()
                    val userAgent = call.argument<String>("userAgent") ?: DEFAULT_UA
                    val position = call.argument<Number>("position")?.toLong() ?: 0L
                    isLive = call.argument<Boolean>("isLive") ?: true
                    prepare(url, headers, userAgent, position)
                    result.success(null)
                }

                "play" -> {
                    player?.play()
                    result.success(null)
                }

                "pause" -> {
                    player?.pause()
                    result.success(null)
                }

                "seekTo" -> {
                    val raw = call.argument<Number>("position")?.toLong() ?: 0L
                    val duration = player?.duration ?: 0L
                    val target = if (duration > 0 && duration != C.TIME_UNSET) {
                        raw.coerceIn(0L, duration)
                    } else {
                        raw.coerceAtLeast(0L)
                    }
                    player?.seekTo(target)
                    result.success(null)
                }

                "getCurrentPosition" ->
                    result.success((player?.currentPosition ?: 0L).coerceAtLeast(0L))

                "getBufferedPosition" ->
                    result.success((player?.bufferedPosition ?: 0L).coerceAtLeast(0L))

                "getDuration" -> {
                    val value = player?.duration ?: 0L
                    result.success(if (value < 0L || value == C.TIME_UNSET) 0L else value)
                }

                "setAudioTrack" -> {
                    result.success(
                        selectTrack(
                            C.TRACK_TYPE_AUDIO,
                            call.argument<Number>("groupIndex")?.toInt(),
                            call.argument<Number>("trackIndex")?.toInt(),
                            call.argument<Boolean>("auto") ?: false,
                            false,
                        )
                    )
                }

                "setSubtitleTrack" -> {
                    result.success(
                        selectTrack(
                            C.TRACK_TYPE_TEXT,
                            call.argument<Number>("groupIndex")?.toInt(),
                            call.argument<Number>("trackIndex")?.toInt(),
                            call.argument<Boolean>("auto") ?: false,
                            call.argument<Boolean>("off") ?: false,
                        )
                    )
                }

                "dispose" -> {
                    disposePlayer()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            val message = t.message ?: t.javaClass.simpleName
            eventSink?.success(
                mapOf(
                    "eventType" to "videoError",
                    "error" to "PLAYER_EXCEPTION · $message",
                )
            )
            result.error("PLAYER_EXCEPTION", message, null)
        }
    }

    private fun initializePlayer(
        flutterEngine: FlutterEngine,
        minBuffer: Int,
        maxBuffer: Int,
        playBuffer: Int,
        rebuffer: Int,
    ): Long {
        disposePlayer()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(minBuffer, maxBuffer, playBuffer, rebuffer)
            .build()

        val renderersFactory = NextRenderersFactory(this)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)

        player = ExoPlayer.Builder(this)
            .setLoadControl(loadControl)
            .setRenderersFactory(renderersFactory)
            .build()
            .also { exo ->
                exo.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(C.USAGE_MEDIA)
                        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                        .build(),
                    true,
                )
                exo.addListener(this)
                exo.addAnalyticsListener(this)
            }

        textureEntry = flutterEngine.renderer.createSurfaceTexture()
        surface = Surface(textureEntry!!.surfaceTexture())
        player!!.setVideoSurface(surface)
        return textureEntry!!.id()
    }

    private fun prepare(
        url: String,
        headers: MutableMap<String, String>,
        userAgent: String,
        positionMs: Long,
    ) {
        val exo = player ?: throw IllegalStateException("Player no inicializado")
        currentUrl = url
        endedRecoveries = 0
        playbackGeneration++

        exo.stop()
        exo.clearMediaItems()

        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
        if (headers.isNotEmpty()) {
            httpFactory.setDefaultRequestProperties(headers)
        }

        val item = MediaItem.Builder().setUri(Uri.parse(url)).build()
        val source = DefaultMediaSourceFactory(httpFactory).createMediaSource(item)
        exo.setMediaSource(source)
        if (positionMs > 0L) exo.seekTo(positionMs)
        exo.prepare()
        exo.playWhenReady = true
    }

    private fun selectTrack(
        trackType: Int,
        groupIndex: Int?,
        trackIndex: Int?,
        auto: Boolean,
        off: Boolean,
    ): Boolean {
        val exo = player ?: return false
        val builder = exo.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(trackType)

        if (off) {
            builder.setTrackTypeDisabled(trackType, true)
            exo.trackSelectionParameters = builder.build()
            return true
        }

        builder.setTrackTypeDisabled(trackType, false)
        if (!auto) {
            if (groupIndex == null || trackIndex == null) return false
            val groups = exo.currentTracks.groups
            if (groupIndex !in groups.indices) return false
            val group = groups[groupIndex]
            if (group.type != trackType || trackIndex !in 0 until group.length) return false
            builder.addOverride(
                TrackSelectionOverride(group.mediaTrackGroup, listOf(trackIndex))
            )
        }
        exo.trackSelectionParameters = builder.build()
        return true
    }

    private fun serializeTracks(trackType: Int): List<Map<String, Any?>> {
        val exo = player ?: return emptyList()
        val output = mutableListOf<Map<String, Any?>>()
        exo.currentTracks.groups.forEachIndexed { groupIndex, group ->
            if (group.type != trackType) return@forEachIndexed
            for (trackIndex in 0 until group.length) {
                val format = group.getTrackFormat(trackIndex)
                output.add(
                    mapOf(
                        "groupIndex" to groupIndex,
                        "trackIndex" to trackIndex,
                        "label" to (format.label ?: ""),
                        "language" to (format.language ?: ""),
                        "mimeType" to (format.sampleMimeType ?: ""),
                        "selected" to group.isTrackSelected(trackIndex),
                        "supported" to group.isTrackSupported(trackIndex),
                    )
                )
            }
        }
        return output
    }

    private fun sendTracks() {
        eventSink?.success(
            mapOf(
                "eventType" to "tracksChanged",
                "audioTracks" to serializeTracks(C.TRACK_TYPE_AUDIO),
                "textTracks" to serializeTracks(C.TRACK_TYPE_TEXT),
            )
        )
    }

    override fun onTracksChanged(tracks: Tracks) {
        sendTracks()
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        when (playbackState) {
            Player.STATE_BUFFERING ->
                eventSink?.success(mapOf("eventType" to "bufferingStart"))

            Player.STATE_READY -> {
                endedRecoveries = 0
                eventSink?.success(mapOf("eventType" to "prepared"))
                eventSink?.success(mapOf("eventType" to "bufferingEnd"))
                sendTracks()
            }

            Player.STATE_ENDED -> {
                val exo = player
                if (
                    isLive &&
                    currentUrl != null &&
                    exo != null &&
                    endedRecoveries < 5
                ) {
                    endedRecoveries++
                    exo.seekToDefaultPosition()
                    exo.prepare()
                    exo.play()
                } else {
                    eventSink?.success(mapOf("eventType" to "completed"))
                }
            }
        }
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        if (videoSize.width <= 0 || videoSize.height <= 0) return
        // LIVE conserva exactamente la estrategia estable de V9. En VOD evitamos
        // forzar el tamaño del SurfaceTexture mientras el decoder está arrancando.
        if (isLive) {
            textureEntry?.surfaceTexture()?.setDefaultBufferSize(
                videoSize.width,
                videoSize.height,
            )
        }
        eventSink?.success(
            mapOf(
                "eventType" to "videoSize",
                "width" to videoSize.width,
                "height" to videoSize.height,
                "pixelWidthHeightRatio" to videoSize.pixelWidthHeightRatio,
            )
        )
    }

    override fun onPlayerError(error: PlaybackException) {
        eventSink?.success(
            mapOf(
                "eventType" to "videoError",
                "error" to (error.errorCodeName + " · " + (error.message ?: "error de reproducción")),
            )
        )
    }

    override fun onVideoCodecError(
        eventTime: AnalyticsListener.EventTime,
        videoCodecError: Exception,
    ) {
        eventSink?.success(
            mapOf(
                "eventType" to "codecError",
                "kind" to "video",
                "error" to (videoCodecError.message ?: videoCodecError.javaClass.simpleName),
            )
        )
    }

    override fun onAudioCodecError(
        eventTime: AnalyticsListener.EventTime,
        audioCodecError: Exception,
    ) {
        eventSink?.success(
            mapOf(
                "eventType" to "codecError",
                "kind" to "audio",
                "error" to (audioCodecError.message ?: audioCodecError.javaClass.simpleName),
            )
        )
    }

    private fun disposePlayer() {
        playbackGeneration++
        player?.removeListener(this)
        player?.removeAnalyticsListener(this)
        player?.stop()
        player?.clearMediaItems()
        player?.release()
        player = null
        surface?.release()
        surface = null
        textureEntry?.release()
        textureEntry = null
        currentUrl = null
        endedRecoveries = 0
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onDestroy() {
        disposePlayer()
        super.onDestroy()
    }
}
'''.replace('__PACKAGE__', package_line)
    MAIN_KT.write_text(native)


def write_live_player():
    LIVE_PLAYER.write_text(r'''import 'dart:async';

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
      final id = await _player.invokeMethod<int>('initialize', <String, Object?>{
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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
''')


def write_vod_player():
    VOD_PLAYER.write_text(r'''import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

const String _vodUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
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

  Map<String, String> get _headers => _channel.resolvedHttpHeaders(_vodUserAgent);

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
      final id = await _player.invokeMethod<int>('initialize', <String, Object?>{
        'minBuffer': 5000,
        'maxBuffer': 18000,
        'bufferForPlayback': 2500,
        'bufferForPlaybackAfterRebuffer': 1200,
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
          _codecWarning = '${event['kind'] ?? 'codec'}: ${event['error'] ?? 'error'}';
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
    await _player.invokeMethod<void>('seekTo', <String, Object?>{'position': target});
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
    await _player.invokeMethod<void>('setAudioTrack', track == null
        ? <String, Object?>{'auto': true}
        : <String, Object?>{
            'groupIndex': track.groupIndex,
            'trackIndex': track.trackIndex,
          });
    _showOverlay();
  }

  Future<void> _selectSubtitle(_TrackOption? track, {bool off = false}) async {
    await _player.invokeMethod<void>('setSubtitleTrack', off
        ? <String, Object?>{'off': true}
        : track == null
            ? <String, Object?>{'auto': true}
            : <String, Object?>{
                'groupIndex': track.groupIndex,
                'trackIndex': track.trackIndex,
              });
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
              const Text('AUDIO', style: TextStyle(fontWeight: FontWeight.w900)),
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
                  trailing: track.selected ? const Icon(Icons.check_rounded) : null,
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    unawaited(_selectAudio(track));
                  },
                ),
              ),
              const Divider(),
              const Text('SUBTÍTULOS', style: TextStyle(fontWeight: FontWeight.w900)),
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
                  trailing: track.selected ? const Icon(Icons.check_rounded) : null,
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
    if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.arrowDown) {
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
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: () => unawaited(_prepareCurrent(positionMs: _positionMs)),
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
                                style: const TextStyle(fontWeight: FontWeight.w800),
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
                            Text(_durationMs > 0 ? _clock(_durationMs) : '--:--'),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Audio y subtítulos',
                              onPressed: _ready ? () => unawaited(_showTrackMenu()) : null,
                              icon: const Icon(Icons.tune_rounded),
                            ),
                            TextButton.icon(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.grid_view_rounded, size: 20),
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
''')


def patch_live_catalog():
    text = CHANNELS.read_text()
    old_call = '''            return _TvCatalogLayout(
              mode: mode,
              channels: channels,
              groups: visibleGroups,
              selectedGroup: _selectedGroup,
              onGroupSelected: (group) => unawaited(_selectGroup(group)),
              onPlay: (channel) =>
                  _openChannel(context, channels, channel, provider),
            );'''
    new_call = '''            return _TvCatalogLayout(
              mode: mode,
              channels: channels,
              groups: visibleGroups,
              selectedGroup: _selectedGroup,
              query: _query,
              onGroupSelected: (group) => unawaited(_selectGroup(group)),
              onQueryChanged: (value) => setState(() => _query = value),
              onPlay: (channel) =>
                  _openChannel(context, channels, channel, provider),
            );'''
    text = replace_once(text, old_call, new_call, 'llamada catalogo TV compacto')

    pattern = re.compile(
        r'class _TvCatalogLayout extends StatelessWidget \{.*?\nclass _DesktopCatalogLayout extends StatelessWidget \{',
        re.S,
    )
    replacement = r'''class _TvCatalogLayout extends StatelessWidget {
  final _CatalogMode mode;
  final List<Channel> channels;
  final List<String> groups;
  final String? selectedGroup;
  final String query;
  final ValueChanged<String?> onGroupSelected;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Channel> onPlay;

  const _TvCatalogLayout({
    required this.mode,
    required this.channels,
    required this.groups,
    required this.selectedGroup,
    required this.query,
    required this.onGroupSelected,
    required this.onQueryChanged,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 220,
          decoration: const BoxDecoration(
            color: Color(0xFF08111D),
            border: Border(right: BorderSide(color: Colors.white12)),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: groups.length + 1,
            itemBuilder: (context, index) {
              final group = index == 0 ? null : groups[index - 1];
              final selected = group == selectedGroup;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                child: Material(
                  color: selected
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: .22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    autofocus: index == 0,
                    onTap: () => onGroupSelected(group),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(
                        group ?? 'Todos',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 24, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${selectedGroup ?? mode.title} · ${channels.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      height: 42,
                      child: TextFormField(
                        initialValue: query,
                        decoration: InputDecoration(
                          hintText: 'Buscar canal…',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: onQueryChanged,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 2, 24, 20),
                  itemCount: channels.length,
                  itemBuilder: (context, index) {
                    final channel = channels[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Material(
                        color: const Color(0xFF0D1826),
                        borderRadius: BorderRadius.circular(11),
                        child: InkWell(
                          onTap: () => onPlay(channel),
                          borderRadius: BorderRadius.circular(11),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                _ChannelLogo(channel: channel),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    channel.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const Icon(Icons.play_arrow_rounded, size: 26),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopCatalogLayout extends StatelessWidget {'''
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise SystemExit('No se pudo reemplazar catalogo TV V10')
    CHANNELS.write_text(text)


def patch_series_detail():
    text = SERIES.read_text()
    pattern = re.compile(
        r'''  Widget _buildWide\(
    XtreamSeriesDetails details,
    int season,
    List<XtreamSeriesEpisode> episodes,
  \) \{.*?\n  Widget _buildCompact\(''',
        re.S,
    )
    replacement = r'''  Widget _buildWide(
    XtreamSeriesDetails details,
    int season,
    List<XtreamSeriesEpisode> episodes,
  ) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 210,
            child: _SeasonList(
              details: details,
              selectedSeason: season,
              onSelected: (value) => setState(() => _selectedSeason = value),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _EpisodePanel(
              series: details.series,
              season: season,
              episodes: episodes,
              onPlay: (episode) => _play(details, season, episode),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact('''
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise SystemExit('No se pudo simplificar detalle de Series V10')
    SERIES.write_text(text)


def patch_manifest_and_version():
    manifest = MANIFEST.read_text()
    if 'android.permission.WAKE_LOCK' not in manifest:
        manifest = manifest.replace(
            '<uses-permission android:name="android.permission.INTERNET" />',
            '<uses-permission android:name="android.permission.INTERNET" />\n'
            '    <uses-permission android:name="android.permission.WAKE_LOCK" />',
            1,
        )
    MANIFEST.write_text(manifest)

    gradle = GRADLE.read_text().replace(
        'applicationId = "com.tvfull.pro.tv.v9clean"',
        'applicationId = "com.tvfull.pro.tv.v10safe"',
    )
    GRADLE.write_text(gradle)

    if REMOTE.exists():
        remote = REMOTE.read_text()
        remote = re.sub(
            r'1\.0\.0\+1-android-tv-[A-Za-z0-9._-]+',
            '1.0.0+1-android-tv-v10-vod-safe',
            remote,
        )
        REMOTE.write_text(remote)


def validate():
    checks = {
        MAIN_KT: [
            'FLAG_KEEP_SCREEN_ON',
            'onVideoCodecError',
            '"setAudioTrack"',
            '"setSubtitleTrack"',
            'tracksChanged',
        ],
        LIVE_PLAYER: ['● LIVE', "label: const Text('Catálogo')", 'Duration(seconds: 4)'],
        VOD_PLAYER: ['tracksChanged', "invokeMethod<void>('setAudioTrack'", 'Audio y subtítulos'],
        CHANNELS: ["hintText: 'Buscar canal…'", 'width: 220'],
        SERIES: ['width: 210', 'Expanded(\n            child: _EpisodePanel('],
        MANIFEST: ['android.permission.WAKE_LOCK'],
        GRADLE: ['com.tvfull.pro.tv.v10safe'],
    }
    for path, markers in checks.items():
        value = path.read_text()
        for marker in markers:
            if marker not in value:
                raise SystemExit(f'Validacion V10 fallo {path}: {marker}')


write_native_bridge()
write_live_player()
write_vod_player()
patch_live_catalog()
patch_series_detail()
patch_manifest_and_version()
validate()
print('V10 aplicada: VOD protegido, tracks, wakelock, HUD limpio y Series compactas.')
