import '../models/channel.dart';

enum IptvContentKind { live, movies, series, radios }

extension IptvContentKindLabel on IptvContentKind {
  String get label => switch (this) {
        IptvContentKind.live => 'TV en vivo',
        IptvContentKind.movies => 'Películas',
        IptvContentKind.series => 'Series',
        IptvContentKind.radios => 'Radios',
      };
}

class ContentBuckets {
  final List<Channel> live;
  final List<Channel> movies;
  final List<Channel> series;
  final List<Channel> radios;

  const ContentBuckets({
    required this.live,
    required this.movies,
    required this.series,
    required this.radios,
  });

  List<Channel> forKind(IptvContentKind kind) => switch (kind) {
        IptvContentKind.live => live,
        IptvContentKind.movies => movies,
        IptvContentKind.series => series,
        IptvContentKind.radios => radios,
      };

  int count(IptvContentKind kind) => forKind(kind).length;
}

class ContentClassifier {
  const ContentClassifier._();

  /// Respeta primero las señales explícitas del proveedor. Una extensión
  /// `.ts` o `.m3u8` por sí sola nunca decide que algo sea LIVE: muchos
  /// proveedores entregan VOD y episodios con esos contenedores.
  static IptvContentKind classify(Channel channel) {
    final url = channel.url.toLowerCase();
    final uri = Uri.tryParse(channel.url);
    final path = (uri?.path ?? url).toLowerCase();
    final group = _normalize(channel.group ?? '');

    if (path.contains('/movie/')) return IptvContentKind.movies;
    if (path.contains('/series/')) return IptvContentKind.series;
    if (path.contains('/radio/') || url.startsWith('icy://')) {
      return IptvContentKind.radios;
    }

    // En M3U, group-title es estructura explícita entregada por el proveedor.
    // Se conserva su intención y su orden; no se reordena ni se aplana A–Z.
    if (_containsAny(group, const [
      'series',
      'serie',
      'temporada',
      'episodios',
      'episodio',
      'novelas',
    ])) {
      return IptvContentKind.series;
    }
    if (_containsAny(group, const [
      'peliculas',
      'pelicula',
      'movies',
      'movie',
      'vod',
      'cine',
      'films',
      'film',
    ])) {
      return IptvContentKind.movies;
    }

    if (_hasVideoFileExtension(path)) return IptvContentKind.movies;
    if (_hasAudioFileExtension(path) || _looksLikeRadioGroup(group)) {
      return IptvContentKind.radios;
    }

    // Sólo cuando no existe ninguna señal explícita de VOD/Series/Radio se
    // conserva como LIVE. Esto evita repetir la regresión de V13.
    return IptvContentKind.live;
  }

  static ContentBuckets partition(Iterable<Channel> channels) {
    final live = <Channel>[];
    final movies = <Channel>[];
    final series = <Channel>[];
    final radios = <Channel>[];

    for (final channel in channels) {
      switch (classify(channel)) {
        case IptvContentKind.live:
          live.add(channel);
        case IptvContentKind.movies:
          movies.add(channel);
        case IptvContentKind.series:
          series.add(channel);
        case IptvContentKind.radios:
          radios.add(channel);
      }
    }

    return ContentBuckets(
      live: List.unmodifiable(live),
      movies: List.unmodifiable(movies),
      series: List.unmodifiable(series),
      radios: List.unmodifiable(radios),
    );
  }

  static List<Channel> filter(
    Iterable<Channel> channels,
    IptvContentKind kind,
  ) =>
      partition(channels).forKind(kind);

  static Map<IptvContentKind, int> counts(Iterable<Channel> channels) {
    final buckets = partition(channels);
    return {
      for (final kind in IptvContentKind.values) kind: buckets.count(kind),
    };
  }

  static bool _hasVideoFileExtension(String path) {
    return const [
      '.mp4',
      '.mkv',
      '.avi',
      '.mov',
      '.m4v',
      '.webm',
      '.wmv',
      '.flv',
    ].any(path.endsWith);
  }

  static bool _hasAudioFileExtension(String path) {
    return const [
      '.mp3',
      '.aac',
      '.m4a',
      '.flac',
      '.ogg',
      '.opus',
    ].any(path.endsWith);
  }

  static bool _looksLikeRadioGroup(String group) {
    final normalized = group.trim();
    return normalized == 'radio' ||
        normalized == 'radios' ||
        normalized.startsWith('radio ') ||
        normalized.endsWith(' radio') ||
        normalized.contains('radio fm') ||
        normalized.contains('fm radio');
  }

  static bool _containsAny(String value, List<String> terms) {
    for (final term in terms) {
      if (value.contains(term)) return true;
    }
    return false;
  }

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
}
