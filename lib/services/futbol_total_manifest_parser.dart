import 'dart:convert';

class FutbolTotalManifest {
  final List<FutbolTotalListDefinition> lists;
  final FutbolTotalRemoteRules futbolRules;

  FutbolTotalManifest({
    required List<FutbolTotalListDefinition> lists,
    required this.futbolRules,
  }) : lists = List.unmodifiable(lists);

  Iterable<FutbolTotalListDefinition> get flowLists =>
      lists.where((item) => item.kind == 'flow');

  Iterable<FutbolTotalListDefinition> get futbolLists =>
      lists.where((item) => item.kind == 'futbol');
}

class FutbolTotalListDefinition {
  final String name;
  final String url;
  final String kind;
  final int ttlSeconds;

  const FutbolTotalListDefinition({
    required this.name,
    required this.url,
    required this.kind,
    required this.ttlSeconds,
  });
}

class FutbolTotalRemoteRules {
  final String eventoPath;
  final String? iframePattern;
  final List<String> discardPaths;
  final List<FutbolTotalHopRule> hops;

  FutbolTotalRemoteRules({
    required this.eventoPath,
    required this.iframePattern,
    required List<String> discardPaths,
    required List<FutbolTotalHopRule> hops,
  }) : discardPaths = List.unmodifiable(discardPaths),
       hops = List.unmodifiable(hops);

  static FutbolTotalRemoteRules empty() => FutbolTotalRemoteRules(
    eventoPath: '',
    iframePattern: null,
    discardPaths: const ['/chat/'],
    hops: const [],
  );
}

class FutbolTotalHopRule {
  final String host;
  final bool webViewMode;
  final String? playbackPattern;

  const FutbolTotalHopRule({
    required this.host,
    required this.webViewMode,
    required this.playbackPattern,
  });
}

class FutbolTotalManifestParser {
  const FutbolTotalManifestParser();

  FutbolTotalManifest parse(String content) {
    dynamic decoded;
    try {
      decoded = jsonDecode(
        content.startsWith('\uFEFF') ? content.substring(1) : content,
      );
    } on FormatException {
      throw const FormatException(
        'El manifiesto de Fútbol Total no es JSON válido.',
      );
    }

    if (decoded is! Map) {
      throw const FormatException(
        'El manifiesto de Fútbol Total debe ser un objeto JSON.',
      );
    }

    final root = Map<String, dynamic>.from(decoded);
    final rawLists = root['lists'];
    final lists = <FutbolTotalListDefinition>[];

    if (rawLists is List) {
      for (final raw in rawLists) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final name = _text(item['name']);
        final url = _text(item['url']);
        if (name == null || url == null || !_isHttpUrl(url)) continue;

        final rawKind = _text(item['kind'])?.toLowerCase();
        final kind = rawKind == null || rawKind.isEmpty ? 'flow' : rawKind;
        final ttl = _nonNegativeInt(item['ttl']);

        lists.add(
          FutbolTotalListDefinition(
            name: name,
            url: url,
            kind: kind,
            ttlSeconds: ttl,
          ),
        );
      }
    }

    return FutbolTotalManifest(
      lists: lists,
      futbolRules: _parseRules(root['futbol']),
    );
  }

  FutbolTotalRemoteRules _parseRules(dynamic raw) {
    if (raw is! Map) return FutbolTotalRemoteRules.empty();
    final map = Map<String, dynamic>.from(raw);

    final discard = <String>[];
    final rawDiscard = map['descartar'];
    if (rawDiscard is List) {
      for (final value in rawDiscard) {
        final text = _text(value);
        if (text != null) discard.add(text);
      }
    }
    if (discard.isEmpty) discard.add('/chat/');

    final hops = <FutbolTotalHopRule>[];
    final rawHops = map['saltos'];
    if (rawHops is List) {
      for (final rawHop in rawHops) {
        if (rawHop is! Map) continue;
        final hop = Map<String, dynamic>.from(rawHop);
        hops.add(
          FutbolTotalHopRule(
            host: _text(hop['host']) ?? '*',
            webViewMode: (_text(hop['modo']) ?? '').toLowerCase() == 'webview',
            playbackPattern: _text(hop['playback']),
          ),
        );
      }
    }

    return FutbolTotalRemoteRules(
      eventoPath: _text(map['evento_path']) ?? '',
      iframePattern: _text(map['iframe']),
      discardPaths: discard,
      hops: hops,
    );
  }

  String? _text(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int _nonNegativeInt(dynamic value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed < 0) return 0;
    return parsed;
  }

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}
