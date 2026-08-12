from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"No se encontro bloque para {label} en {path}")
    p.write_text(text.replace(old, new, 1))


# 1) Selector de contenido: en telefono las tarjetas pasan a un layout
# horizontal, con iconos contenidos y espacio suficiente para el texto.
replace_once(
    "lib/screens/source_content_screen.dart",
    "childAspectRatio: columns == 1 ? 3.3 : 1.35,",
    "childAspectRatio: columns == 1 ? 2.55 : 1.35,",
    "aspecto de tarjetas de contenido",
)

old_card = """          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 58,
                color: enabled ? Colors.white : Colors.white30,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: enabled ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: enabled ? Colors.white70 : Colors.white30,
                ),
              ),
            ],
          ),"""
new_card = """          padding: const EdgeInsets.all(18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final iconWidget = Container(
                width: compact ? 58 : 72,
                height: compact ? 58 : 72,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: enabled ? 0.22 : 0.08),
                  borderRadius: BorderRadius.circular(compact ? 16 : 20),
                  border: Border.all(
                    color: accent.withValues(alpha: enabled ? 0.40 : 0.10),
                  ),
                ),
                child: Icon(
                  icon,
                  size: compact ? 34 : 42,
                  color: enabled ? Colors.white : Colors.white30,
                ),
              );

              final labels = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: compact
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: compact ? TextAlign.left : TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: enabled ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 20 : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: compact ? TextAlign.left : TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: enabled ? Colors.white70 : Colors.white30,
                    ),
                  ),
                ],
              );

              if (compact) {
                return Row(
                  children: [
                    iconWidget,
                    const SizedBox(width: 16),
                    Expanded(child: labels),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: enabled ? Colors.white54 : Colors.white12,
                    ),
                  ],
                );
              }

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  iconWidget,
                  const SizedBox(height: 14),
                  labels,
                ],
              );
            },
          ),"""
replace_once(
    "lib/screens/source_content_screen.dart",
    old_card,
    new_card,
    "contenido responsive de tarjetas",
)


# 2) Capa visual del reproductor. Un toque sobre el video oculta los controles;
# otro toque vuelve a mostrarlos. El motor Player no se modifica aqui.
replace_once(
    "lib/widgets/live_video_view.dart",
    """  void _scheduleOverlayHide() {
    _overlayTimer?.cancel();
    if (!_playing || _buffering) return;
    _overlayTimer = Timer(_overlayTimeout, () {
      if (!mounted || !_playing || _buffering) return;
      setState(() => _overlayVisible = false);
    });
  }
""",
    """  void _scheduleOverlayHide() {
    _overlayTimer?.cancel();
    if (!_playing || _buffering) return;
    _overlayTimer = Timer(_overlayTimeout, () {
      if (!mounted || !_playing || _buffering) return;
      setState(() => _overlayVisible = false);
    });
  }

  void _toggleOverlayFromPointer() {
    _overlayTimer?.cancel();
    if (!_overlayVisible) {
      _showOverlay();
      return;
    }
    if (!_playing || _buffering) return;
    setState(() => _overlayVisible = false);
  }
""",
    "toggle manual de overlay",
)
replace_once(
    "lib/widgets/live_video_view.dart",
    "onPointerDown: (_) => _showOverlay(),",
    "onPointerDown: (_) => _toggleOverlayFromPointer(),",
    "toque para ocultar controles",
)
replace_once(
    "lib/widgets/live_video_view.dart",
    "final compact = constraints.maxWidth < 760;",
    "final compact = constraints.maxWidth < 980 || MediaQuery.sizeOf(context).height < 520;",
    "modo compacto landscape",
)
replace_once(
    "lib/widgets/live_video_view.dart",
    """        _textPill(
          icon: Icons.aspect_ratio_rounded,
          label: _fitLabel,
          onTap: () => _toggleFit(videoState),
        ),""",
    """        if (compact)
          _iconPill(
            icon: Icons.aspect_ratio_rounded,
            tooltip: 'Formato: $_fitLabel',
            onTap: () => _toggleFit(videoState),
          )
        else
          _textPill(
            icon: Icons.aspect_ratio_rounded,
            label: _fitLabel,
            onTap: () => _toggleFit(videoState),
          ),""",
    "boton de aspecto compacto",
)
replace_once(
    "lib/widgets/live_video_view.dart",
    "final width = compact ? 72.0 : 106.0;\n    final height = compact ? 50.0 : 66.0;",
    "final width = compact ? 60.0 : 106.0;\n    final height = compact ? 42.0 : 66.0;",
    "logo compacto del canal",
)
replace_once(
    "lib/widgets/live_video_view.dart",
    "fontSize: compact ? 20 : 28,",
    "fontSize: compact ? 17 : 28,",
    "titulo compacto del canal",
)
replace_once(
    "lib/widgets/live_video_view.dart",
    "width: compact ? 92 : 132,",
    "width: compact ? 76 : 132,",
    "columna numero compacta",
)


# 3) Android/libmpv: un fallo transitorio al inicio recibe un unico reintento
# corto. La rama macOS sigue usando exactamente la logica anterior.
replace_once(
    "lib/screens/player_screen.dart",
    "import 'package:flutter/material.dart';",
    "import 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart';",
    "import foundation player",
)
replace_once(
    "lib/screens/player_screen.dart",
    "  static const int _maxLiveStartupCompatibilityFallbacks = 1;",
    "  static const int _maxLiveStartupCompatibilityFallbacks = 1;\n  static const int _maxAndroidTransientStartupRetries = 1;\n  static const Duration _androidTransientRetryDelay = Duration(milliseconds: 700);",
    "constantes retry Android",
)
replace_once(
    "lib/screens/player_screen.dart",
    "  bool _startupCompatibilityHint = false;",
    "  bool _startupCompatibilityHint = false;\n  bool _startupTransientFailureHint = false;\n  int _androidTransientStartupRetries = 0;",
    "estado retry Android",
)
replace_once(
    "lib/screens/player_screen.dart",
    "  int get _maxAutoRetries => _effectiveSettings.maxRetries;",
    "  bool get _isAndroidRuntime =>\n      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;\n\n  int get _maxAutoRetries => _effectiveSettings.maxRetries;",
    "detector Android player",
)

replace_once(
    "lib/screens/player_screen.dart",
    """  bool _isDefinitiveStartupFailureLog(String text) {
    if (!widget.isLiveContent || _hasEverPlayed) return false;
    final lower = text.toLowerCase();
""",
    """  bool _isTransientAndroidStartupFailure(String text) {
    if (!_isAndroidRuntime) return false;
    final lower = text.toLowerCase();
    return lower.contains('408') ||
        lower.contains('request timeout') ||
        lower.contains('429') ||
        lower.contains('too many requests') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('broken pipe') ||
        lower.contains('service unavailable') ||
        lower.contains('bad gateway') ||
        lower.contains('gateway timeout') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('tardó demasiado') ||
        lower.contains('no llegó el primer frame') ||
        (RegExp(r'\\b5\\d\\d\\b').hasMatch(lower) && lower.contains('http'));
  }

  bool _isDefinitiveStartupFailureLog(String text) {
    if (!widget.isLiveContent || _hasEverPlayed) return false;
    final lower = text.toLowerCase();

    // Android puede reportar un 429/5xx o un socket transitorio antes de que
    // el mismo stream abra normalmente. Un reintento corto evita falsos
    // positivos sin cambiar el comportamiento de macOS.
    if (_isTransientAndroidStartupFailure(lower)) return false;
""",
    "clasificacion transitoria Android",
)
replace_once(
    "lib/screens/player_screen.dart",
    """    if (widget.isLiveContent && !_hasEverPlayed && _opening) {
      _rememberStartupCompatibilityHint(text);
      if (_isDefinitiveStartupFailureLog(text)) {""",
    """    if (widget.isLiveContent && !_hasEverPlayed && _opening) {
      _rememberStartupCompatibilityHint(text);
      if (_isTransientAndroidStartupFailure(text)) {
        _startupTransientFailureHint = true;
      }
      if (_isDefinitiveStartupFailureLog(text)) {""",
    "recordar fallo transitorio Android",
)
replace_once(
    "lib/screens/player_screen.dart",
    """    if (!_hasEverPlayed && widget.isLiveContent) {
      final elapsedMs = _startupStopwatch?.elapsedMilliseconds ?? 999999;
      final failedQuickly = elapsedMs < 2500;
""",
    """    if (!_hasEverPlayed && widget.isLiveContent) {
      final androidTransient = _isAndroidRuntime &&
          (_startupTransientFailureHint ||
              _isTransientAndroidStartupFailure(message));
      if (androidTransient &&
          _androidTransientStartupRetries < _maxAndroidTransientStartupRetries) {
        _androidTransientStartupRetries++;
        setState(() {
          _reconnecting = true;
          _errorMessage = null;
          _engineDiagnostic =
              'Android: fallo transitorio, reintentando conexión…';
        });
        _retryTimer = Timer(_androidTransientRetryDelay, () {
          if (!mounted || failedSession != _sessionId) return;
          unawaited(_playCurrent(isRetry: true, forceNormalProbe: true));
        });
        return;
      }

      final elapsedMs = _startupStopwatch?.elapsedMilliseconds ?? 999999;
      final failedQuickly = elapsedMs < 2500;
""",
    "retry corto Android live",
)
replace_once(
    "lib/screens/player_screen.dart",
    """    _startupCompatibilityHint = false;
    _startupCompatibilityTarget = null;
    _opening = true;""",
    """    _startupCompatibilityHint = false;
    _startupCompatibilityTarget = null;
    _startupTransientFailureHint = false;
    _opening = true;""",
    "reset hint transitorio por intento",
)
replace_once(
    "lib/screens/player_screen.dart",
    """    if (!isRetry) {
      _retryCount = 0;
      _normalProbeFallbackUsed = false;""",
    """    if (!isRetry) {
      _retryCount = 0;
      _androidTransientStartupRetries = 0;
      _normalProbeFallbackUsed = false;""",
    "reset contador Android por canal",
)
replace_once(
    "lib/screens/player_screen.dart",
    """      _errorTitle = 'CANAL EN MANTENIMIENTO';
      _errorMessage = _channelMaintenanceMessage;""",
    """      _errorTitle = _isAndroidRuntime
          ? 'CANAL TEMPORALMENTE NO DISPONIBLE'
          : 'CANAL EN MANTENIMIENTO';
      _errorMessage = _isAndroidRuntime
          ? 'No pudimos obtener señal en este momento.\\nIntentá nuevamente en unos segundos.'
          : _channelMaintenanceMessage;""",
    "mensaje de canal Android",
)
replace_once(
    "lib/screens/player_screen.dart",
    """    final isChannelMaintenance =
        widget.isLiveContent && _errorTitle == 'CANAL EN MANTENIMIENTO';""",
    """    final isChannelMaintenance = widget.isLiveContent &&
        (_errorTitle == 'CANAL EN MANTENIMIENTO' ||
            _errorTitle == 'CANAL TEMPORALMENTE NO DISPONIBLE');""",
    "deteccion visual de error live",
)


# 4) Autenticacion/catalogo Xtream: si Android recibe un error de socket o
# timeout antes de responder, crea un cliente nuevo y repite una sola vez.
replace_once(
    "lib/services/xtream_service.dart",
    "import 'package:http/http.dart' as http;",
    "import 'package:flutter/foundation.dart';\nimport 'package:http/http.dart' as http;",
    "import foundation Xtream",
)
replace_once(
    "lib/services/xtream_service.dart",
    """    final response = await _client
        .get(authUri, headers: _jsonHeaders)
        .timeout(timeout);""",
    """    final response = await _getJsonWithAndroidRetry(authUri, timeout);""",
    "auth Xtream retry Android",
)
replace_once(
    "lib/services/xtream_service.dart",
    """    final response = await _client
        .get(uri, headers: _jsonHeaders)
        .timeout(timeout);""",
    """    final response = await _getJsonWithAndroidRetry(uri, timeout);""",
    "acciones Xtream retry Android",
)
replace_once(
    "lib/services/xtream_service.dart",
    "  static Map<String, String> _categoryMap(List<dynamic> raw) {",
    """  static bool get _isAndroidRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool _retryableAndroidConnectionError(Object error) {
    if (!_isAndroidRuntime) return false;
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('network is unreachable') ||
        text.contains('timed out') ||
        text.contains('timeoutexception') ||
        text.contains('clientexception');
  }

  static Future<http.Response> _getJsonWithAndroidRetry(
    Uri uri,
    Duration timeout,
  ) async {
    final attempts = _isAndroidRuntime ? 2 : 1;
    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await _client.get(uri, headers: _jsonHeaders).timeout(timeout);
      } catch (error) {
        lastError = error;
        if (attempt + 1 >= attempts ||
            !_retryableAndroidConnectionError(error)) {
          rethrow;
        }
        XtreamHttpClient.cancelBrowsingRequests();
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    throw lastError ?? Exception('No se pudo conectar con Xtream.');
  }

  static Map<String, String> _categoryMap(List<dynamic> raw) {""",
    "helper Xtream Android",
)


# 5) Los errores de conexion nunca deben mostrar username/password completos.
p = Path("lib/providers/iptv_provider.dart")
text = p.read_text()
hits = text.count("_error = e.toString();")
if hits < 3:
    raise SystemExit(f"Se esperaban al menos 3 errores directos, encontrados {hits}")
text = text.replace("_error = e.toString();", "_error = _friendlyConnectionError(e);")
marker = """  void _setLoading(bool value) {
"""
helper = """  String _friendlyConnectionError(Object error) {
    var message = error.toString();
    message = message.replaceAllMapped(
      RegExp(
        r'([?&](?:username|password)=)([^&#\\s]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}••••',
    );

    final lower = message.toLowerCase();
    if (lower.contains('wrong_version_number')) {
      return 'El servidor rechazó la conexión segura. Revisá si este proveedor usa http:// en lugar de https://.';
    }
    if (lower.contains('connection refused')) {
      return 'No se pudo conectar con el servidor. Verificá que el host y el puerto estén disponibles.';
    }
    return message;
  }

"""
if marker not in text:
    raise SystemExit("No se encontro _setLoading para insertar sanitizacion")
p.write_text(text.replace(marker, helper + marker, 1))
