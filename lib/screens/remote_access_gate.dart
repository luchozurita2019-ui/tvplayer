import 'package:flutter/material.dart';

import '../services/remote_provisioning_service.dart';
import 'tv_home_screen.dart';

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
      // Se conserva exactamente el comportamiento estable de la V3: un fallo
      // temporal de Internet/servidor no bloquea el acceso local a la app.
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
    if (_allowed) return const TvHomeScreen();

    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF060B12),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TvGateLogo(),
                SizedBox(height: 24),
                SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    color: Color(0xFF1677FF),
                    strokeWidth: 3,
                  ),
                ),
                SizedBox(height: 15),
                Text(
                  'Verificando acceso…',
                  style: TextStyle(
                    color: Color(0xFF9BA9BA),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
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
      backgroundColor: const Color(0xFF060B12),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final horizontalPadding = constraints.maxWidth >= 1400 ? 70.0 : 34.0;
            final verticalPadding = constraints.maxHeight >= 800 ? 42.0 : 24.0;

            final information = _GateInformation(
              paymentDue: paymentDue,
              title: title,
              message: message,
            );
            final actions = _GateActions(
              paymentDue: paymentDue,
              deviceCode: _deviceCode,
              checking: _checking,
              onRetry: _checkAccess,
            );

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1260, maxHeight: 760),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(wide ? 32 : 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C1725),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: paymentDue
                            ? const Color(0xFFE4B94F).withValues(alpha: 0.70)
                            : const Color(0xFF203149),
                      ),
                    ),
                    child: wide
                        ? Row(
                            children: [
                              Expanded(flex: 6, child: information),
                              const SizedBox(width: 32),
                              Container(width: 1, color: const Color(0xFF203149)),
                              const SizedBox(width: 32),
                              Expanded(flex: 5, child: actions),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                information,
                                const SizedBox(height: 24),
                                actions,
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GateInformation extends StatelessWidget {
  final bool paymentDue;
  final String title;
  final String message;

  const _GateInformation({
    required this.paymentDue,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final accent = paymentDue ? const Color(0xFFE4B94F) : const Color(0xFF1677FF);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TvGateLogo(),
        const SizedBox(height: 26),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            paymentDue ? Icons.payments_outlined : Icons.lock_outline_rounded,
            color: accent,
            size: 29,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 27,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          style: const TextStyle(
            color: Color(0xFF9BA9BA),
            fontSize: 15,
            height: 1.45,
          ),
        ),
        if (paymentDue) ...[
          const SizedBox(height: 14),
          const Text(
            'Cuando se acredite el pago, elegí Reintentar. No hace falta reinstalar la aplicación.',
            style: TextStyle(
              color: Color(0xFFE4B94F),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _GateActions extends StatelessWidget {
  final bool paymentDue;
  final String? deviceCode;
  final bool checking;
  final VoidCallback onRetry;

  const _GateActions({
    required this.paymentDue,
    required this.deviceCode,
    required this.checking,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final code = deviceCode?.trim() ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Vinculación con TV FULL',
          style: TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Usá este código en tu panel. La vinculación y el estado del servicio se sincronizan automáticamente.',
          style: TextStyle(
            color: Color(0xFF8D9CAF),
            fontSize: 12,
            height: 1.4,
          ),
        ),
        if (code.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF08111D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF203149)),
            ),
            child: Column(
              children: [
                const Text(
                  'CÓDIGO DEL DISPOSITIVO',
                  style: TextStyle(
                    color: Color(0xFF8D9CAF),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 9),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          autofocus: true,
          onPressed: checking ? null : onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1677FF),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Control remoto: DPAD para navegar · OK para seleccionar · BACK para volver',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF6F7E91), fontSize: 10),
        ),
      ],
    );
  }
}

class _TvGateLogo extends StatelessWidget {
  const _TvGateLogo();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFF1677FF),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: SizedBox(
            width: 46,
            height: 36,
            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 27),
          ),
        ),
        SizedBox(width: 11),
        Text(
          'TV FULL',
          style: TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(width: 6),
        Text(
          'PRO',
          style: TextStyle(
            color: Color(0xFFE4B94F),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
