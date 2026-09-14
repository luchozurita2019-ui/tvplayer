import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import 'provider_json_catalog_parser.dart';

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
    final catalog = await Isolate.run(
      () => const ProviderJsonCatalogParser().parse(content),
    );
    // Validar antes de escribir: un JSON inválido conserva la copia anterior.
    final directory = await _directory(serviceId);
    await directory.create(recursive: true);
    final target = File(directory.path + '/catalog.private.json');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final temporary = File(directory.path + '/$stamp.private.json');
    try {
      await temporary.writeAsString(content, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return ImportedProviderJson(target.path, catalog);
  }

  Future<ProviderJsonCatalog> load(String serviceId) async {
    final directory = await _directory(serviceId);
    final path = directory.path + '/catalog.private.json';
    return Isolate.run(
      () => const ProviderJsonCatalogParser().parseFile(File(path)),
    );
  }

  Future<void> remove(String serviceId) async {
    final directory = await _directory(serviceId);
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
