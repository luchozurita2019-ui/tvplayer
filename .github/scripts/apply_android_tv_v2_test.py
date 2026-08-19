from pathlib import Path

REMOTE = Path('lib/services/remote_provisioning_service.dart')
GATE = Path('lib/screens/remote_access_gate.dart')
HOME = Path('lib/screens/tv_home_screen.dart')
LIVE = Path('lib/widgets/live_video_view.dart')

remote = REMOTE.read_text()
gate = GATE.read_text()
home = HOME.read_text()
live = LIVE.read_text()

# 1) Vinculación: un dispositivo registrado pero sin M3U/Xtream asignada no
# entra al HOME. Reutilizamos la pantalla de bloqueo existente para mostrar el
# código; no se cambia el protocolo ni los endpoints del panel.
old_verify = """  Future<void> verifyAccess(RemoteDeviceCredentials credentials) async {\n    await fetchConfiguration(credentials);\n  }\n"""
new_verify = """  Future<void> verifyAccess(RemoteDeviceCredentials credentials) async {\n    final configuration = await fetchConfiguration(credentials);\n    if (configuration.services.isEmpty) {\n      throw const RemoteDeviceAccessBlockedException(\n        reason: 'awaiting_service',\n        title: 'Vinculá este televisor',\n        message:\n            'Ingresá el código del dispositivo en el panel TV FULL y asigná una lista M3U o Xtream. Después elegí Reintentar.',\n      );\n    }\n  }\n"""
if old_verify in remote:
    remote = remote.replace(old_verify, new_verify, 1)
elif "reason: 'awaiting_service'" not in remote:
    raise SystemExit('remote verifyAccess marker not found')

# 2) La sincronización pesada termina ANTES de habilitar el HOME. Así no empieza
# a descargar/parsear catálogos mientras el usuario ya está reproduciendo.
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

success_marker = """        await _remote.verifyAccess(credentials);\n      }\n\n      if (!mounted) return;\n      setState(() {\n"""
success_v2 = """        await _remote.verifyAccess(credentials);\n      }\n\n      final provider = context.read<IptvProvider>();\n      await provider.init();\n      if (!mounted) return;\n      if (provider.playlists.isEmpty) {\n        setState(() {\n          _checking = false;\n          _allowed = false;\n          _blocked = RemoteDeviceAccessBlockedException(\n            reason: 'awaiting_service',\n            title: 'Vinculación pendiente',\n            message: provider.remoteSyncError ??\n                'La lista está asignada, pero todavía no pudo sincronizarse. Elegí Reintentar.',\n          );\n        });\n        return;\n      }\n\n      setState(() {\n"""
if success_marker in gate:
    gate = gate.replace(success_marker, success_v2, 1)
elif "final provider = context.read<IptvProvider>();" not in gate:
    raise SystemExit('RemoteAccessGate success marker not found')

home_init = """    WidgetsBinding.instance.addPostFrameCallback((_) {\n      unawaited(ParentalControlService.instance.init());\n      context.read<IptvProvider>().init();\n    });\n"""
home_v2 = """    WidgetsBinding.instance.addPostFrameCallback((_) {\n      unawaited(ParentalControlService.instance.init());\n      // El provider ya llega sincronizado desde RemoteAccessGate.\n    });\n"""
if home_init in home:
    home = home.replace(home_init, home_v2, 1)
elif "provider ya llega sincronizado desde RemoteAccessGate" not in home:
    raise SystemExit('TvHomeScreen init marker not found')

# 3) Reproductor: DPAD con foco real. V1 capturaba la primera flecha en un
# Focus padre pero no entregaba un foco inicial a los controles visuales.
if "final FocusNode _playPauseFocusNode" not in live:
    marker = "  final FocusNode _remoteFocusNode = FocusNode(debugLabel: 'tv-live-remote');\n"
    if marker not in live:
        raise SystemExit('V1 remote focus marker not found')
    live = live.replace(
        marker,
        marker + "  final FocusNode _playPauseFocusNode = FocusNode(debugLabel: 'tv-play-pause');\n",
        1,
    )

show_start = live.find("  void _showOverlay({bool scheduleHide = true}) {")
show_end = live.find("\n  void _scheduleOverlayHide()", show_start)
if show_start == -1 or show_end == -1:
    raise SystemExit('showOverlay method not found')
live = live[:show_start] + """  void _showOverlay({bool scheduleHide = true}) {\n    _overlayTimer?.cancel();\n    final wasHidden = !_overlayVisible;\n    if (mounted && wasHidden) {\n      setState(() => _overlayVisible = true);\n      WidgetsBinding.instance.addPostFrameCallback((_) {\n        if (mounted && _overlayVisible) _playPauseFocusNode.requestFocus();\n      });\n    }\n    if (scheduleHide) _scheduleOverlayHide();\n  }\n""" + live[show_end:]

init_focus_old = """    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (mounted) _scheduleOverlayHide();\n    });\n"""
init_focus_new = """    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (!mounted) return;\n      _playPauseFocusNode.requestFocus();\n      _scheduleOverlayHide();\n    });\n"""
if init_focus_old in live:
    live = live.replace(init_focus_old, init_focus_new, 1)

play_old = """        _iconPill(\n          icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,\n          tooltip: _playing ? 'Pausar' : 'Reproducir',\n          onTap: _togglePlayPause,\n        ),\n"""
play_new = """        _iconPill(\n          icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,\n          tooltip: _playing ? 'Pausar' : 'Reproducir',\n          focusNode: _playPauseFocusNode,\n          onTap: _togglePlayPause,\n        ),\n"""
if play_old not in live:
    raise SystemExit('play button marker not found')
live = live.replace(play_old, play_new, 1)

sig_old = """  Widget _iconPill({\n    required IconData icon,\n    required String tooltip,\n    bool enabled = true,\n    required VoidCallback onTap,\n  }) {\n"""
sig_new = """  Widget _iconPill({\n    required IconData icon,\n    required String tooltip,\n    bool enabled = true,\n    FocusNode? focusNode,\n    required VoidCallback onTap,\n  }) {\n"""
if sig_old not in live:
    raise SystemExit('icon pill signature marker not found')
live = live.replace(sig_old, sig_new, 1)

ink_old = """        child: InkWell(\n          borderRadius: BorderRadius.circular(22),\n          onTap: enabled\n"""
ink_new = """        child: InkWell(\n          focusNode: focusNode,\n          canRequestFocus: enabled,\n          focusColor: const Color(0xFF1677FF),\n          borderRadius: BorderRadius.circular(22),\n          onTap: enabled\n"""
if ink_old not in live:
    raise SystemExit('icon pill InkWell marker not found')
live = live.replace(ink_old, ink_new, 1)

if "_playPauseFocusNode.dispose();" not in live:
    live = live.replace(
        "    _remoteFocusNode.dispose();\n",
        "    _remoteFocusNode.dispose();\n    _playPauseFocusNode.dispose();\n",
        1,
    )

# V1 había añadido RepaintBoundary alrededor de Video como experimento. Para la
# prueba Impeller OFF lo retiramos y dejamos el árbol de video lo más directo.
build_start = live.find("  @override\n  Widget build(BuildContext context) {", live.find("KeyEventResult _handleTvRemoteKey"))
build_end = live.find("\n  Widget _buildControls(VideoState videoState)", build_start)
if build_start == -1 or build_end == -1:
    raise SystemExit('LiveVideoView build block not found')
live = live[:build_start] + """  @override\n  Widget build(BuildContext context) {\n    return FocusTraversalGroup(\n      policy: ReadingOrderTraversalPolicy(),\n      child: Focus(\n        focusNode: _remoteFocusNode,\n        autofocus: true,\n        onKeyEvent: _handleTvRemoteKey,\n        child: MouseRegion(\n          onHover: (_) => _showOverlay(),\n          child: Listener(\n            behavior: HitTestBehavior.translucent,\n            onPointerDown: (_) => _showOverlay(),\n            child: Video(\n              controller: widget.controller,\n              fit: _videoFit,\n              controls: (videoState) => _buildControls(videoState),\n            ),\n          ),\n        ),\n      ),\n    );\n  }\n""" + live[build_end:]

REMOTE.write_text(remote)
GATE.write_text(gate)
HOME.write_text(home)
LIVE.write_text(live)
print('Android TV V2 pairing, pre-home sync and player focus patch applied')
