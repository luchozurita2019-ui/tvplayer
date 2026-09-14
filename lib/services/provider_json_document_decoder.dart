import 'dart:convert';

/// Decodifica provider.json manteniendo JSON estricto como camino principal.
///
/// La APK de integración del proveedor acepta dos irregularidades presentes en
/// su catálogo de prueba: una comilla sobrante después de `summary.streams` y
/// el carácter `·`/`•` como marcador de `globalIndex` ausente. TV FULL sólo
/// normaliza esos casos conocidos; cualquier otra sintaxis inválida sigue
/// rechazándose para no ocultar errores reales del catálogo.
dynamic decodeProviderJsonDocument(String content) {
  final source = content.startsWith('\uFEFF') ? content.substring(1) : content;
  try {
    return jsonDecode(source);
  } on FormatException {
    final normalized = _normalizeKnownProviderSyntax(source);
    if (normalized == source) rethrow;
    return jsonDecode(normalized);
  }
}

String _normalizeKnownProviderSyntax(String source) {
  var value = source;

  // Ejemplo real del catálogo de integración:
  //   "streams": 453"
  // se normaliza a:
  //   "streams": 453
  value = value.replaceAllMapped(
    RegExp(r'("streams"\s*:\s*\d+)"(\s*[,}])'),
    (match) => '${match.group(1)}${match.group(2)}',
  );

  // Algunos samples usan un punto medio como marcador visual de índice vacío:
  //   "globalIndex": ·,
  // La APK del proveedor lo trata como dato ausente, no como error fatal.
  value = value.replaceAllMapped(
    RegExp(r'("globalIndex"\s*:\s*)[·•](\s*[,}])'),
    (match) => '${match.group(1)}null${match.group(2)}',
  );

  return value;
}
