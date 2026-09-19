import 'dart:convert';

class FutbolTotalAgenda {
  final List<FutbolTotalAgendaEvent> events;

  FutbolTotalAgenda(List<FutbolTotalAgendaEvent> events)
      : events = List.unmodifiable(events);

  int get channelCount =>
      events.fold<int>(0, (total, event) => total + event.channels.length);
}

class FutbolTotalAgendaEvent {
  final String title;
  final String status;
  final int timestampUtc;
  final List<FutbolTotalAgendaChannel> channels;

  FutbolTotalAgendaEvent({
    required this.title,
    required this.status,
    required this.timestampUtc,
    required List<FutbolTotalAgendaChannel> channels,
  }) : channels = List.unmodifiable(channels);

  bool get isLive {
    final value = status.toLowerCase();
    return value.contains('vivo') || value.contains('live');
  }
}

class FutbolTotalAgendaChannel {
  final String canalId;
  final String name;

  const FutbolTotalAgendaChannel({
    required this.canalId,
    required this.name,
  });
}

/// Parser del modo Fútbol reconstruido desde Fútbol Total 3.6.
///
/// La agenda es un array JSON. Los eventos finalizados y los canales marcados
/// con con_anuncios=true se omiten igual que en la aplicación original.
/// canal_id se conserva como referencia; no se trata como una URL multimedia.
class FutbolTotalAgendaParser {
  const FutbolTotalAgendaParser();

  FutbolTotalAgenda parse(String content) {
    dynamic decoded;
    try {
      decoded = jsonDecode(
        content.startsWith('\uFEFF') ? content.substring(1) : content,
      );
    } on FormatException {
      throw const FormatException('La agenda de Fútbol Total no es JSON válido.');
    }

    if (decoded is! List) {
      throw const FormatException('La agenda de Fútbol Total debe ser un array JSON.');
    }

    final events = <FutbolTotalAgendaEvent>[];

    for (final rawEvent in decoded) {
      if (rawEvent is! Map) continue;
      final event = Map<String, dynamic>.from(rawEvent);

      final status = _text(event['status']) ?? '';
      if (status.toLowerCase().contains('final')) continue;

      final rawChannels = event['canales'];
      if (rawChannels is! List) continue;

      final channels = <FutbolTotalAgendaChannel>[];
      for (final rawChannel in rawChannels) {
        if (rawChannel is! Map) continue;
        final channel = Map<String, dynamic>.from(rawChannel);

        final canalId = _text(channel['canal_id']);
        if (canalId == null) continue;
        if (_bool(channel['con_anuncios'])) continue;

        channels.add(
          FutbolTotalAgendaChannel(
            canalId: canalId,
            name: _text(channel['canal']) ?? 'Canal',
          ),
        );
      }

      if (channels.isEmpty) continue;

      final title =
          _text(event['titulo']) ??
          _text(event['categoria']) ??
          'Partido';

      events.add(
        FutbolTotalAgendaEvent(
          title: title,
          status: status,
          timestampUtc: _int(event['ts_utc']),
          channels: channels,
        ),
      );
    }

    return FutbolTotalAgenda(events);
  }

  String? _text(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _bool(dynamic value) {
    if (value is bool) return value;
    return value?.toString().toLowerCase() == 'true';
  }
}

/// Referencia interna equivalente al formato observado en Fútbol Total:
/// base-origen|canal_id.
class FutbolTotalAgendaReference {
  final String baseOrigin;
  final String canalId;

  const FutbolTotalAgendaReference({
    required this.baseOrigin,
    required this.canalId,
  });

  String get encoded => '$baseOrigin|$canalId';

  static FutbolTotalAgendaReference parse(String encoded) {
    final separator = encoded.lastIndexOf('|');
    if (separator <= 0 || separator >= encoded.length - 1) {
      throw const FormatException('Referencia de agenda inválida.');
    }
    final base = encoded.substring(0, separator).trim();
    final id = encoded.substring(separator + 1).trim();
    final uri = Uri.tryParse(base);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        id.isEmpty) {
      throw const FormatException('Referencia de agenda inválida.');
    }
    return FutbolTotalAgendaReference(baseOrigin: base, canalId: id);
  }

  static FutbolTotalAgendaReference fromAgendaUrl(
    String agendaUrl,
    String canalId,
  ) {
    final uri = Uri.tryParse(agendaUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException('URL de agenda inválida.');
    }

    final port = uri.hasPort ? ':${uri.port}' : '';
    return FutbolTotalAgendaReference(
      baseOrigin: '${uri.scheme}://${uri.host}$port',
      canalId: canalId,
    );
  }
}


class FutbolTotalEventRequest {
  final Uri url;
  final String referer;

  const FutbolTotalEventRequest({
    required this.url,
    required this.referer,
  });
}

/// Construye la URL de evento exactamente hasta el punto observado en la APK:
/// base-origen + evento_path + canal_id.
///
/// No inspecciona HTML, iframes ni reproductores. Esa etapa queda separada para
/// el resolvedor autorizado.
class FutbolTotalEventUrlBuilder {
  const FutbolTotalEventUrlBuilder();

  FutbolTotalEventRequest build(
    FutbolTotalAgendaReference reference,
    String eventoPath,
  ) {
    final path = eventoPath.trim();
    if (path.isEmpty) {
      throw const FormatException(
        'El manifiesto no contiene evento_path.',
      );
    }
    if (path.contains('\r') || path.contains('\n')) {
      throw const FormatException('evento_path inválido.');
    }
    if (reference.canalId.contains('\r') ||
        reference.canalId.contains('\n')) {
      throw const FormatException('canal_id inválido.');
    }

    final rawUrl = '${reference.baseOrigin}$path${reference.canalId}';
    final uri = Uri.tryParse(rawUrl);
    final base = Uri.tryParse(reference.baseOrigin);
    if (uri == null ||
        base == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.scheme != base.scheme ||
        uri.host != base.host ||
        uri.port != base.port) {
      throw const FormatException('La URL de evento resultante es inválida.');
    }

    return FutbolTotalEventRequest(
      url: uri,
      referer: reference.baseOrigin,
    );
  }
}
