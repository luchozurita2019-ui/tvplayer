import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_performance_service.dart';
import '../services/streaming_premium_service.dart';

const Color streamingPremiumGold = Color(0xFFD8B55B);
const Color streamingPremiumGoldSoft = Color(0xFFF2D58A);

enum StreamingPremiumPlatform {
  netflix('netflix', 'NETFLIX', 'Series y películas'),
  max('hbomax', 'HBO MAX', 'Películas, series y estrenos'),
  prime('prime', 'PRIME VIDEO', 'Películas, series y originales'),
  crunchyroll('crunchyroll', 'CRUNCHYROLL', 'Anime y estrenos');

  final String backendId;
  final String title;
  final String subtitle;

  const StreamingPremiumPlatform(
    this.backendId,
    this.title,
    this.subtitle,
  );
}

/// V65: Streaming Premium funcional y aislado del motor IPTV.
/// Las sesiones se solicitan sólo al abrir una plataforma.
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

class _PlatformGrid extends StatefulWidget {
  const _PlatformGrid();

  @override
  State<_PlatformGrid> createState() => _PlatformGridState();
}

class _PlatformGridState extends State<_PlatformGrid> {
  final StreamingPremiumService _service = StreamingPremiumService();
  StreamingPremiumPlatform? _opening;

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

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
                opening: _opening == platform,
                enabled: _opening == null,
                onTap: () => _openPlatform(context, platform),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openPlatform(
    BuildContext context,
    StreamingPremiumPlatform platform,
  ) async {
    if (_opening != null) return;

    if (platform == StreamingPremiumPlatform.netflix) {
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            backgroundColor: Color(0xFF17140D),
            content: Text(
              'Netflix queda para la fase final. '
              'Esta prueba corrige MAX, Prime y Crunchyroll.',
            ),
          ),
        );
      return;
    }

    setState(() => _opening = platform);

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF17140D),
          content: Text('Preparando ${platform.title}…'),
        ),
      );

    try {
      await _service.open(
        platform.backendId,
        allowOfficialFallback: false,
      );
    } on StreamingPremiumUnavailableException catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 4),
            backgroundColor: const Color(0xFF2A1712),
            content: Text(error.toString()),
          ),
        );
    } on PlatformException catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 4),
            backgroundColor: const Color(0xFF2A1712),
            content: Text(
              error.message ?? 'No se pudo abrir ${platform.title}.',
            ),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 4),
            backgroundColor: const Color(0xFF2A1712),
            content: Text(
              'No se pudo preparar ${platform.title}. Intentá nuevamente.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }
}

class _PlatformCard extends StatefulWidget {
  final StreamingPremiumPlatform platform;
  final VoidCallback onTap;
  final bool autofocus;
  final bool opening;
  final bool enabled;

  const _PlatformCard({
    required this.platform,
    required this.onTap,
    this.autofocus = false,
    this.opening = false,
    this.enabled = true,
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
            autofocus: widget.autofocus,
            borderRadius: BorderRadius.circular(20),
            onFocusChange: (value) {
              if (_focused != value) setState(() => _focused = value);
            },
            onTap: widget.enabled ? widget.onTap : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              child: Row(
                children: [
                  _PlatformLogo(
                    platform: widget.platform,
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
                              'SESIÓN COMPARTIDA',
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
                  if (widget.opening)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: streamingPremiumGoldSoft,
                      ),
                    )
                  else
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

class _PlatformLogo extends StatelessWidget {
  final StreamingPremiumPlatform platform;
  final bool focused;

  const _PlatformLogo({
    required this.platform,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 78,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        color: const Color(0xFF08090B),
        border: Border.all(
          color: streamingPremiumGold.withValues(alpha: focused ? .62 : .20),
        ),
      ),
      child: RepaintBoundary(
        child: switch (platform) {
          StreamingPremiumPlatform.netflix => const _NetflixLogo(),
          StreamingPremiumPlatform.max => const _HboMaxLogo(),
          StreamingPremiumPlatform.prime => const _PrimeVideoLogo(),
          StreamingPremiumPlatform.crunchyroll => const _CrunchyrollLogo(),
        },
      ),
    );
  }
}

class _NetflixLogo extends StatelessWidget {
  const _NetflixLogo();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'N',
      style: TextStyle(
        color: Color(0xFFE50914),
        fontSize: 50,
        height: .9,
        fontWeight: FontWeight.w900,
        letterSpacing: -4,
      ),
    );
  }
}

class _HboMaxLogo extends StatelessWidget {
  const _HboMaxLogo();

  @override
  Widget build(BuildContext context) {
    return const FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'HBO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                height: .86,
                fontWeight: FontWeight.w900,
                letterSpacing: -.8,
              ),
            ),
            Text(
              'MAX',
              style: TextStyle(
                color: Color(0xFF9D7CFF),
                fontSize: 25,
                height: .95,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimeVideoLogo extends StatelessWidget {
  const _PrimeVideoLogo();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 78,
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 2,
            child: Text(
              'prime',
              style: TextStyle(
                color: Color(0xFF21A8E0),
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -.9,
              ),
            ),
          ),
          Positioned(
            top: 19,
            child: Text(
              'video',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 13,
            right: 13,
            height: 11,
            child: CustomPaint(painter: _PrimeSmilePainter()),
          ),
        ],
      ),
    );
  }
}

class _PrimeSmilePainter extends CustomPainter {
  const _PrimeSmilePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF21A8E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(1, 1)
      ..quadraticBezierTo(size.width * .52, size.height * 1.08, size.width - 5, 2);
    canvas.drawPath(path, paint);

    final arrow = Path()
      ..moveTo(size.width - 9, 0)
      ..lineTo(size.width - 2, 2)
      ..lineTo(size.width - 7, 7);
    canvas.drawPath(arrow, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CrunchyrollLogo extends StatelessWidget {
  const _CrunchyrollLogo();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 66,
      height: 54,
      child: CustomPaint(painter: _CrunchyrollMarkPainter()),
    );
  }
}

class _CrunchyrollMarkPainter extends CustomPainter {
  const _CrunchyrollMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .5, size.height * .5);
    final radius = size.height * .39;
    final orange = Paint()
      ..color = const Color(0xFFF47521)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, orange);
    canvas.drawCircle(
      Offset(center.dx + radius * .30, center.dy - radius * .12),
      radius * .63,
      Paint()..color = const Color(0xFF08090B),
    );
    canvas.drawCircle(
      Offset(center.dx + radius * .48, center.dy - radius * .17),
      radius * .21,
      orange,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
