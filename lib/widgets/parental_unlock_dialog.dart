import 'package:flutter/material.dart';

import '../services/parental_control_service.dart';

Future<bool> requestParentalUnlock(
  BuildContext context, {
  String title = 'Contenido protegido',
}) async {
  final parental = ParentalControlService.instance;
  await parental.init();
  if (!parental.enabled || parental.isUnlocked) return true;

  final controller = TextEditingController();
  final pin = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        decoration: const InputDecoration(
          labelText: 'PIN parental',
          counterText: '',
        ),
        onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('Desbloquear'),
        ),
      ],
    ),
  );
  controller.dispose();

  if (!context.mounted || pin == null) return false;
  final ok = await parental.unlock(pin);
  if (!context.mounted) return ok;
  if (!ok) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('PIN incorrecto.')));
  }
  return ok;
}
