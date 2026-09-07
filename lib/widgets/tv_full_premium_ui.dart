import 'dart:async';

import 'package:flutter/material.dart';

const Color tvFullBackground = Color(0xFF07111F);
const Color tvFullCyan = Color(0xFF42D6FF);
const Color tvFullBlue = Color(0xFF1677FF);
const Color tvFullViolet = Color(0xFF755CFF);
const Color tvFullPanel = Color(0x99101C2D);
const Color tvFullPanelStrong = Color(0xC7121F31);
const Color tvFullLiveRed = Color(0xFFFF4059);
const Color tvFullMuted = Color(0xFF91A5BE);

class TvFullPremiumBackground extends StatelessWidget {
  final Widget child;
  final bool compact;

  const TvFullPremiumBackground({
    super.key,
    required this.child,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: tvFullBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0A1627),
                  Color(0xFF07111F),
                  Color(0xFF06101D),
                ],
              ),
            ),
          ),
          IgnorePointer(
            child: Align(
              alignment: const Alignment(.35, -.78),
              child: Container(
                width: compact ? 520 : 760,
                height: compact ? 180 : 230,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: RadialGradient(
                    colors: [
                      tvFullBlue.withValues(alpha: .065),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

BoxDecoration tvFullGlassDecoration({
  bool focused = false,
  double radius = 16,
  Color accent = tvFullCyan,
}) {
  return BoxDecoration(
    color: focused ? const Color(0xC8192B43) : const Color(0x8F101C2D),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: focused
          ? accent.withValues(alpha: .95)
          : Colors.white.withValues(alpha: .10),
      width: focused ? 1.8 : 1,
    ),
    boxShadow: [
      if (focused)
        BoxShadow(
          color: accent.withValues(alpha: .24),
          blurRadius: 22,
          spreadRadius: 1,
        ),
      BoxShadow(
        color: Colors.black.withValues(alpha: .18),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

class TvFullLiveBadge extends StatelessWidget {
  final bool compact;
  final String label;

  const TvFullLiveBadge({
    super.key,
    this.compact = false,
    this.label = 'EN VIVO',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: tvFullLiveRed.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tvFullLiveRed.withValues(alpha: .48)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 5 : 6,
            height: compact ? 5 : 6,
            decoration: const BoxDecoration(
              color: tvFullLiveRed,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: compact ? 5 : 6),
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFFFFD9DE),
              fontSize: compact ? 8.5 : 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .55,
            ),
          ),
        ],
      ),
    );
  }
}

class TvFullClock extends StatefulWidget {
  const TvFullClock({super.key});

  @override
  State<TvFullClock> createState() => _TvFullClockState();
}

class _TvFullClockState extends State<TvFullClock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    return Text(
      '$hour:$minute',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: .4,
      ),
    );
  }
}

class TvFullGlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool focused;

  const TvFullGlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.radius = 16,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: tvFullGlassDecoration(
        focused: focused,
        radius: radius,
      ),
      child: child,
    );
  }
}
