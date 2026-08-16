import 'package:flutter/material.dart';

import '../services/remote_provisioning_service.dart';
import 'home_screen.dart';

class RemoteAccessGate extends StatefulWidget {
  const RemoteAccessGate({super.key});

  @override
  State<RemoteAccessGate> createState() => _RemoteAccessGateState();
}

class _RemoteAccessGateState extends State<RemoteAccessGate> {
  final RemoteProvisioningService _remote = RemoteProvisioningService();

  bool _checking = true;
  bool _allowed = false;
  String? _deviceCode;
  RemoteDeviceAccessBlockedException? _blocked;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    if (!_remote.isSupported) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _allowed = true;
        _blocked = null;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _checking = true;
        _blocked = null;
      });
    }

    try {
      var credentials = await _remote.ensureRegistered();
      _deviceCode = credentials.code;

      try {
        await _remote.verifyAccess(credentials);
      } on RemoteDeviceCredentialsInvalidException {
        await _remote.clearCredentials();
        credentials = await _remote.ensureRegistered();
        _deviceCode = credentials.code;
        await _remote.verifyAccess(credentials);
      }

      if (!mounted) return;
      setState(() {
        _checking = false;
        _allowed = true;
        _blocked = null;
      });
    } on RemoteDeviceAccessBlockedException catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _allowed = false;
        _blocked = error;
      });
    } catch (_) {
      // Un fallo temporal de Internet o servidor no debe bloquear la app.
      if (!mounted) return;
      setState(() {
        _checking = false;
        _allowed = true;
        _blocked = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed) return const HomeScreen();

    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF07111F),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.live_tv_rounded, color: Color(0xFF1677FF), size: 58),
              SizedBox(height: 22),
              CircularProgressIndicator(color: Color(0xFF1677FF)),
              SizedBox(height: 16),
              Text(
                'Verificando acceso…',
                style: TextStyle(color: Color(0xFFB6C2D2), fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    final blocked = _blocked;
    final paymentDue = blocked?.isPaymentDue ?? false;
    final title = blocked?.title ?? 'Acceso suspendido';
    final message = blocked?.message ??
        'Este dispositivo se encuentra temporalmente desactivado.';

    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1C30),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: paymentDue
                        ? const Color(0xFFE4B94F)
                        : const Color(0xFF24354B),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'TV FULL PRO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Icon(
                      paymentDue
                          ? Icons.payments_outlined
                          : Icons.lock_outline_rounded,
                      color: paymentDue
                          ? const Color(0xFFE4B94F)
                          : const Color(0xFF1677FF),
                      size: 58,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFB6C2D2),
                        fontSize: 16,
                        height: 1.45,
                      ),
                    ),
                    if (paymentDue) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Cuando se acredite el pago, presioná Reintentar. No hace falta reinstalar la aplicación.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFE4B94F),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if ((_deviceCode ?? '').isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF09182B),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'CÓDIGO DEL DISPOSITIVO',
                              style: TextStyle(
                                color: Color(0xFF91A0B4),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _deviceCode!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _checking ? null : _checkAccess,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Reintentar'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
