import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class CatalogFileSnapshot {
  final Map<String, dynamic> payload;
  final DateTime updatedAt;

  const CatalogFileSnapshot({required this.payload, required this.updatedAt});
}

/// Persistencia de catálogos pesados fuera de SQLite.
///
/// Cada servicio/sección mantiene generaciones independientes en Application
/// Support. Los items se escriben como NDJSON por streaming para evitar una fila
/// SQLite o un String JSON gigantesco en memoria. Un pequeño current.json apunta
/// a la última generación confirmada; si ese puntero falta, se recupera la
/// generación válida más reciente.
class CatalogFileStore {
  CatalogFileStore._();

  static final CatalogFileStore instance = CatalogFileStore._();

  static const int _version = 1;
  Directory? _root;

  Future<CatalogFileSnapshot?> loadSnapshot(
    String serviceId,
    String kind,
  ) async {
    final section = await _sectionDirectory(serviceId, kind);
    if (!await section.exists()) return null;

    final generation = await _resolveCurrentGeneration(section);
    if (generation == null) return null;
    return _readGeneration(generation);
  }

  Future<DateTime?> loadUpdatedAt(String serviceId, String kind) async {
    final snapshot = await loadSnapshot(serviceId, kind);
    return snapshot?.updatedAt;
  }

  Future<void> saveSnapshot({
    required String serviceId,
    required String kind,
    required Iterable<Object?> items,
    required List<String> categories,
  }) async {
    final section = await _sectionDirectory(serviceId, kind);
    await section.create(recursive: true);

    final now = DateTime.now();
    final stamp = now.microsecondsSinceEpoch;
    final temp = Directory('${section.path}/.tmp_$stamp');
    final generation = Directory('${section.path}/gen_$stamp');
    await temp.create(recursive: true);

    var count = 0;
    final itemsFile = File('${temp.path}/items.ndjson');
    final sink = itemsFile.openWrite();
    try {
      for (final item in items) {
        if (item == null) continue;
        sink.writeln(jsonEncode(item));
        count++;
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      await _deleteDirectoryQuietly(temp);
      rethrow;
    }

    if (count == 0) {
      await _deleteDirectoryQuietly(temp);
      throw const FormatException('No se guarda un catálogo vacío.');
    }

    await File('${temp.path}/categories.json').writeAsString(
      jsonEncode(categories),
      flush: true,
    );
    await File('${temp.path}/meta.json').writeAsString(
      jsonEncode({
        'version': _version,
        'updatedAt': now.millisecondsSinceEpoch,
        'count': count,
      }),
      flush: true,
    );

    await temp.rename(generation.path);

    final current = File('${section.path}/current.json');
    final pointerTemp = File('${section.path}/current.tmp');
    await pointerTemp.writeAsString(
      jsonEncode({
        'version': _version,
        'generation': generation.path.split(Platform.pathSeparator).last,
        'updatedAt': now.millisecondsSinceEpoch,
        'count': count,
      }),
      flush: true,
    );
    if (await current.exists()) await current.delete();
    await pointerTemp.rename(current.path);

    await _cleanupOldGenerations(section, keep: 2);
  }

  Future<void> clearService(String serviceId) async {
    final root = await _ensureRoot();
    final directory = Directory('${root.path}/${_serviceKey(serviceId)}');
    await _deleteDirectoryQuietly(directory);
  }

  Future<Directory?> _resolveCurrentGeneration(Directory section) async {
    final current = File('${section.path}/current.json');
    if (await current.exists()) {
      try {
        final decoded = jsonDecode(await current.readAsString());
        if (decoded is Map) {
          final name = decoded['generation']?.toString().trim() ?? '';
          if (name.startsWith('gen_')) {
            final candidate = Directory('${section.path}/$name');
            if (await candidate.exists()) return candidate;
          }
        }
      } catch (_) {}
    }

    final generations = await _generationDirectories(section);
    return generations.isEmpty ? null : generations.first;
  }

  Future<CatalogFileSnapshot?> _readGeneration(Directory generation) async {
    try {
      final metaRaw = jsonDecode(
        await File('${generation.path}/meta.json').readAsString(),
      );
      if (metaRaw is! Map || metaRaw['version'] != _version) return null;
      final updatedMillis =
          int.tryParse(metaRaw['updatedAt']?.toString() ?? '');
      if (updatedMillis == null || updatedMillis <= 0) return null;

      final categoriesRaw = jsonDecode(
        await File('${generation.path}/categories.json').readAsString(),
      );
      final categories = categoriesRaw is List
          ? categoriesRaw.map((e) => e.toString()).toList(growable: false)
          : const <String>[];

      final items = <dynamic>[];
      final stream = File('${generation.path}/items.ndjson')
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in stream) {
        final value = line.trim();
        if (value.isEmpty) continue;
        try {
          items.add(jsonDecode(value));
        } catch (_) {}
      }
      if (items.isEmpty) return null;

      return CatalogFileSnapshot(
        payload: <String, dynamic>{
          'categories': categories,
          'items': items,
        },
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMillis),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<Directory>> _generationDirectories(Directory section) async {
    final values = <Directory>[];
    try {
      await for (final entity in section.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('gen_')) values.add(entity);
      }
    } catch (_) {}
    values.sort((a, b) => b.path.compareTo(a.path));
    return values;
  }

  Future<void> _cleanupOldGenerations(
    Directory section, {
    required int keep,
  }) async {
    final values = await _generationDirectories(section);
    for (var index = keep; index < values.length; index++) {
      await _deleteDirectoryQuietly(values[index]);
    }
    try {
      await for (final entity in section.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.tmp_')) await _deleteDirectoryQuietly(entity);
      }
    } catch (_) {}
  }

  Future<Directory> _sectionDirectory(String serviceId, String kind) async {
    final root = await _ensureRoot();
    final safeKind = kind.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return Directory('${root.path}/${_serviceKey(serviceId)}/$safeKind');
  }

  Future<Directory> _ensureRoot() async {
    final existing = _root;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/tv_full_catalogs');
    if (!await directory.exists()) await directory.create(recursive: true);
    _root = directory;
    return directory;
  }

  String _serviceKey(String serviceId) =>
      sha256.convert(utf8.encode(serviceId.trim())).toString().substring(0, 24);

  Future<void> _deleteDirectoryQuietly(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }
}
