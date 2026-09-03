import '../providers/iptv_provider.dart';

/// Devuelve el mensaje del panel sólo cuando representa un bloqueo real de
/// acceso. Los errores transitorios de red/sincronización no deben cortar un
/// servicio que ya tiene un catálogo local válido.
String? remoteAccessBlockMessage(IptvProvider provider) {
  final raw = provider.remoteSyncError?.trim();
  if (raw == null || raw.isEmpty) return null;
  final value = raw.toLowerCase();
  const blockedSignals = <String>[
    'falta de pago',
    'desactivado',
    'desactivada',
    'inactivo',
    'inactiva',
    'suspendido',
    'suspendida',
    'bloqueado',
    'bloqueada',
    'payment required',
    'inactive',
    'disabled',
    'suspended',
    'vencido',
    'vencida',
    'expired',
    'no autorizado',
    'unauthorized',
    'forbidden',
  ];
  for (final signal in blockedSignals) {
    if (value.contains(signal)) return raw;
  }
  return null;
}
