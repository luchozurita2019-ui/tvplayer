import 'dart:async';

import 'package:flutter/material.dart';

const Color tvCleanBackground = Color(0xFF050B14);
const Color tvCleanSurface = Color(0xE60A1422);
const Color tvCleanSurfaceSoft = Color(0xB80A1422);
const Color tvCleanSurfaceFocus = Color(0xFF10243A);
const Color tvCleanBlue = Color(0xFF2D8CFF);
const Color tvCleanCyan = Color(0xFF54D7FF);
const Color tvCleanViolet = Color(0xFF9077FF);
const Color tvCleanMuted = Color(0xFF8EA2BA);
const Color tvCleanLiveRed = Color(0xFFFF5F78);

class TvCleanBackground extends StatelessWidget {
  final Widget child;
  final bool compact;

  const TvCleanBackground({
    super.key,
    required this.child,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: tvCleanBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _CleanGlow(),
          child,
        ],
      ),
    );
  }
}

BoxDecoration tvCleanCardDecoration({
  bool focused = false,
  Color accent = tvCleanCyan,
  double radius = 14,
}) {
  return BoxDecoration(
    color: focused ? tvCleanSurfaceFocus : tvCleanSurfaceSoft,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: focused ? accent : Colors.white.withValues(alpha: .065),
      width: focused ? 1.8 : 1,
    ),
    boxShadow: [
      if (focused)
        BoxShadow(
          color: accent.withValues(alpha: .15),
          blurRadius: 20,
          spreadRadius: .5,
        ),
      BoxShadow(
        color: Colors.black.withValues(alpha: .20),
        blurRadius: 14,
        offset: const Offset(0, 7),
      ),
    ],
  );
}

class TvCleanCategoryRow extends StatefulWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final bool primary;
  final VoidCallback onTap;

  const TvCleanCategoryRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
    this.primary = false,
  });

  @override
  State<TvCleanCategoryRow> createState() => _TvCleanCategoryRowState();
}

class _TvCleanCategoryRowState extends State<TvCleanCategoryRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 85),
        decoration: BoxDecoration(
          color: _focused
              ? tvCleanBlue.withValues(alpha: .18)
              : widget.selected
                  ? tvCleanCyan.withValues(alpha: .08)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _focused
                ? tvCleanCyan
                : widget.selected
                    ? tvCleanCyan.withValues(alpha: .22)
                    : Colors.transparent,
            width: _focused ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            autofocus: widget.autofocus,
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 85),
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: active ? tvCleanCyan : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? Colors.white : Colors.white60,
                        fontSize: widget.primary ? 12.5 : 12,
                        fontWeight: active || widget.primary
                            ? FontWeight.w900
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.selected)
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: tvCleanCyan,
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

class TvCleanLiveBadge extends StatelessWidget {
  final bool compact;

  const TvCleanLiveBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4567).withValues(alpha: .13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFF6A83).withValues(alpha: .35),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: Color(0xFFFF6A83)),
          SizedBox(width: 5),
          Text(
            'EN VIVO',
            style: TextStyle(
              color: Color(0xFFFF93A5),
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: .6,
            ),
          ),
        ],
      ),
    );
  }
}

class TvCleanClock extends StatefulWidget {
  const TvCleanClock({super.key});

  @override
  State<TvCleanClock> createState() => _TvCleanClockState();
}

class _TvCleanClockState extends State<TvCleanClock> {
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
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return Text(
      '$hour:$minute',
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class TvCleanLoading extends StatelessWidget {
  final String label;

  const TvCleanLoading({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              color: tvCleanCyan,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CleanGlow extends StatelessWidget {
  const _CleanGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: -220,
            top: -260,
            child: Container(
              width: 620,
              height: 620,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    tvCleanBlue.withValues(alpha: .095),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -280,
            bottom: -310,
            child: Container(
              width: 720,
              height: 720,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    tvCleanCyan.withValues(alpha: .055),
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
