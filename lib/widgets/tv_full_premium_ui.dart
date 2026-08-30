import 'dart:async';

import 'package:flutter/material.dart';

const Color tvFullCyan = Color(0xFF39C5FF);
const Color tvFullBlue = Color(0xFF245CFF);
const Color tvFullViolet = Color(0xFF8A48FF);
const Color tvFullPanel = Color(0xD90A1220);

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
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(.68, -.72),
              radius: 1.25,
              colors: [
                Color(0xFF101A43),
                Color(0xFF070C1B),
                Color(0xFF02050C),
              ],
              stops: [0, .52, 1],
            ),
          ),
        ),
        Positioned(
          right: compact ? -70 : -100,
          top: compact ? -70 : -105,
          child: IgnorePointer(
            child: Opacity(
              opacity: .07,
              child: Icon(
                Icons.movie_filter_rounded,
                size: compact ? 260 : 390,
                color: tvFullViolet,
              ),
            ),
          ),
        ),
        Positioned(
          left: compact ? -45 : -75,
          bottom: compact ? -65 : -95,
          child: IgnorePointer(
            child: Opacity(
              opacity: .055,
              child: Icon(
                Icons.location_city_rounded,
                size: compact ? 220 : 330,
                color: tvFullCyan,
              ),
            ),
          ),
        ),
        const IgnorePointer(
          child: CustomPaint(painter: _NeonWavePainter()),
        ),
        child,
      ],
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

  static const _days = <String>[
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];
  static const _months = <String>[
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
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
    final day = _days[_now.weekday - 1];
    final month = _months[_now.month - 1];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .035),
            border: Border.all(color: Colors.white.withValues(alpha: .14)),
          ),
          child: const Icon(Icons.schedule_rounded, size: 21),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$hour:$minute',
              style: const TextStyle(
                fontSize: 20,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '$day, ${_now.day} de $month',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

BoxDecoration tvFullGlassDecoration({
  bool focused = false,
  double radius = 16,
  Color accent = tvFullCyan,
}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: focused
          ? [
              accent.withValues(alpha: .16),
              tvFullViolet.withValues(alpha: .10),
              const Color(0xEE09111E),
            ]
          : const [
              Color(0xE6111927),
              Color(0xE9080E19),
            ],
    ),
    border: Border.all(
      color: focused ? accent : Colors.white.withValues(alpha: .105),
      width: focused ? 2.1 : 1,
    ),
    boxShadow: focused
        ? [
            BoxShadow(
              color: accent.withValues(alpha: .28),
              blurRadius: 20,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: tvFullViolet.withValues(alpha: .14),
              blurRadius: 34,
              spreadRadius: 2,
            ),
          ]
        : const [],
  );
}

class _NeonWavePainter extends CustomPainter {
  const _NeonWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final y = size.height * .82;
    final bluePath = Path()
      ..moveTo(-30, y)
      ..cubicTo(
        size.width * .20,
        y - size.height * .06,
        size.width * .45,
        y + size.height * .08,
        size.width * .67,
        y - size.height * .015,
      )
      ..cubicTo(
        size.width * .82,
        y - size.height * .07,
        size.width * .91,
        y + size.height * .04,
        size.width + 40,
        y - size.height * .13,
      );
    final purplePath = Path()
      ..moveTo(-20, y + size.height * .045)
      ..cubicTo(
        size.width * .24,
        y - size.height * .01,
        size.width * .45,
        y + size.height * .10,
        size.width * .68,
        y + size.height * .025,
      )
      ..cubicTo(
        size.width * .83,
        y - size.height * .025,
        size.width * .91,
        y + size.height * .07,
        size.width + 30,
        y - size.height * .055,
      );

    canvas.drawPath(
      bluePath,
      Paint()
        ..color = tvFullBlue.withValues(alpha: .34)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawPath(
      purplePath,
      Paint()
        ..color = tvFullViolet.withValues(alpha: .36)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawPath(
      bluePath,
      Paint()
        ..color = tvFullCyan.withValues(alpha: .10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10,
    );
    canvas.drawPath(
      purplePath,
      Paint()
        ..color = tvFullViolet.withValues(alpha: .08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
