import 'futbol_total_agenda_parser.dart';
import 'futbol_total_flow_catalog_parser.dart';
import 'futbol_total_manifest_parser.dart';
import 'futbol_total_authorized_fetcher.dart';

/// Fachada de red del puente Fútbol Total.
///
/// La URL del manifiesto se recibe desde configuración autorizada. Este archivo
/// no contiene tokens, firmas ni secretos del proyecto original.
class FutbolTotalCatalogService {
  FutbolTotalCatalogService({
    FutbolTotalAuthorizedFetcher? fetcher,
  }) : _fetcher = fetcher ?? FutbolTotalAuthorizedFetcher();

  final FutbolTotalAuthorizedFetcher _fetcher;

  Future<String> fetchRaw(
    String url, {
    bool noCache = false,
  }) =>
      _fetcher.fetch(url, noCache: noCache);

  Future<FutbolTotalManifest> loadManifest(String manifestUrl) async {
    final content = await _fetcher.fetch(manifestUrl);
    return const FutbolTotalManifestParser().parse(content);
  }

  Future<FutbolTotalAgenda> loadAgenda(
    FutbolTotalListDefinition definition,
  ) async {
    if (definition.kind != 'futbol') {
      throw const FormatException(
        'La lista seleccionada no es una agenda de fútbol.',
      );
    }
    final content = await _fetcher.fetch(definition.url);
    return const FutbolTotalAgendaParser().parse(content);
  }

  Future<FutbolTotalFlowCatalog> loadFlow(
    FutbolTotalListDefinition definition,
  ) async {
    if (definition.kind != 'flow') {
      throw const FormatException(
        'La lista seleccionada no es un catálogo Flow.',
      );
    }
    final content = await _fetcher.fetch(definition.url);
    return const FutbolTotalFlowCatalogParser().parse(content);
  }
  void close() => _fetcher.close();
}
