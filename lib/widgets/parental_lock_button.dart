import 'package:flutter/material.dart';

class ParentalLockButton extends StatelessWidget {
  final bool unlocked;
  final int hiddenCategoryCount;
  final VoidCallback onPressed;

  const ParentalLockButton({
    super.key,
    required this.unlocked,
    required this.hiddenCategoryCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final hidden = unlocked ? 0 : hiddenCategoryCount;
    final hiddenLabel =
        hidden == 1 ? '1 categoría oculta' : '$hidden categorías ocultas';

    return IconButton(
      tooltip: unlocked
          ? 'Bloquear contenido protegido'
          : hidden > 0
              ? 'Desbloquear · $hiddenLabel'
              : 'Desbloquear contenido protegido',
      onPressed: onPressed,
      icon: SizedBox(
        width: 34,
        height: 32,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              unlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
            ),
            if (hidden > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    hidden > 99 ? '99+' : '$hidden',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onError,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
