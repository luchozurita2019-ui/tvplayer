import 'package:flutter/material.dart';

import 'tv_full_brand.dart';
import 'tv_full_premium_ui.dart';

/// Vista TV en vivo estilo teatro.
///
/// Es sólo presentación: recibe la misma textura Media3 y la misma lista de
/// canales que ya usa el reproductor. Cambiar entre esta vista y pantalla
/// completa no recrea el player ni modifica su estrategia de red.
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
            final railWidth = compact ? 150.0 : 194.0;
            final channelWidth = compact ? 216.0 : 286.0;
            final outer = compact ? 12.0 : 20.0;

            return Column(
              children: [
                _TopBar(compact: compact, outer: outer),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(outer, 0, outer, outer),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: railWidth,
                          child: _LeftRail(
                            compact: compact,
                            onFullscreen: onFullscreen,
                            onCategories: onCategories,
                            onHome: onHome,
                            onAudio: onAudio,
                          ),
                        ),
                        SizedBox(width: compact ? 10 : 16),
                        Expanded(
                          child: _CenterStage(
                            video: video,
                            channelName: channelName,
                            onFullscreen: onFullscreen,
                            compact: compact,
                          ),
                        ),
                        SizedBox(width: compact ? 10 : 16),
                        SizedBox(
                          width: channelWidth,
                          child: _ChannelRail(channels: channels),
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

class _TopBar extends StatelessWidget {
  final bool compact;
  final double outer;

  const _TopBar({required this.compact, required this.outer});

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
                Icon(Icons.circle, size: 7, color: tvFullCyan),
                SizedBox(width: 7),
                Text(
                  'TV EN VIVO',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 18),
            const TvFullClock(),
          ],
        ],
      ),
    );
  }
}

class _LeftRail extends StatelessWidget {
  final bool compact;
  final VoidCallback onFullscreen;
  final VoidCallback onCategories;
  final VoidCallback onHome;
  final VoidCallback? onAudio;

  const _LeftRail({
    required this.compact,
    required this.onFullscreen,
    required this.onCategories,
    required this.onHome,
    required this.onAudio,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF080D15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
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
              padding: EdgeInsets.fromLTRB(compact ? 8 : 10, 0, 8, 12),
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
            _RailAction(
              icon: Icons.live_tv_rounded,
              label: 'TV EN VIVO',
              selected: true,
              onTap: onFullscreen,
            ),
            const SizedBox(height: 6),
            _RailAction(
              icon: Icons.grid_view_rounded,
              label: 'CATEGORÍAS',
              onTap: onCategories,
            ),
            const SizedBox(height: 6),
            _RailAction(
              icon: Icons.auto_awesome_rounded,
              label: 'DESTACADOS',
              onTap: onHome,
            ),
            if (onAudio != null) ...[
              const SizedBox(height: 6),
              _RailAction(
                icon: Icons.audiotrack_rounded,
                label: 'AUDIO',
                onTap: onAudio!,
              ),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 4),
              child: Text(
                compact
                    ? 'OK seleccionar'
                    : 'Usá el control remoto para navegar',
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

class _CenterStage extends StatelessWidget {
  final Widget video;
  final String channelName;
  final VoidCallback onFullscreen;
  final bool compact;

  const _CenterStage({
    required this.video,
    required this.channelName,
    required this.onFullscreen,
    required this.compact,
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
        Container(
          height: compact ? 48 : 56,
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
          decoration: BoxDecoration(
            color: const Color(0xFF080D15),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white.withValues(alpha: .055)),
          ),
          child: Row(
            children: [
              const TvFullLiveBadge(compact: true),
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
              _FullscreenButton(onPressed: onFullscreen),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChannelRail extends StatelessWidget {
  final Widget channels;

  const _ChannelRail({required this.channels});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF080D15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
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
                    color: tvFullCyan,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'CANALES',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .65,
                    ),
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

class _FullscreenButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _FullscreenButton({required this.onPressed});

  @override
  State<_FullscreenButton> createState() => _FullscreenButtonState();
}

class _FullscreenButtonState extends State<_FullscreenButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 95),
      decoration: BoxDecoration(
        color: _focused
            ? tvFullCyan.withValues(alpha: .18)
            : Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: _focused ? tvFullCyan : Colors.white.withValues(alpha: .07),
          width: _focused ? 1.5 : 1,
        ),
      ),
      child: IconButton(
        tooltip: 'Pantalla completa',
        onPressed: widget.onPressed,
        onFocusChange: (value) => setState(() => _focused = value),
        icon: Icon(
          Icons.fullscreen_rounded,
          color: _focused ? tvFullCyan : Colors.white70,
        ),
      ),
    );
  }
}

class _RailAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  const _RailAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  State<_RailAction> createState() => _RailActionState();
}

class _RailActionState extends State<_RailAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || widget.selected;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 95),
      decoration: BoxDecoration(
        color: _focused
            ? tvFullBlue.withValues(alpha: .24)
            : widget.selected
                ? tvFullCyan.withValues(alpha: .10)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: _focused
              ? tvFullCyan
              : widget.selected
                  ? tvFullCyan.withValues(alpha: .26)
                  : Colors.transparent,
          width: _focused ? 1.6 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (value) => setState(() => _focused = value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 20,
                  color: active ? tvFullCyan : Colors.white54,
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
    );
  }
}
