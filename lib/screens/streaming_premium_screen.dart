import 'package:flutter/material.dart';

import '../services/device_performance_service.dart';

const Color streamingPremiumGold = Color(0xFFD8B55B);
const Color streamingPremiumGoldSoft = Color(0xFFF2D58A);

enum StreamingPremiumPlatform {
  netflix('NETFLIX', 'Series y películas', 'N'),
  max('MAX', 'Películas, series y estrenos', 'MAX'),
  prime('PRIME VIDEO', 'Películas, series y originales', 'prime'),
  crunchyroll('CRUNCHYROLL', 'Anime y estrenos', 'CR');

  final String title;
  final String subtitle;
  final String monogram;

  const StreamingPremiumPlatform(this.title, this.subtitle, this.monogram);
}

/// V63: prueba visual aislada de Streaming Premium.
/// No crea WebViews ni toca el motor IPTV.
class StreamingPremiumScreen extends StatelessWidget {
  const StreamingPremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(.72, -.86),
                radius: 1.35,
                colors: [
                  Color(0xFF2A2110),
                  Color(0xFF0B0C10),
                  Color(0xFF020304),
                ],
                stops: [0, .46, 1],
              ),
            ),
          ),
          const IgnorePointer(child: CustomPaint(painter: _PremiumGoldPainter())),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(48, 30, 48, 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PremiumHeader(onBack: () => Navigator.of(context).maybePop()),
                  const SizedBox(height: 28),
                  const Expanded(child: _PlatformGrid()),
                  const SizedBox(height: 18),
                  const _PremiumFooter(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumHeader extends StatelessWidget {
  final VoidCallback onBack;

  const _PremiumHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GoldIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Volver',
          onPressed: onBack,
        ),
        const SizedBox(width: 18),
        Container(
          width: 4,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [streamingPremiumGoldSoft, streamingPremiumGold],
            ),
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'STREAMING PREMIUM',
                style: TextStyle(
                  color: streamingPremiumGoldSoft,
                  fontSize: 31,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.05,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Plataformas premium · prueba de interfaz',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const _StatusPill(),
      ],
    );
  }
}

class _PlatformGrid extends StatelessWidget {
  const _PlatformGrid();

  @override
  Widget build(BuildContext context) {
    const platforms = StreamingPremiumPlatform.values;
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowHeight = (constraints.maxHeight - 18) / 2;
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 18,
            mainAxisSpacing: 18,
            mainAxisExtent: rowHeight,
          ),
          itemCount: platforms.length,
          itemBuilder: (context, index) {
            final platform = platforms[index];
            return RepaintBoundary(
              child: _PlatformCard(
                platform: platform,
                autofocus: index == 0,
                onTap: () => _showInterfacePreview(context, platform),
              ),
            );
          },
        );
      },
    );
  }

  void _showInterfacePreview(
    BuildContext context,
    StreamingPremiumPlatform platform,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF17140D),
          content: Text(
            '${platform.title}: interfaz lista. La sesión temporal se conecta en la siguiente etapa.',
          ),
        ),
      );
  }
}

class _PlatformCard extends StatefulWidget {
  final StreamingPremiumPlatform platform;
  final VoidCallback onTap;
  final bool autofocus;

  const _PlatformCard({
    required this.platform,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_PlatformCard> createState() => _PlatformCardState();
}

class _PlatformCardState extends State<_PlatformCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    final duration = Duration(milliseconds: lowRam ? 70 : 115);
    final scale = _focused ? (lowRam ? 1.012 : 1.025) : 1.0;

    return AnimatedScale(
      scale: scale,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _focused
                ? const [Color(0xFF211B0F), Color(0xFF111115)]
                : const [Color(0xF20E0F12), Color(0xF208090B)],
          ),
          border: Border.all(
            color: streamingPremiumGold.withValues(
              alpha: _focused ? .88 : .28,
            ),
            width: _focused ? 1.35 : .8,
          ),
          boxShadow: lowRam || !_focused
              ? const []
              : [
                  BoxShadow(
                    color: streamingPremiumGold.withValues(alpha: .16),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              borderRadius: BorderRadius.circular(20),
            onFocusChange: (value) {
              if (_focused != value) setState(() => _focused = value);
            },
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              child: Row(
                children: [
                  _PlatformMonogram(
                    text: widget.platform.monogram,
                    focused: _focused,
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.platform.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _focused
                                ? streamingPremiumGoldSoft
                                : Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .45,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.platform.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Row(
                          children: [
                            _StatusDot(),
                            SizedBox(width: 8),
                            Text(
                              'PRUEBA DE INTERFAZ',
                              style: TextStyle(
                                color: streamingPremiumGold,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .75,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 18,
                    color: _focused
                        ? streamingPremiumGoldSoft
                        : Colors.white24,
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

class _StatusDot extends StatelessWidget {
  const _StatusDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: streamingPremiumGold,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _PlatformMonogram extends StatelessWidget {
  final String text;
  final bool focused;

  const _PlatformMonogram({
    required this.text,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            streamingPremiumGold.withValues(alpha: focused ? .25 : .12),
            Colors.white.withValues(alpha: focused ? .07 : .025),
          ],
        ),
        border: Border.all(
          color: streamingPremiumGold.withValues(alpha: focused ? .72 : .28),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            text,
            style: TextStyle(
              color: focused ? streamingPremiumGoldSoft : Colors.white70,
              fontSize: text.length > 3 ? 17 : 30,
              fontWeight: FontWeight.w900,
              letterSpacing: text.length > 3 ? -.4 : .5,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: streamingPremiumGold.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: streamingPremiumGold.withValues(alpha: .32),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium_rounded,
            color: streamingPremiumGold,
            size: 17,
          ),
          SizedBox(width: 7),
          Text(
            'BETA',
            style: TextStyle(
              color: streamingPremiumGoldSoft,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .9,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  const _GoldIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  State<_GoldIconButton> createState() => _GoldIconButtonState();
}

class _GoldIconButtonState extends State<_GoldIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(14),
          onFocusChange: (value) {
            if (_focused != value) setState(() => _focused = value);
          },
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: streamingPremiumGold.withValues(
                alpha: _focused ? .16 : .06,
              ),
              border: Border.all(
                color: streamingPremiumGold.withValues(
                  alpha: _focused ? .82 : .28,
                ),
              ),
            ),
            child: Icon(
              widget.icon,
              color: _focused
                  ? streamingPremiumGoldSoft
                  : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumFooter extends StatelessWidget {
  const _PremiumFooter();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(
          Icons.speed_rounded,
          color: streamingPremiumGold,
          size: 19,
        ),
        SizedBox(width: 9),
        Text(
          'Navegación rápida · animaciones ligeras · carga bajo demanda',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PremiumGoldPainter extends CustomPainter {
  const _PremiumGoldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = streamingPremiumGold.withValues(alpha: .055);

    final path = Path()
      ..moveTo(size.width * .58, 0)
      ..cubicTo(
        size.width * .72,
        size.height * .18,
        size.width * .74,
        size.height * .58,
        size.width,
        size.height * .69,
      );
    canvas.drawPath(path, paint);

    final second = Path()
      ..moveTo(0, size.height * .82)
      ..cubicTo(
        size.width * .18,
        size.height * .68,
        size.width * .34,
        size.height * .98,
        size.width * .52,
        size.height,
      );
    canvas.drawPath(second, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
