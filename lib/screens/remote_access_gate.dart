import 'package:flutter/material.dart';

import '../services/remote_provisioning_service.dart';
import 'home_screen.dart';

class RemoteAccessGate extends StatefulWidget {
  const RemoteAccessGate({super.key});

  @override
  State<RemoteAccessGate> createState() => _RemoteAccessGateState();
}

class _RemoteAccessGateState extends State<RemoteAccessGate> {
  static const _background = Color(0xFF070B12);
  static const _panel = Color(0xFF0D1725);
  static const _border = Color(0xFF24354B);
  static const _blue = Color(0xFF16A8FF);
  static const _gold = Color(0xFFE4B94F);
  static const _text = Color(0xFFF4F7FB);
  static const _muted = Color(0xFF98A6B8);

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
        await _remote.fetchConfiguration(credentials);
      } on RemoteDeviceCredentialsInvalidException {
        await _remote.clearCredentials();
        credentials = await _remote.ensureRegistered();
        _deviceCode = credentials.code;
        await _remote.fetchConfiguration(credentials);
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
      // Una caída temporal de Internet o del servidor no debe bloquear una app
      // que ya estaba funcionando. El aprovisionamiento normal volverá a
      // intentar la sincronización dentro de HomeScreen.
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
    if (_checking) return _buildChecking();
    return _buildBlocked();
  }

  Widget _buildChecking() {
    return const Scaffold(
      backgroundColor: _background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TvFullMark(),
            SizedBox(height: 28),
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: _blue,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Verificando acceso…',
              style: TextStyle(
                color: _muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlocked() {
    final blocked = _blocked;
    final paymentDue = blocked?.isPaymentDue ?? false;
    final title = blocked?.title ?? 'Acceso suspendido';
    final message = blocked?.message ??
        'Este dispositivo se encuentra temporalmente desactivado.';

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                padding: const EdgeInsets.fromLTRB(34, 34, 34, 30),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: paymentDue
                        ? _gold.withValues(alpha: 0.55)
                        : _border,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 38,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _TvFullMark(),
                    const SizedBox(height: 28),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (paymentDue ? _gold : _blue)
                            .withValues(alpha: 0.10),
                        border: Border.all(
                          color: (paymentDue ? _gold : _blue)
                              .withValues(alpha: 0.42),
                        ),
                      ),
                      child: Icon(
                        paymentDue
                            ? Icons.payments_outlined
                            : Icons.lock_outline_rounded,
                        color: paymentDue ? _gold : _blue,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 15,
                        height: 1.55,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (paymentDue) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Una vez acreditado el pago, presioná Reintentar. No hace falta reinstalar la aplicación ni registrar nuevamente el dispositivo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _gold,
                          fontSize: 12,
                          height: 1.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if ((_deviceCode ?? '').isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF09111C),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'DISPOSITIVO  ',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              _deviceCode!,
                              style: const TextStyle(
                                color: _text,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
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
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
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

class _TvFullMark extends StatelessWidget {
  const _TvFullMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 54,
          height: 42,
          decoration: BoxDecoration(
            color: _RemoteAccessGateState._blue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: _RemoteAccessGateState._gold,
              width: 1.6,
            ),
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: _RemoteAccessGateState._blue,
            size: 28,
          ),
        ),
        const SizedBox(width: 13),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TV FULL PRO',
              style: TextStyle(
                color: _RemoteAccessGateState._text,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
            Text(
              'REMOTE SERVICE',
              style: TextStyle(
                color: _RemoteAccessGateState._muted,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
