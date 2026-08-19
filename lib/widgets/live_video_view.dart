import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'cached_artwork_image.dart';

/// Reproductor visual premium de TV FULL.
///
/// Esta capa sólo maneja presentación y controles del usuario. No modifica
/// cache, red, reconexiones ni la estrategia del motor de reproducción.
class LiveVideoView extends StatefulWidget {
  final Player player;
  final VideoController controller;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool canPrevious;
  final bool canNext;
  final bool isLiveContent;

  final String title;
  final String? subtitle;
  final String? logoUrl;
  final int channelNumber;
  final String resolution;
  final String? performanceLabel;
  final VoidCallback onBack;
  final VoidCallback onShowChannelList;
  final VoidCallback onShowStreamInfo;
  final VoidCallback? onShowPerformance;

  const LiveVideoView({
    super.key,
    required this.player,
    required this.controller,
    required this.onPrevious,
    required this.onNext,
    required this.canPrevious,
    required this.canNext,
    required this.isLiveContent,
    required this.title,
    required this.channelNumber,
    required this.resolution,
    required this.onBack,
    required this.onShowChannelList,
    required this.onShowStreamInfo,
    this.subtitle,
    this.logoUrl,
    this.performanceLabel,
    this.onShowPerformance,
  });

  @override
  State<LiveVideoView> createState() => _LiveVideoViewState();
}

class _LiveVideoViewState extends State<LiveVideoView> {
  static const _overlayTimeout = Duration(seconds: 4);

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<Track>? _trackSub;
  Timer? _statusTimer;
  Timer? _overlayTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _hasStarted = false;
  double _volume = 100;
  List<AudioTrack> _audioTracks = const [];
  List<SubtitleTrack> _subtitleTracks = const [];
  late AudioTrack _selectedAudioTrack;
  late SubtitleTrack _selectedSubtitleTrack;
  bool _overlayVisible = true;
  DateTime _lastProgressAt = DateTime.now();
  BoxFit _videoFit = BoxFit.contain;
  int _fitIndex = 0;

  @override
  void initState() {
    super.initState();

    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _playing = widget.player.state.playing;
    _buffering = widget.player.state.buffering;
    _volume = widget.player.state.volume;
    _audioTracks = widget.player.state.tracks.audio;
    _subtitleTracks = widget.player.state.tracks.subtitle;
    _selectedAudioTrack = widget.player.state.track.audio;
    _selectedSubtitleTrack = widget.player.state.track.subtitle;

    _positionSub = widget.player.stream.position.listen((value) {
      if (!mounted) return;
      if (value != _position) {
        _position = value;
        _lastProgressAt = DateTime.now();
      }
      setState(() {});
    });

    _durationSub = widget.player.stream.duration.listen((value) {
      if (!mounted || value == _duration) return;
      setState(() => _duration = value);
    });

    _playingSub = widget.player.stream.playing.listen((value) {
      if (!mounted) return;
      setState(() {
        _playing = value;
        if (value) {
          _hasStarted = true;
          _lastProgressAt = DateTime.now();
        }
      });
      _scheduleOverlayHide();
    });

    _bufferingSub = widget.player.stream.buffering.listen((value) {
      if (!mounted) return;
      setState(() {
        _buffering = value;
        if (!value && _playing) _lastProgressAt = DateTime.now();
      });
      if (value) {
        _showOverlay(scheduleHide: false);
      } else {
        _scheduleOverlayHide();
      }
    });

    _volumeSub = widget.player.stream.volume.listen((value) {
      if (!mounted) return;
      setState(() => _volume = value.clamp(0, 100).toDouble());
    });

    // Películas y series pueden traer varias pistas de audio y subtítulos.
    // Escuchamos la lista real que detecta mpv/FFmpeg para no inventar idiomas.
    _tracksSub = widget.player.stream.tracks.listen((value) {
      if (!mounted || widget.isLiveContent) return;
      setState(() {
        _audioTracks = value.audio;
        _subtitleTracks = value.subtitle;
      });
    });

    _trackSub = widget.player.stream.track.listen((value) {
      if (!mounted || widget.isLiveContent) return;
      setState(() {
        _selectedAudioTrack = value.audio;
        _selectedSubtitleTrack = value.subtitle;
      });
    });

    _statusTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && widget.isLiveContent) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleOverlayHide();
    });
  }

  bool get _isActuallyLive {
    if (!_hasStarted || !_playing || _buffering) return false;
    return DateTime.now().difference(_lastProgressAt) <
        const Duration(milliseconds: 2500);
  }

  String get _statusLabel {
    if (!_hasStarted) return 'CARGANDO';
    if (_buffering) return 'BUFFER';
    if (!_playing) return 'PAUSA';
    return _isActuallyLive ? 'EN VIVO' : 'RECUPERANDO';
  }

  String get _fitLabel => switch (_fitIndex) {
        1 => 'Zoom',
        2 => 'Estirar',
        _ => 'Original',
      };

  void _showOverlay({bool scheduleHide = true}) {
    _overlayTimer?.cancel();
    if (mounted && !_overlayVisible) {
      setState(() => _overlayVisible = true);
    }
    if (scheduleHide) _scheduleOverlayHide();
  }

  void _scheduleOverlayHide() {
    _overlayTimer?.cancel();
    if (!_playing || _buffering) return;
    _overlayTimer = Timer(_overlayTimeout, () {
      if (!mounted || !_playing || _buffering) return;
      setState(() => _overlayVisible = false);
    });
  }

  void _toggleFit(VideoState videoState) {
    _showOverlay();
    setState(() {
      _fitIndex = (_fitIndex + 1) % 3;
      _videoFit = switch (_fitIndex) {
        1 => BoxFit.cover,
        2 => BoxFit.fill,
        _ => BoxFit.contain,
      };
    });
    videoState.update(fit: _videoFit);
  }

  Future<void> _handleBack(VideoState videoState) async {
    _showOverlay();
    if (videoState.isFullscreen()) {
      await videoState.exitFullscreen();
      return;
    }
    widget.onBack();
  }

  Future<void> _handleChannelList(VideoState videoState) async {
    _showOverlay();
    if (videoState.isFullscreen()) {
      await videoState.exitFullscreen();
    }
    widget.onShowChannelList();
  }

  void _togglePlayPause() {
    _showOverlay();
    unawaited(widget.player.playOrPause());
  }

  void _setVolume(double value) {
    _showOverlay();
    setState(() => _volume = value);
    unawaited(widget.player.setVolume(value));
  }

  void _seekTo(double milliseconds) {
    _showOverlay();
    if (widget.isLiveContent || _duration <= Duration.zero) return;
    final target = Duration(milliseconds: milliseconds.round());
    unawaited(widget.player.seek(target));
  }

  List<AudioTrack> get _selectableAudioTracks => _audioTracks
      .where((track) => track.id != 'auto' && track.id != 'no')
      .toList(growable: false);

  List<SubtitleTrack> get _selectableSubtitleTracks => _subtitleTracks
      .where((track) => track.id != 'auto' && track.id != 'no')
      .toList(growable: false);

  String? _languageName(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty || value == 'und') return null;
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
      _ => raw!.trim().toUpperCase(),
    };
  }

  String _trackDescription(
    String? title,
    String? language,
    String fallback,
  ) {
    final lang = _languageName(language);
    final cleanTitle = title?.trim();
    if (lang != null && cleanTitle != null && cleanTitle.isNotEmpty) {
      final titleLower = cleanTitle.toLowerCase();
      final langLower = lang.toLowerCase();
      if (!titleLower.contains(langLower)) return '$lang · $cleanTitle';
    }
    if (lang != null) return lang;
    if (cleanTitle != null && cleanTitle.isNotEmpty) return cleanTitle;
    return fallback;
  }

  String get _audioButtonLabel {
    final track = _selectedAudioTrack;
    if (track.id == 'auto') return 'Audio: Auto';
    if (track.id == 'no') return 'Audio: Off';
    final label = _languageName(track.language) ??
        (track.title?.trim().isNotEmpty == true ? track.title!.trim() : 'Pista');
    return 'Audio: $label';
  }

  String get _subtitleButtonLabel {
    final track = _selectedSubtitleTrack;
    if (track.id == 'no') return 'Subtítulos: Off';
    if (track.id == 'auto') return 'Subtítulos: Auto';
    final label = _languageName(track.language) ??
        (track.title?.trim().isNotEmpty == true ? track.title!.trim() : 'Pista');
    return 'Subs: $label';
  }

  Future<void> _showAudioTrackPicker() async {
    if (widget.isLiveContent) return;
    _showOverlay(scheduleHide: false);
    final tracks = _selectableAudioTracks;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF101A26),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(Icons.language_rounded, color: Color(0xFF58A6FF)),
                title: Text(
                  'Idioma / pista de audio',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text('Disponible sólo cuando el contenido incluye varias pistas.'),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.auto_awesome_rounded),
                      title: const Text('Automático'),
                      subtitle: const Text('Dejar que el reproductor elija la pista predeterminada'),
                      trailing: _selectedAudioTrack.id == 'auto'
                          ? const Icon(Icons.check_circle_rounded, color: Color(0xFF58A6FF))
                          : null,
                      onTap: () async {
                        await widget.player.setAudioTrack(AudioTrack.auto());
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                    if (tracks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(22, 12, 22, 22),
                        child: Text(
                          'Este contenido no informa pistas de audio adicionales.',
                          style: TextStyle(color: Colors.white60),
                        ),
                      )
                    else
                      ...tracks.asMap().entries.map((entry) {
                        final index = entry.key;
                        final track = entry.value;
                        final selected = _selectedAudioTrack.id == track.id;
                        final details = <String>[
                          if (track.codec?.trim().isNotEmpty == true) track.codec!.toUpperCase(),
                          if (track.channels?.trim().isNotEmpty == true) track.channels!,
                          if (track.isDefault == true) 'Predeterminada',
                        ];
                        return ListTile(
                          leading: const Icon(Icons.audiotrack_rounded),
                          title: Text(_trackDescription(
                            track.title,
                            track.language,
                            'Pista ${index + 1}',
                          )),
                          subtitle: details.isEmpty ? null : Text(details.join(' · ')),
                          trailing: selected
                              ? const Icon(Icons.check_circle_rounded, color: Color(0xFF58A6FF))
                              : null,
                          onTap: () async {
                            await widget.player.setAudioTrack(track);
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                          },
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) _scheduleOverlayHide();
  }

  Future<void> _showSubtitleTrackPicker() async {
    if (widget.isLiveContent) return;
    _showOverlay(scheduleHide: false);
    final tracks = _selectableSubtitleTracks;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF101A26),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(Icons.subtitles_rounded, color: Color(0xFF58A6FF)),
                title: Text(
                  'Subtítulos',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text('Elegí una pista incluida por el proveedor o desactivalos.'),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.subtitles_off_rounded),
                      title: const Text('Desactivados'),
                      trailing: _selectedSubtitleTrack.id == 'no'
                          ? const Icon(Icons.check_circle_rounded, color: Color(0xFF58A6FF))
                          : null,
                      onTap: () async {
                        await widget.player.setSubtitleTrack(SubtitleTrack.no());
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.auto_awesome_rounded),
                      title: const Text('Automático'),
                      subtitle: const Text('Usar la pista de subtítulos predeterminada'),
                      trailing: _selectedSubtitleTrack.id == 'auto'
                          ? const Icon(Icons.check_circle_rounded, color: Color(0xFF58A6FF))
                          : null,
                      onTap: () async {
                        await widget.player.setSubtitleTrack(SubtitleTrack.auto());
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                    if (tracks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(22, 12, 22, 22),
                        child: Text(
                          'Este contenido no informa pistas de subtítulos adicionales.',
                          style: TextStyle(color: Colors.white60),
                        ),
                      )
                    else
                      ...tracks.asMap().entries.map((entry) {
                        final index = entry.key;
                        final track = entry.value;
                        final selected = _selectedSubtitleTrack.id == track.id;
                        final details = <String>[
                          if (track.codec?.trim().isNotEmpty == true) track.codec!.toUpperCase(),
                          if (track.isDefault == true) 'Predeterminada',
                        ];
                        return ListTile(
                          leading: const Icon(Icons.closed_caption_rounded),
                          title: Text(_trackDescription(
                            track.title,
                            track.language,
                            'Subtítulo ${index + 1}',
                          )),
                          subtitle: details.isEmpty ? null : Text(details.join(' · ')),
                          trailing: selected
                              ? const Icon(Icons.check_circle_rounded, color: Color(0xFF58A6FF))
                              : null,
                          onTap: () async {
                            await widget.player.setSubtitleTrack(track);
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                          },
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) _scheduleOverlayHide();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _volumeSub?.cancel();
    _tracksSub?.cancel();
    _trackSub?.cancel();
    _statusTimer?.cancel();
    _overlayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => _showOverlay(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _showOverlay(),
        child: Video(
          controller: widget.controller,
          fit: _videoFit,
          controls: (videoState) => _buildControls(videoState),
        ),
      ),
    );
  }

  Widget _buildControls(VideoState videoState) {
    return IgnorePointer(
      ignoring: !_overlayVisible,
      child: AnimatedOpacity(
        opacity: _overlayVisible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _buildTopBar(videoState),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1320),
                    child: _buildBottomArea(videoState),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(VideoState videoState) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE5000914), Color(0x00000914)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            _roundButton(
              icon: Icons.arrow_back_ios_new_rounded,
              tooltip: 'Volver',
              onTap: () => unawaited(_handleBack(videoState)),
            ),
            const SizedBox(width: 12),
            const Text(
              'TV FULL',
              style: TextStyle(
                color: Color(0xFF58A6FF),
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: 0.8,
              ),
            ),
            if (widget.isLiveContent) ...[
              const SizedBox(width: 12),
              _liveBadge(),
            ],
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            if (widget.performanceLabel != null &&
                widget.onShowPerformance != null) ...[
              _smallInfoChip(
                icon: Icons.speed_rounded,
                text: widget.performanceLabel!,
                onTap: widget.onShowPerformance!,
              ),
              const SizedBox(width: 8),
            ],
            _roundButton(
              icon: Icons.info_outline_rounded,
              tooltip: 'Información del stream',
              onTap: widget.onShowStreamInfo,
            ),
            const SizedBox(width: 8),
            _roundButton(
              icon: Icons.view_list_rounded,
              tooltip: 'Lista de canales',
              onTap: () => unawaited(_handleChannelList(videoState)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomArea(VideoState videoState) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 20,
                compact ? 12 : 16,
                compact ? 14 : 20,
                12,
              ),
              decoration: BoxDecoration(
                color: const Color(0xD9162230),
                borderRadius: BorderRadius.circular(compact ? 20 : 26),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _channelLogo(compact),
                      SizedBox(width: compact ? 12 : 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 20 : 28,
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                              ),
                            ),
                            if ((widget.subtitle ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                widget.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: compact ? 12 : 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(width: compact ? 12 : 18),
                      SizedBox(
                        width: compact ? 92 : 132,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'N° ${widget.channelNumber}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 15 : 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (widget.resolution.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                widget.resolution,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: compact ? 12 : 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  widget.isLiveContent
                      ? _buildLiveProgress()
                      : _buildVodProgress(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildControlRow(videoState, compact),
          ],
        );
      },
    );
  }

  Widget _buildLiveProgress() {
    final color = _isActuallyLive
        ? const Color(0xFFFF2D2D)
        : _buffering
            ? const Color(0xFFFFC857)
            : Colors.white38;
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: _isActuallyLive
                ? const [
                    BoxShadow(
                      color: Color(0x99FF2D2D),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 9),
        Text(
          _statusLabel,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: _isActuallyLive ? 1 : null,
              minHeight: 4,
              color: color,
              backgroundColor: Colors.white24,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVodProgress() {
    final totalMs = _duration.inMilliseconds;
    final currentMs = _position.inMilliseconds.clamp(0, totalMs > 0 ? totalMs : 0);
    final max = totalMs > 0 ? totalMs.toDouble() : 1.0;
    final value = currentMs.toDouble().clamp(0.0, max).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: const Color(0xFFFF3B4D),
            inactiveTrackColor: Colors.white30,
            thumbColor: Colors.white,
            overlayColor: Colors.white12,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            min: 0,
            max: max,
            value: value,
            onChanged: totalMs > 0 ? _seekTo : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Spacer(),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControlRow(VideoState videoState, bool compact) {
    return Row(
      children: [
        _iconPill(
          icon: Icons.skip_previous_rounded,
          tooltip: 'Canal anterior',
          enabled: widget.canPrevious,
          onTap: widget.onPrevious,
        ),
        const SizedBox(width: 8),
        _iconPill(
          icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: _playing ? 'Pausar' : 'Reproducir',
          onTap: _togglePlayPause,
        ),
        const SizedBox(width: 8),
        _iconPill(
          icon: Icons.skip_next_rounded,
          tooltip: 'Canal siguiente',
          enabled: widget.canNext,
          onTap: widget.onNext,
        ),
        const SizedBox(width: 10),
        _textPill(
          icon: Icons.aspect_ratio_rounded,
          label: _fitLabel,
          onTap: () => _toggleFit(videoState),
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          _textPill(
            icon: Icons.view_list_rounded,
            label: widget.isLiveContent ? 'Canales' : 'Contenido',
            onTap: () => unawaited(_handleChannelList(videoState)),
          ),
        ],
        if (!widget.isLiveContent) ...[
          const SizedBox(width: 10),
          if (compact)
            _iconPill(
              icon: Icons.language_rounded,
              tooltip: _audioButtonLabel,
              onTap: () => unawaited(_showAudioTrackPicker()),
            )
          else
            _textPill(
              icon: Icons.language_rounded,
              label: _audioButtonLabel,
              onTap: () => unawaited(_showAudioTrackPicker()),
            ),
          const SizedBox(width: 8),
          if (compact)
            _iconPill(
              icon: Icons.subtitles_rounded,
              tooltip: _subtitleButtonLabel,
              onTap: () => unawaited(_showSubtitleTrackPicker()),
            )
          else
            _textPill(
              icon: Icons.subtitles_rounded,
              label: _subtitleButtonLabel,
              onTap: () => unawaited(_showSubtitleTrackPicker()),
            ),
        ],
        const Spacer(),
        _volumePill(compact),
        const SizedBox(width: 10),
        _iconPill(
          icon: videoState.isFullscreen()
              ? Icons.fullscreen_exit_rounded
              : Icons.fullscreen_rounded,
          tooltip: videoState.isFullscreen()
              ? 'Salir de pantalla completa'
              : 'Pantalla completa',
          onTap: () {
            _showOverlay();
            unawaited(videoState.toggleFullscreen());
          },
        ),
      ],
    );
  }

  Widget _channelLogo(bool compact) {
    final width = compact ? 72.0 : 106.0;
    final height = compact ? 50.0 : 66.0;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1B30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedArtworkImage(
        url: widget.logoUrl,
        allowNetwork: false,
        fit: BoxFit.contain,
        cacheWidth: compact ? 144 : 212,
        fallback: const Center(
          child: Icon(Icons.live_tv_rounded, color: Colors.white38, size: 32),
        ),
      ),
    );
  }

  Widget _liveBadge() {
    final active = _isActuallyLive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFB31322)
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: active ? const Color(0xFFFF4250) : Colors.white38,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _statusLabel,
            style: TextStyle(
              color: active ? Colors.white : Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xB0152434),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            _showOverlay();
            onTap();
          },
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: Colors.white, size: 21),
          ),
        ),
      ),
    );
  }

  Widget _smallInfoChip({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xB0152434),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          _showOverlay();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconPill({
    required IconData icon,
    required String tooltip,
    bool enabled = true,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xD9202C39),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: enabled
              ? () {
                  _showOverlay();
                  onTap();
                }
              : null,
          child: SizedBox(
            width: 48,
            height: 42,
            child: Icon(
              icon,
              color: enabled ? Colors.white : Colors.white24,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _textPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xD9202C39),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          _showOverlay();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _volumePill(bool compact) {
    return Container(
      height: 42,
      padding: EdgeInsets.only(left: 12, right: compact ? 8 : 12),
      decoration: BoxDecoration(
        color: const Color(0xD9202C39),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _volume <= 0
                ? Icons.volume_off_rounded
                : _volume < 50
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: compact ? 72 : 112,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: const Color(0xFFF0D84B),
                inactiveTrackColor: Colors.white30,
                thumbColor: const Color(0xFFF0D84B),
                overlayColor: const Color(0x33F0D84B),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                min: 0,
                max: 100,
                value: _volume.clamp(0, 100).toDouble(),
                onChanged: _setVolume,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
