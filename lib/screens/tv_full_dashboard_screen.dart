import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _background = Color(0xFF050B14);
const Color _panel = Color(0xB30A1422);
const Color _panelStrong = Color(0xEA0A1422);
const Color _blue = Color(0xFF2D8CFF);
const Color _cyan = Color(0xFF54D7FF);
const Color _textMuted = Color(0xFF8EA2BA);

enum TvFullDashboardSection {
  live,
  movies,
  series,
  sports,
  kids,
  adults,
}

class TvFullDashboardAction {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget? child;

  const TvFullDashboardAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.child,
  });
}

class TvFullDashboardScreen extends StatefulWidget {
  final String playlistName;
  final List<TvFullDashboardAction> actions;
  final Widget footer;
  final Widget? notice;
  final ValueChanged<TvFullDashboardSection> onOpenSection;

  const TvFullDashboardScreen({
    super.key,
    required this.playlistName,
    required this.actions,
    required this.footer,
    required this.onOpenSection,
    this.notice,
  });

  @override
  State<TvFullDashboardScreen> createState() => _TvFullDashboardScreenState();
}

class _TvFullDashboardScreenState extends State<TvFullDashboardScreen> {
  late final List<FocusNode> _sectionFocusNodes = List<FocusNode>.generate(
    TvFullDashboardSection.values.length,
    (index) => FocusNode(debugLabel: 'dashboard-section-$index'),
  );

  @override
  void dispose() {
    for (final node in _sectionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleSectionKeys(KeyEvent event, int columns) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final current = _sectionFocusNodes.indexWhere((node) => node.hasFocus);
    if (current < 0) return KeyEventResult.ignored;

    final key = event.logicalKey;
    int? target;
    if (key == LogicalKeyboardKey.arrowLeft && current % columns != 0) {
      target = current - 1;
    } else if (key == LogicalKeyboardKey.arrowRight &&
        current % columns != columns - 1 &&
        current + 1 < _sectionFocusNodes.length) {
      target = current + 1;
    } else if (key == LogicalKeyboardKey.arrowUp && current >= columns) {
      target = current - columns;
    } else if (key == LogicalKeyboardKey.arrowDown &&
        current + columns < _sectionFocusNodes.length) {
      target = current + columns;
    }

    if (target == null) return KeyEventResult.ignored;
    _sectionFocusNodes[target].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _BackgroundGlow(),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(28, 18, 28, 18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 980;
                final columns = constraints.maxWidth >= 820 ? 3 : 2;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(
                      playlistName: widget.playlistName,
                      actions: widget.actions,
                      compact: compact,
                    ),
                    if (widget.notice != null) ...[
                      const SizedBox(height: 12),
                      widget.notice!,
                    ],
                    SizedBox(height: compact ? 18 : 26),
                    Expanded(
                      child: Focus(
                        onKeyEvent: (_, event) =>
                            _handleSectionKeys(event, columns),
                        child: GridView.builder(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: compact ? 14 : 18,
                            crossAxisSpacing: compact ? 14 : 18,
                            childAspectRatio: compact ? 1.72 : 1.88,
                          ),
                          itemCount: _sections.length,
                          itemBuilder: (context, index) {
                            final entry = _sections[index];
                            return _SectionCard(
                              focusNode: _sectionFocusNodes[index],
                              autofocus: index == 0,
                              title: entry.title,
                              subtitle: entry.subtitle,
                              icon: entry.icon,
                              accent: entry.accent,
                              onPressed: () =>
                                  widget.onOpenSection(entry.section),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.gamepad_rounded,
                          size: 15,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 7),
                        const Text(
                          'Flechas para navegar  ·  OK para abrir  ·  Atrás para volver',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        widget.footer,
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String playlistName;
  final List<TvFullDashboardAction> actions;
  final bool compact;

  const _TopBar({
    required this.playlistName,
    required this.actions,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 66 : 74,
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 20),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .24),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 38 : 44,
            height: compact ? 38 : 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_blue, _cyan],
              ),
              boxShadow: [
                BoxShadow(
                  color: _cyan.withValues(alpha: .20),
                  blurRadius: 18,
                ),
              ],
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TV FULL PRO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 18 : 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.35,
                ),
              ),
              const SizedBox(height: 3),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 210 : 320),
                child: Text(
                  playlistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          for (final action in actions) ...[
            _ToolbarButton(action: action),
            const SizedBox(width: 8),
          ],
          if (!compact) const _Clock(),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatefulWidget {
  final TvFullDashboardAction action;

  const _ToolbarButton({required this.action});

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.action.onPressed != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: _focused
            ? _blue.withValues(alpha: .20)
            : Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused
              ? _cyan
              : Colors.white.withValues(alpha: enabled ? .08 : .035),
          width: _focused ? 1.5 : 1,
        ),
      ),
      child: Tooltip(
        message: widget.action.tooltip,
        child: InkWell(
          canRequestFocus: enabled,
          onFocusChange: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          borderRadius: BorderRadius.circular(12),
          onTap: widget.action.onPressed,
          child: Center(
            child: widget.action.child ??
                Icon(
                  widget.action.icon,
                  size: 21,
                  color: enabled
                      ? (_focused ? _cyan : Colors.white70)
                      : Colors.white24,
                ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatefulWidget {
  final FocusNode focusNode;
  final bool autofocus;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onPressed;

  const _SectionCard({
    required this.focusNode,
    required this.autofocus,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onPressed,
  });

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
      scale: _focused ? 1.018 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: _focused ? _panelStrong : _panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                _focused ? widget.accent : Colors.white.withValues(alpha: .07),
            width: _focused ? 2 : 1,
          ),
          boxShadow: [
            if (_focused)
              BoxShadow(
                color: widget.accent.withValues(alpha: .18),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            BoxShadow(
              color: Colors.black.withValues(alpha: .22),
              blurRadius: 18,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onFocusChange: (focused) {
              if (_focused != focused) setState(() => _focused = focused);
            },
            onTap: widget.onPressed,
            child: Stack(
              children: [
                Positioned(
                  right: -18,
                  bottom: -24,
                  child: Icon(
                    widget.icon,
                    size: 142,
                    color: widget.accent.withValues(alpha: .055),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 18, 17),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: widget.accent.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: widget.accent.withValues(alpha: .25),
                          ),
                        ),
                        child: Icon(
                          widget.icon,
                          color: widget.accent,
                          size: 26,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 14,
                  top: 14,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 80),
                    opacity: _focused ? 1 : .35,
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: _focused ? widget.accent : Colors.white38,
                      size: 20,
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

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final minute = now.minute.toString().padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Text(
        '${now.hour.toString().padLeft(2, '0')}:$minute',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: -180,
            top: -220,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _blue.withValues(alpha: .12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -220,
            bottom: -260,
            child: Container(
              width: 620,
              height: 620,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _cyan.withValues(alpha: .08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionSpec {
  final TvFullDashboardSection section;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const _SectionSpec({
    required this.section,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });
}

const List<_SectionSpec> _sections = [
  _SectionSpec(
    section: TvFullDashboardSection.live,
    title: 'TV EN VIVO',
    subtitle: 'Canales y programación en directo',
    icon: Icons.live_tv_rounded,
    accent: Color(0xFF4EDCFF),
  ),
  _SectionSpec(
    section: TvFullDashboardSection.movies,
    title: 'PELÍCULAS',
    subtitle: 'Catálogo completo de películas',
    icon: Icons.movie_creation_rounded,
    accent: Color(0xFF6CA7FF),
  ),
  _SectionSpec(
    section: TvFullDashboardSection.series,
    title: 'SERIES',
    subtitle: 'Series, temporadas y episodios',
    icon: Icons.video_library_rounded,
    accent: Color(0xFF9B7BFF),
  ),
  _SectionSpec(
    section: TvFullDashboardSection.sports,
    title: 'DEPORTES',
    subtitle: 'Canales deportivos de la lista',
    icon: Icons.sports_soccer_rounded,
    accent: Color(0xFF51E6B1),
  ),
  _SectionSpec(
    section: TvFullDashboardSection.kids,
    title: 'INFANTILES',
    subtitle: 'Canales para chicos y familia',
    icon: Icons.child_care_rounded,
    accent: Color(0xFFFFC85A),
  ),
  _SectionSpec(
    section: TvFullDashboardSection.adults,
    title: 'ADULTOS',
    subtitle: 'Contenido protegido por control parental',
    icon: Icons.lock_rounded,
    accent: Color(0xFFFF6F8F),
  ),
];
