from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        print(f"[ok] {label}: already applied")
        return text
    if old not in text:
        raise SystemExit(f"[error] {label}: expected marker not found")
    return text.replace(old, new, 1)


# 1) Source content cards: give portrait phones enough vertical room.
source_path = Path('lib/screens/source_content_screen.dart')
source = source_path.read_text(encoding='utf-8')
source = replace_once(
    source,
    "                childAspectRatio: columns == 1 ? 3.3 : 1.35,",
    "                childAspectRatio: columns == 1\n                    ? (constraints.maxWidth < 520 ? 1.85 : 2.3)\n                    : 1.35,",
    'portrait source cards',
)
source_path.write_text(source, encoding='utf-8')


# 2) Player warning badge: keep it below the top toolbar on narrow phones.
player_path = Path('lib/screens/player_screen.dart')
player = player_path.read_text(encoding='utf-8')
player = replace_once(
    player,
    "          Positioned(\n            top: 18,\n            right: 18,\n            child: SafeArea(child: _buildConnectionHealthBadge()),\n          ),",
    "          Positioned(\n            top: MediaQuery.sizeOf(context).width < 600 ? 76 : 18,\n            right: MediaQuery.sizeOf(context).width < 600 ? 10 : 18,\n            child: SafeArea(child: _buildConnectionHealthBadge()),\n          ),",
    'portrait connection badge',
)
player_path.write_text(player, encoding='utf-8')


# 3) LiveVideoView: compact top toolbar and wrap the bottom controls on portrait.
view_path = Path('lib/widgets/live_video_view.dart')
view = view_path.read_text(encoding='utf-8')

view = replace_once(
    view,
    "  Widget _buildTopBar(VideoState videoState) {\n    return Container(",
    "  Widget _buildTopBar(VideoState videoState) {\n    final compactTop = MediaQuery.sizeOf(context).width < 600;\n    return Container(",
    'compact player top bar marker',
)

view = replace_once(
    view,
    "            if (widget.isLiveContent) ...[",
    "            if (widget.isLiveContent && !compactTop) ...[",
    'hide live badge on narrow portrait toolbar',
)

view = replace_once(
    view,
    "            if (widget.performanceLabel != null &&\n                widget.onShowPerformance != null) ...[",
    "            if (!compactTop &&\n                widget.performanceLabel != null &&\n                widget.onShowPerformance != null) ...[",
    'hide performance chip on narrow toolbar',
)

view = replace_once(
    view,
    "        final compact = constraints.maxWidth < 760;\n        return Column(",
    "        final compact = constraints.maxWidth < 760;\n        final portraitPhone =\n            compact && MediaQuery.orientationOf(context) == Orientation.portrait;\n        return Column(",
    'portrait player layout flag',
)

view = replace_once(
    view,
    "            _buildControlRow(videoState, compact),",
    "            _buildControlRow(videoState, compact, portraitPhone),",
    'responsive control row call',
)

old_controls = '''  Widget _buildControlRow(VideoState videoState, bool compact) {
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
'''

new_controls = '''  Widget _buildControlRow(
    VideoState videoState,
    bool compact,
    bool portraitPhone,
  ) {
    if (portraitPhone) {
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _iconPill(
            icon: Icons.skip_previous_rounded,
            tooltip: 'Canal anterior',
            enabled: widget.canPrevious,
            onTap: widget.onPrevious,
          ),
          _iconPill(
            icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: _playing ? 'Pausar' : 'Reproducir',
            onTap: _togglePlayPause,
          ),
          _iconPill(
            icon: Icons.skip_next_rounded,
            tooltip: 'Canal siguiente',
            enabled: widget.canNext,
            onTap: widget.onNext,
          ),
          _iconPill(
            icon: Icons.aspect_ratio_rounded,
            tooltip: 'Ajuste de imagen: $_fitLabel',
            onTap: () => _toggleFit(videoState),
          ),
          if (!widget.isLiveContent)
            _iconPill(
              icon: Icons.language_rounded,
              tooltip: _audioButtonLabel,
              onTap: () => unawaited(_showAudioTrackPicker()),
            ),
          if (!widget.isLiveContent)
            _iconPill(
              icon: Icons.subtitles_rounded,
              tooltip: _subtitleButtonLabel,
              onTap: () => unawaited(_showSubtitleTrackPicker()),
            ),
          _volumePill(true),
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
'''

view = replace_once(
    view,
    old_controls,
    new_controls,
    'portrait wrapped player controls',
)

view_path.write_text(view, encoding='utf-8')
print('[done] Android mobile portrait UI V3 patch applied')
