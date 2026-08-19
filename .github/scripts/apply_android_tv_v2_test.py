from pathlib import Path

GATE = Path('lib/screens/remote_access_gate.dart')
HOME = Path('lib/screens/tv_home_screen.dart')
LIVE = Path('lib/widgets/live_video_view.dart')

gate = GATE.read_text()
home = HOME.read_text()
live = LIVE.read_text()

# ---------------------------------------------------------------------------
# 1) Vinculación TV: no entrar al HOME hasta que el panel tenga al menos un
#    servicio M3U/Xtream asignado y la sincronización local haya producido una
#    lista reproducible. Mientras espera, muestra el código y consulta cada 6 s.
# ---------------------------------------------------------------------------
if "import 'dart:async';" not in gate:
    gate = "import 'dart:async';\n\n" + gate

if "package:provider/provider.dart" not in gate:
    gate = gate.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport 'package:provider/provider.dart';",
        1,
    )

if "../providers/iptv_provider.dart" not in gate:
    gate = gate.replace(
        "import '../services/remote_provisioning_service.dart';",
        "import '../providers/iptv_provider.dart';\nimport '../services/remote_provisioning_service.dart';",
        1,
    )

if "bool _waitingForService = false;" not in gate:
    gate = gate.replace(
        "  RemoteDeviceAccessBlockedException? _blocked;",
        "  RemoteDeviceAccessBlockedException? _blocked;\n"
        "  bool _waitingForService = false;\n"
        "  String? _waitingMessage;\n"
        "  Timer? _linkPollTimer;",
        1,
    )

start = gate.find("  Future<void> _checkAccess() async {")
end = gate.find("\n  @override\n  Widget build(BuildContext context)", start)
if start == -1 or end == -1:
    raise SystemExit('RemoteAccessGate _checkAccess block not found')

replacement = r'''  void _scheduleLinkPoll() {
    _linkPollTimer?.cancel();
    if (!_waitingForService || _checking || !mounted) return;
    _linkPollTimer = Timer(const Duration(seconds: 6), _checkAccess);
  }

  void _setWaitingForService(String message) {
    if (!mounted) return;
    setState(() {
      _checking = false;
      _allowed = false;
      _blocked = null;
      _waitingForService = true;
      _waitingMessage = message;
    });
    _scheduleLinkPoll();
  }

  Future<void> _checkAccess() async {
    _linkPollTimer?.cancel();

    if (!_remote.isSupported) {
      if (!mounted) return;
      await context.read<IptvProvider>().init();
      if (!mounted) return;
      setState(() {
        _checking = false;
        _allowed = true;
        _blocked = null;
        _waitingForService = false;
        _waitingMessage = null;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _checking = true;
        _blocked = null;
        _waitingMessage = null;
      });
    }

    try {
      var credentials = await _remote.ensureRegistered();
      _deviceCode = credentials.code;

      RemoteProvisioningConfiguration configuration;
      try {
        configuration = await _remote.fetchConfiguration(credentials);
      } on RemoteDeviceCredentialsInvalidException {
        await _remote.clearCredentials();
        credentials = await _remote.ensureRegistered();
        _deviceCode = credentials.code;
        configuration = await _remote.fetchConfiguration(credentials);
      }

      if (!mounted) return;

      // El dispositivo puede estar registrado correctamente pero todavía no
      // tener una lista asignada. En TV no entramos al HOME en ese estado.
      if (configuration.services.isEmpty) {
        _setWaitingForService(
          'Ingresá este código en el panel TV FULL y asigná una lista M3U o Xtream. '
          'La aplicación entrará automáticamente cuando el servicio esté listo.',
        );
        return;
      }

      // La sincronización pesada ocurre ANTES de habilitar el HOME. De esta
      // manera no puede empezar a descargar/parsear catálogos mientras ya se
      // está reproduciendo un canal en una TV con pocos recursos.
      final provider = context.read<IptvProvider>();
      await provider.init();
      if (!mounted) return;

      if (provider.playlists.isEmpty) {
        _setWaitingForService(
          provider.remoteSyncError ??
              'El servicio está asignado, pero todavía no llegó una lista reproducible. '
                  'TV FULL volverá a comprobarlo automáticamente.',
        );
        return;
      }

      setState(() {
        _checking = false;
        _allowed = true;
        _blocked = null;
        _waitingForService = false;
        _waitingMessage = null;
      });
    } on RemoteDeviceAccessBlockedException catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _allowed = false;
        _blocked = error;
        _waitingForService = false;
        _waitingMessage = null;
      });
    } catch (error) {
      // Si el servidor está temporalmente fuera de línea, sólo permitimos
      // entrar cuando ya existe una lista local válida de una vinculación
      // anterior. Una instalación nueva sin lista permanece en la pantalla de
      // vinculación en vez de entrar vacía al HOME.
      final provider = context.read<IptvProvider>();
      try {
        await provider.init();
      } catch (_) {}
      if (!mounted) return;

      if (provider.playlists.isNotEmpty) {
        setState(() {
          _checking = false;
          _allowed = true;
          _blocked = null;
          _waitingForService = false;
          _waitingMessage = null;
        });
      } else {
        _setWaitingForService(
          'No se pudo verificar el panel en este momento. El código del dispositivo '
          'se conserva y TV FULL volverá a intentarlo automáticamente.',
        );
      }
    }
  }

  @override
  void dispose() {
    _linkPollTimer?.cancel();
    super.dispose();
  }
'''

gate = gate[:start] + replacement + gate[end:]

old_fallback = """    final blocked = _blocked;\n    final paymentDue = blocked?.isPaymentDue ?? false;\n    final title = blocked?.title ?? 'Acceso suspendido';\n    final message = blocked?.message ??\n        'Este dispositivo se encuentra temporalmente desactivado.';\n"""
new_fallback = """    final blocked = _blocked;\n    final paymentDue = blocked?.isPaymentDue ?? false;\n    final title = blocked?.title ??\n        (_waitingForService ? 'Vinculá este televisor' : 'Acceso suspendido');\n    final message = blocked?.message ??\n        _waitingMessage ??\n        'Este dispositivo se encuentra temporalmente desactivado.';\n"""
if old_fallback not in gate:
    raise SystemExit('RemoteAccessGate fallback text marker not found')
gate = gate.replace(old_fallback, new_fallback, 1)

# HOME: el provider ya llega inicializado/sincronizado desde el gate. Evitamos
# una segunda sincronización en segundo plano al entrar al HOME.
home_init = """    WidgetsBinding.instance.addPostFrameCallback((_) {\n      unawaited(ParentalControlService.instance.init());\n      context.read<IptvProvider>().init();\n    });\n"""
home_init_v2 = """    WidgetsBinding.instance.addPostFrameCallback((_) {\n      unawaited(ParentalControlService.instance.init());\n      // IptvProvider ya fue inicializado por RemoteAccessGate antes de entrar.\n      // No repetimos sincronización mientras el usuario navega o reproduce.\n    });\n"""
if home_init in home:
    home = home.replace(home_init, home_init_v2, 1)
elif "IptvProvider ya fue inicializado por RemoteAccessGate" not in home:
    raise SystemExit('TvHomeScreen init marker not found')

# ---------------------------------------------------------------------------
# 2) Reproductor TV: eliminar el RepaintBoundary experimental de V1 y hacer que
#    al mostrar controles el foco pase realmente a Play/Pause. Los InkWell del
#    reproductor reciben un focusColor azul fuerte para que DPAD sea visible.
# ---------------------------------------------------------------------------
if "final FocusNode _playPauseFocusNode" not in live:
    marker = "  final FocusNode _remoteFocusNode = FocusNode(debugLabel: 'tv-live-remote');\n"
    if marker not in live:
        raise SystemExit('V1 remote focus marker not found')
    live = live.replace(
        marker,
        marker + "  final FocusNode _playPauseFocusNode = FocusNode(debugLabel: 'tv-play-pause');\n",
        1,
    )

old_show = """  void _showOverlay({bool scheduleHide = true}) {\n    _overlayTimer?.cancel();\n    if (mounted && !_overlayVisible) {\n      setState(() => _overlayVisible = true);\n    }\n    if (scheduleHide) _scheduleOverlayHide();\n  }\n"""
new_show = """  void _showOverlay({bool scheduleHide = true}) {\n    _overlayTimer?.cancel();\n    final wasHidden = !_overlayVisible;\n    if (mounted && wasHidden) {\n      setState(() => _overlayVisible = true);\n      WidgetsBinding.instance.addPostFrameCallback((_) {\n        if (mounted && _overlayVisible) _playPauseFocusNode.requestFocus();\n      });\n    }\n    if (scheduleHide) _scheduleOverlayHide();\n  }\n"""
if old_show in live:
    live = live.replace(old_show, new_show, 1)
elif "_playPauseFocusNode.requestFocus()" not in live:
    raise SystemExit('overlay focus marker not found')

old_post_frame = """    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (mounted) _scheduleOverlayHide();\n    });\n"""
new_post_frame = """    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (!mounted) return;\n      _playPauseFocusNode.requestFocus();\n      _scheduleOverlayHide();\n    });\n"""
if old_post_frame in live:
    live = live.replace(old_post_frame, new_post_frame, 1)

old_nav = """    if (navigationKey && !_overlayVisible) {\n      _showOverlay(scheduleHide: false);\n      return KeyEventResult.handled;\n    }\n"""
new_nav = """    if (navigationKey && !_overlayVisible) {\n      _showOverlay(scheduleHide: false);\n      WidgetsBinding.instance.addPostFrameCallback((_) {\n        if (mounted) _playPauseFocusNode.requestFocus();\n      });\n      return KeyEventResult.handled;\n    }\n"""
if old_nav in live:
    live = live.replace(old_nav, new_nav, 1)

old_play_call = """        _iconPill(\n          icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,\n          tooltip: _playing ? 'Pausar' : 'Reproducir',\n          onTap: _togglePlayPause,\n        ),\n"""
new_play_call = """        _iconPill(\n          icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,\n          tooltip: _playing ? 'Pausar' : 'Reproducir',\n          focusNode: _playPauseFocusNode,\n          onTap: _togglePlayPause,\n        ),\n"""
if old_play_call not in live:
    raise SystemExit('play button marker not found')
live = live.replace(old_play_call, new_play_call, 1)

old_icon_sig = """  Widget _iconPill({\n    required IconData icon,\n    required String tooltip,\n    bool enabled = true,\n    required VoidCallback onTap,\n  }) {\n"""
new_icon_sig = """  Widget _iconPill({\n    required IconData icon,\n    required String tooltip,\n    bool enabled = true,\n    FocusNode? focusNode,\n    required VoidCallback onTap,\n  }) {\n"""
if old_icon_sig not in live:
    raise SystemExit('icon pill signature marker not found')
live = live.replace(old_icon_sig, new_icon_sig, 1)

old_icon_ink = """        child: InkWell(\n          borderRadius: BorderRadius.circular(22),\n          onTap: enabled\n"""
new_icon_ink = """        child: InkWell(\n          focusNode: focusNode,\n          canRequestFocus: enabled,\n          focusColor: const Color(0xFF1677FF),\n          borderRadius: BorderRadius.circular(22),\n          onTap: enabled\n"""
if old_icon_ink not in live:
    raise SystemExit('icon pill InkWell marker not found')
live = live.replace(old_icon_ink, new_icon_ink, 1)

for old, new in [
    (
        "child: InkWell(\n            customBorder: const CircleBorder(),\n            onTap:",
        "child: InkWell(\n            focusColor: const Color(0xFF1677FF),\n            customBorder: const CircleBorder(),\n            onTap:",
    ),
    (
        "child: InkWell(\n        borderRadius: BorderRadius.circular(20),\n        onTap:",
        "child: InkWell(\n        focusColor: const Color(0xFF1677FF),\n        borderRadius: BorderRadius.circular(20),\n        onTap:",
    ),
    (
        "child: InkWell(\n        borderRadius: BorderRadius.circular(22),\n        onTap: () {",
        "child: InkWell(\n        focusColor: const Color(0xFF1677FF),\n        borderRadius: BorderRadius.circular(22),\n        onTap: () {",
    ),
]:
    if old in live:
        live = live.replace(old, new)

if "_playPauseFocusNode.dispose();" not in live:
    live = live.replace(
        "    _remoteFocusNode.dispose();\n",
        "    _remoteFocusNode.dispose();\n    _playPauseFocusNode.dispose();\n",
        1,
    )

old_build = """  @override\n  Widget build(BuildContext context) {\n    return Focus(\n      focusNode: _remoteFocusNode,\n      autofocus: true,\n      onKeyEvent: _handleTvRemoteKey,\n      child: RepaintBoundary(\n        child: MouseRegion(\n          onHover: (_) => _showOverlay(),\n          child: Listener(\n            behavior: HitTestBehavior.translucent,\n            onPointerDown: (_) => _showOverlay(),\n            child: Video(\n              controller: widget.controller,\n              fit: _videoFit,\n              controls: (videoState) => _buildControls(videoState),\n            ),\n          ),\n        ),\n      ),\n    );\n  }\n"""
new_build = """  @override\n  Widget build(BuildContext context) {\n    return FocusTraversalGroup(\n      policy: ReadingOrderTraversalPolicy(),\n      child: Focus(\n        focusNode: _remoteFocusNode,\n        autofocus: true,\n        onKeyEvent: _handleTvRemoteKey,\n        child: MouseRegion(\n          onHover: (_) => _showOverlay(),\n          child: Listener(\n            behavior: HitTestBehavior.translucent,\n            onPointerDown: (_) => _showOverlay(),\n            child: Video(\n              controller: widget.controller,\n              fit: _videoFit,\n              controls: (videoState) => _buildControls(videoState),\n            ),\n          ),\n        ),\n      ),\n    );\n  }\n"""
if old_build not in live:
    raise SystemExit('V1 RepaintBoundary build marker not found')
live = live.replace(old_build, new_build, 1)

GATE.write_text(gate)
HOME.write_text(home)
LIVE.write_text(live)
print('Android TV V2 pairing, focus and low-overhead playback patch applied')
