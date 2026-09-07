import 'package:flutter/material.dart';

import 'tv_full_brand.dart';
import 'tv_full_clean_ui.dart';

/// Presentación de TV en vivo. Reutiliza la textura Media3 y la lista de
/// canales existentes; no modifica reproducción, buffers ni red.
class TvLiveTheater extends StatelessWidget {
  final Widget video;
  final Widget channels;
  final String channelName;
  final VoidCallback onFullscreen;
  final VoidCallback onCategories;
  final VoidCallback onHome;
  final VoidCallback? onAudio;

  const TvLiveTheater({
    super.key,
    required this.video,
    required this.channels,
    required this.channelName,
    required this.onFullscreen,
    required this.onCategories,
    required this.onHome,
    this.onAudio,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF04070D),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1050;
            final outer = compact ? 12.0 : 20.0;
            final menuWidth = compact ? 150.0 : 194.0;
            final channelsWidth = compact ? 216.0 : 286.0;

            return Column(
              children: [
                _Header(compact: compact, outer: outer),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(outer, 0, outer, outer),
                    child: Row(
                      children: [
                        SizedBox(
                          width: menuWidth,
                          child: _MenuRail(
                            compact: compact,
                            onFullscreen: onFullscreen,
                            onCategories: onCategories,
                            onHome: onHome,
                            onAudio: onAudio,
                          ),
                        ),
                        SizedBox(width: compact ? 10 : 16),
                        Expanded(
                          child: _VideoStage(
                            video: video,
                            channelName: channelName,
                            compact: compact,
                            onFullscreen: onFullscreen,
                          ),
                        ),
                        SizedBox(width: compact ? 10 : 16),
                        SizedBox(
                          width: channelsWidth,
                          child: _ChannelsRail(channels: channels),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool compact;
  final double outer;

  const _Header({required this.compact, required this.outer});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 62 : 70,
      margin: EdgeInsets.fromLTRB(outer, 4, outer, 8),
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: .07)),
        ),
      ),
      child: Row(
        children: [
          TvFullBrand(iconSize: compact ? 38 : 44),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .035),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: .07)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 7, color: tvCleanCyan),
                SizedBox(width: 7),
                Text(
                  'TV EN VIVO',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 18),
            const TvCleanClock(),
          ],
        ],
      ),
    );
  }
}

class _MenuRail extends StatelessWidget {
  final bool compact;
  final VoidCallback onFullscreen;
  final VoidCallback onCategories;
  final VoidCallback onHome;
  final VoidCallback? onAudio;

  const _MenuRail({
    required this.compact,
    required this.onFullscreen,
    required this.onCategories,
    required this.onHome,
    required this.onAudio,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 7 : 9,
          compact ? 12 : 16,
          compact ? 7 : 9,
          10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 0, 8, 12),
              child: Text(
                compact ? 'MENÚ' : 'NAVEGACIÓN',
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.35,
                ),
              ),
            ),
            _NavButton(
              icon: Icons.fullscreen_rounded,
              label: 'PANTALLA COMPLETA',
              onPressed: onFullscreen,
              selected: false,
            ),
            _NavButton(
              icon: Icons.grid_view_rounded,
              label: 'CATEGORÍAS',
              onPressed: onCategories,
            ),
            _NavButton(
              icon: Icons.home_rounded,
              label: 'INICIO',
              onPressed: onHome,
            ),
            if (onAudio != null)
              _NavButton(
                icon: Icons.audiotrack_rounded,
                label: 'AUDIO',
                onPressed: onAudio!,
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 4),
              child: Text(
                compact ? 'OK seleccionar' : 'Control remoto · OK seleccionar',
                maxLines: 2,
                style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 9.5,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoStage extends StatelessWidget {
  final Widget video;
  final String channelName;
  final bool compact;
  final VoidCallback onFullscreen;

  const _VideoStage({
    required this.video,
    required this.channelName,
    required this.compact,
    required this.onFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: .08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .34),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: ColoredBox(color: Colors.black, child: video),
            ),
          ),
        ),
        SizedBox(height: compact ? 8 : 10),
        _Panel(
          height: compact ? 48 : 56,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
            child: Row(
              children: [
                const TvCleanLiveBadge(compact: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 13 : 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _FocusIconButton(
                  tooltip: 'Pantalla completa',
                  icon: Icons.fullscreen_rounded,
                  onPressed: onFullscreen,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChannelsRail extends StatelessWidget {
  final Widget channels;

  const _ChannelsRail({required this.channels});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: tvCleanCyan,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 9),
                const Text(
                  'CANALES',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .65,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: .055)),
          Expanded(child: channels),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final double? height;

  const _Panel({required this.child, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF080D15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
      child: child,
    );
  }
}

class _NavButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 95),
        decoration: BoxDecoration(
          color: _focused
              ? tvCleanBlue.withValues(alpha: .24)
              : widget.selected
                  ? tvCleanCyan.withValues(alpha: .10)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: _focused
                ? tvCleanCyan
                : widget.selected
                    ? tvCleanCyan.withValues(alpha: .26)
                    : Colors.transparent,
            width: _focused ? 1.6 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onPressed,
            onFocusChange: (value) => setState(() => _focused = value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 20,
                    color: active ? tvCleanCyan : Colors.white54,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? Colors.white : Colors.white60,
                        fontSize: 11.5,
                        fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                        letterSpacing: .25,
                      ),
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

class _FocusIconButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _FocusIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  State<_FocusIconButton> createState() => _FocusIconButtonState();
}

class _FocusIconButtonState extends State<_FocusIconButton> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.tooltip)
      ..addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 95),
      decoration: BoxDecoration(
        color: focused
            ? tvCleanCyan.withValues(alpha: .18)
            : Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: focused ? tvCleanCyan : Colors.white.withValues(alpha: .07),
          width: focused ? 1.5 : 1,
        ),
      ),
      child: IconButton(
        focusNode: _focusNode,
        tooltip: widget.tooltip,
        onPressed: widget.onPressed,
        icon: Icon(
          widget.icon,
          color: focused ? tvCleanCyan : Colors.white70,
        ),
      ),
    );
  }
}
