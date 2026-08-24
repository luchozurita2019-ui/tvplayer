from pathlib import Path
import re

ROOT = Path('.')
PLAYER = ROOT / 'lib/screens/player_screen.dart'
LIVE_FAST = ROOT / 'lib/services/xtream_live_fast_service.dart'
GRADLE = ROOT / 'android/app/build.gradle.kts'
REMOTE = ROOT / 'lib/services/remote_provisioning_service.dart'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Marcador no encontrado V12: {label}')
    return text.replace(old, new, 1)


def patch_logo_urls():
    text = LIVE_FAST.read_text()
    old = "      'logoUrl': _firstText(item, const ['stream_icon', 'logo', 'icon']),"
    new = "      'logoUrl': _resolveArtworkUrl(\n        streamServer,\n        _firstText(item, const ['stream_icon', 'logo', 'icon']),\n      ),"
    text = replace_once(text, old, new, 'normalizar logo LIVE')

    marker = '''String? _resolveDirect(Uri base, String? raw) {\n'''
    helper = '''String? _resolveArtworkUrl(Uri base, String? raw) {\n  final value = raw?.trim() ?? '';\n  if (value.isEmpty || value.toLowerCase() == 'null' || value == '0') {\n    return null;\n  }\n\n  if (value.startsWith('//')) {\n    final scheme = base.scheme == 'https' ? 'https' : 'http';\n    return '$scheme:$value';\n  }\n\n  final parsed = Uri.tryParse(value);\n  if (parsed != null &&\n      (parsed.scheme == 'http' || parsed.scheme == 'https') &&\n      parsed.host.isNotEmpty) {\n    return parsed.toString();\n  }\n\n  if (value.startsWith('/')) {\n    return base.resolve(value).toString();\n  }\n\n  // Algunos clones Xtream devuelven stream_icon como ruta relativa sin '/'.\n  // La resolvemos respecto del host del servicio en vez de descartarla.\n  final cleanBase = base.replace(query: '', fragment: '');\n  return cleanBase.resolve(value).toString();\n}\n\n'''
    text = replace_once(text, marker, helper + marker, 'helper logo relativo')
    LIVE_FAST.write_text(text)


def patch_vod_software_decode():
    text = PLAYER.read_text()

    if "import 'dart:io';" not in text:
        text = replace_once(
            text,
            "import 'dart:async';\n",
            "import 'dart:async';\nimport 'dart:io';\n",
            'import dart io',
        )

    old_comment = '''        // Android TV: no forzamos opciones de decodificación/sincronización\n        // desde la app. media_kit_video administra su Surface nativa y la ruta\n        // MediaCodec de Android para evitar copias innecesarias por CPU.\n'''
    new_comment = '''        // LIVE de Android TV no pasa por este reproductor: usa Media3.\n        // Para VOD desactivamos MediaCodec/hardware decoding. En el equipo de\n        // prueba, Media3 y MPV terminaban usando el mismo decoder Android y el\n        // proceso podía cerrarse durante una película. Software decode aísla\n        // VOD de ese decoder defectuoso sin tocar el motor LIVE estable.\n        if (!widget.isLiveContent) {\n          await platform.setProperty('hwdec', 'no');\n        }\n'''
    text = replace_once(text, old_comment, new_comment, 'software decode VOD')

    # VOD no recorre ocho modos de compatibilidad antes de mostrar un error.
    old_advance = '''  bool _advanceCompatibilityMode(\n    String reason, {\n    ServerCompatibilityMode? preferredTarget,\n  }) {\n    if (_hasEverPlayed || _compatibilityPlan.isEmpty) {\n'''
    new_advance = '''  bool _advanceCompatibilityMode(\n    String reason, {\n    ServerCompatibilityMode? preferredTarget,\n  }) {\n    if (!widget.isLiveContent) return false;\n    if (_hasEverPlayed || _compatibilityPlan.isEmpty) {\n'''
    text = replace_once(text, old_advance, new_advance, 'desactivar cascada VOD')

    marker = '''  Future<void> _playCurrent({\n'''
    helper = r'''  Future<String?> _preflightVod(Channel channel) async {
    if (widget.isLiveContent) return null;
    final uri = Uri.tryParse(channel.url.trim());
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'La URL de esta película o episodio no es válida.';
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-65535');

      final headers = channel.resolvedHttpHeaders(_defaultUserAgent);
      for (final entry in headers.entries) {
        try {
          request.headers.set(entry.key, entry.value);
        } catch (_) {}
      }

      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return 'El servidor rechazó el contenido (HTTP ${response.statusCode}).';
      }

      try {
        final firstChunk = await response.first.timeout(const Duration(seconds: 5));
        if (firstChunk.isEmpty) {
          return 'El servidor respondió pero no entregó datos de video.';
        }
      } on StateError {
        return 'El servidor respondió pero no entregó datos de video.';
      } on TimeoutException {
        return 'El servidor tardó demasiado en entregar los primeros datos.';
      }
      return null;
    } on TimeoutException {
      return 'El servidor tardó demasiado en responder.';
    } on SocketException {
      return 'No se pudo abrir la conexión de esta película o episodio.';
    } on HttpException catch (error) {
      return 'Error HTTP antes de reproducir: ${error.message}';
    } catch (error) {
      return 'No se pudo validar el contenido antes de reproducir.';
    } finally {
      client.close(force: true);
    }
  }

'''
    text = replace_once(text, marker, helper + marker, 'preflight VOD helper')

    old_prepare = '''    _lastKnownPosition = Duration.zero;\n    _lastProgressAt = DateTime.now();\n\n    final prepared = await _prepareChannelTuning(\n'''
    new_prepare = '''    _lastKnownPosition = Duration.zero;\n    _lastProgressAt = DateTime.now();\n\n    if (!widget.isLiveContent && !isRetry) {\n      final preflightError = await _preflightVod(widget.playlist[_currentIndex]);\n      if (!mounted || session != _sessionId) return;\n      if (preflightError != null) {\n        _opening = false;\n        _acceptPlaybackEvents = true;\n        _startupStopwatch?.stop();\n        setState(() {\n          _isBuffering = false;\n          _reconnecting = false;\n          _errorTitle = 'NO SE PUDO ABRIR EL CONTENIDO';\n          _errorMessage = preflightError;\n          _engineDiagnostic = 'V12 preflight bloqueó la apertura nativa';\n        });\n        return;\n      }\n    }\n\n    final prepared = await _prepareChannelTuning(\n'''
    text = replace_once(text, old_prepare, new_prepare, 'preflight antes del player')

    # En VOD, después de un fallo inicial no hacemos reintentos exponenciales.
    old_retry = '''    if (_retryCount < _maxAutoRetries) {\n      final seconds = 1 << _retryCount;\n'''
    new_retry = '''    final retryLimit = widget.isLiveContent ? _maxAutoRetries : 0;\n    if (_retryCount < retryLimit) {\n      final seconds = 1 << _retryCount;\n'''
    text = replace_once(text, old_retry, new_retry, 'sin reintentos VOD')

    PLAYER.write_text(text)


def patch_version():
    gradle = GRADLE.read_text()
    gradle = gradle.replace('applicationId = "com.tvfull.pro.tv.v11lazy"', 'applicationId = "com.tvfull.pro.tv.v12softvod"')
    GRADLE.write_text(gradle)

    remote = REMOTE.read_text()
    remote = remote.replace("'TV FULL Android TV V11 Lazy VOD Fix'", "'TV FULL Android TV V12 Software VOD'", 1)
    remote = remote.replace("'android-tv-v11-lazy-vod-fix'", "'android-tv-v12-software-vod-logo-fix'", 1)
    REMOTE.write_text(remote)


def verify():
    checks = {
        PLAYER: ["setProperty('hwdec', 'no')", '_preflightVod(', 'retryLimit = widget.isLiveContent'],
        LIVE_FAST: ['_resolveArtworkUrl(', "value.startsWith('//')"],
        GRADLE: ['com.tvfull.pro.tv.v12softvod'],
    }
    for path, markers in checks.items():
        text = path.read_text()
        for marker in markers:
            if marker not in text:
                raise SystemExit(f'Verificacion V12 fallo: {path} -> {marker}')


patch_logo_urls()
patch_vod_software_decode()
patch_version()
verify()
print('V12 aplicado: VOD software + preflight + logos normalizados.')
