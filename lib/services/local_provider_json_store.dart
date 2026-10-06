import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'package:path_provider/path_provider.dart';

import 'provider_json_catalog_parser.dart';
import 'provider_json_document_decoder.dart';

class ImportedProviderJson {
  final String path;
  final ProviderJsonCatalog catalog;

  const ImportedProviderJson(this.path, this.catalog);
}

/// Copia privada duradera: no depende de permisos a un documento externo ni de
/// archivos temporales del selector. Nunca agrega catálogos a los assets.
class LocalProviderJsonStore {
  static final instance = LocalProviderJsonStore();

  final Future<Directory> Function() _supportDirectory;

  LocalProviderJsonStore({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  Future<Directory> _directory(String serviceId) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(serviceId)) {
      throw const FormatException('Identificador de catálogo local inválido.');
    }
    final support = await _supportDirectory();
    return Directory(support.path + '/tv_full_local_providers/' + serviceId);
  }

  Future<ImportedProviderJson> importContent(
    String serviceId,
    String content,
  ) async {
    final normalized = await Isolate.run(
      () => normalizeProviderJsonDocument(content),
    );
    final catalog = await Isolate.run(
      () => ProviderJsonCatalogParser(playbackProfile: serviceId).parse(normalized),
    );
    // Validar antes de escribir: un JSON inválido conserva la copia anterior.
    final directory = await _directory(serviceId);
    await directory.create(recursive: true);
    final target = File(directory.path + '/catalog.private.json');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final temporary = File(directory.path + '/$stamp.private.json');
    try {
      // Guardamos la versión JSON estricta ya normalizada. Así una lectura
      // posterior no depende de volver a reparar la sintaxis del proveedor.
      await temporary.writeAsString(normalized, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return ImportedProviderJson(target.path, catalog);
  }

  /// Descarga el JSON vivo del proveedor y lo pasa por el mismo pipeline de
  /// normalización/validación que una importación local. La copia anterior
  /// sólo se reemplaza si la descarga y el parseo terminan correctamente.
  Future<ImportedProviderJson> importUrl(
    String serviceId,
    String url, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('URL del catálogo del proveedor inválida.');
    }
    final response = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json, text/plain, */*',
        'User-Agent': 'TV-FULL-PRO/1.0',
      },
    ).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'El catálogo del proveedor respondió HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    final content = utf8.decode(response.bodyBytes, allowMalformed: false);
    if (content.trim().isEmpty) {
      throw const FormatException('El catálogo del proveedor está vacío.');
    }
    return importContent(serviceId, content);
  }

  Future<ProviderJsonCatalog> load(String serviceId) async {
    final directory = await _directory(serviceId);
    final path = directory.path + '/catalog.private.json';
    return Isolate.run(
      () => ProviderJsonCatalogParser(playbackProfile: serviceId).parseFile(File(path)),
    );
  }

  Future<void> remove(String serviceId) async {
    final directory = await _directory(serviceId);
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
