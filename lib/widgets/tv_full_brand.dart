import 'package:flutter/material.dart';

import 'tv_full_clean_ui.dart';

/// Marca visual compartida por las superficies Android TV.
///
/// Reutiliza el icono oficial que ya firma y publica la aplicación para no
/// introducir otro recurso gráfico ni alterar el paquete Android.
class TvFullBrand extends StatelessWidget {
  final bool compact;
  final double iconSize;

  const TvFullBrand({
    super.key,
    this.compact = false,
    this.iconSize = 42,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'TV FULL PRO',
      image: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(iconSize * .22),
            child: Image.asset(
              'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
              width: iconSize,
              height: iconSize,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => Container(
                width: iconSize,
                height: iconSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(iconSize * .22),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [tvCleanBlue, tvCleanViolet],
                  ),
                ),
                child: Icon(
                  Icons.live_tv_rounded,
                  size: iconSize * .58,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 10),
            const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TV FULL',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    height: .95,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    letterSpacing: -.45,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'PRO',
                  style: TextStyle(
                    color: tvCleanCyan,
                    fontSize: 9.5,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.4,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
