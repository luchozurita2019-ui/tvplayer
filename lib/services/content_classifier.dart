import '../models/channel.dart';

enum IptvContentKind {
  live,
  movies,
  series,
  radios,
}

extension IptvContentKindLabel on IptvContentKind {
  String get label => switch (this) {
        IptvContentKind.live => 'TV en vivo',
        IptvContentKind.movies => 'Películas',
        IptvContentKind.series => 'Series',
        IptvContentKind.radios => 'Radios',
      };
}

class ContentClassifier {
  const ContentClassifier._();

  static IptvContentKind classify(Channel channel) {
    final url = channel.url.toLowerCase();
    final group = (channel.group ?? '').toLowerCase();
    final name = channel.name.toLowerCase();
    final text = '$group $name';

    // Xtream Codes suele exponer rutas explícitas, por eso estas reglas son
    // las más confiables y se evalúan antes que los nombres/categorías.
    if (url.contains('/movie/')) return IptvContentKind.movies;
    if (url.contains('/series/')) return IptvContentKind.series;
    if (url.contains('/radio/') || url.startsWith('icy://')) {
      return IptvContentKind.radios;
    }

    if (_containsAny(group, const [
      'radio',
      'radios',
      'fm radio',
      'radio fm',
      'audio radio',
    ])) {
      return IptvContentKind.radios;
    }

    if (_containsAny(text, const [
      'peliculas',
      'películas',
      'movies',
      'movie',
      'vod',
      'cine',
      'cinema',
      'films',
      'filmes',
    ])) {
      return IptvContentKind.movies;
    }

    if (_containsAny(text, const [
      'series',
      'serie ',
      'tv shows',
      'shows',
      'temporada',
      'season ',
      'novelas',
    ])) {
      return IptvContentKind.series;
    }

    return IptvContentKind.live;
  }

  static List<Channel> filter(
    Iterable<Channel> channels,
    IptvContentKind kind,
  ) {
    return channels
        .where((channel) => classify(channel) == kind)
        .toList(growable: false);
  }

  static Map<IptvContentKind, int> counts(Iterable<Channel> channels) {
    final result = <IptvContentKind, int>{
      for (final kind in IptvContentKind.values) kind: 0,
    };
    for (final channel in channels) {
      final kind = classify(channel);
      result[kind] = (result[kind] ?? 0) + 1;
    }
    return result;
  }

  static bool _containsAny(String value, List<String> needles) {
    for (final needle in needles) {
      if (value.contains(needle)) return true;
    }
    return false;
  }
}
