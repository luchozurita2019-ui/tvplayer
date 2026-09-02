import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import 'catalog_file_store.dart';

/// Persistencia chica de TV FULL PRO.
///
/// SQLite conserva únicamente definición/orden de servicios y estado de la app.
/// Los catálogos pesados viven en CatalogFileStore dentro de Application Support.
/// La tabla catalog_snapshots sólo se lee para migrar instalaciones anteriores.
class TvLocalStore {
  TvLocalStore._();

  static final TvLocalStore instance = TvLocalStore._();

  final CatalogFileStore _catalogFiles = CatalogFileStore.instance;
  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final base = await getDatabasesPath();
    final db = await openDatabase(
      '$base/tv_full_pro.db',
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE services (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            source TEXT NOT NULL,
            source_type TEXT NOT NULL,
            is_remote INTEGER NOT NULL,
            display_order INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE app_state (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await _createRuntimeTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 -> v2: no se borra catalog_snapshots aquí. SectionCatalogService
        // migra cada snapshot válido a archivos y elimina la fila sólo después
        // de confirmar la escritura nueva.
        if (oldVersion < 3) await _createRuntimeTables(db);
      },
    );
    _database = db;
    return db;
  }

  Future<void> _createRuntimeTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS channel_health (
        channel_key TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        reason TEXT NOT NULL,
        expires_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS channel_logo_cache (
        lookup_key TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        expires_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<List<Playlist>> loadServices() async {
    final db = await database;
    final rows = await db.query('services', orderBy: 'display_order ASC');
    return rows.map((row) {
      final rawType = row['source_type']?.toString() ?? 'm3u';
      final type = PlaylistSourceType.values.firstWhere(
        (item) => item.name == rawType,
        orElse: () => PlaylistSourceType.m3u,
      );
      return Playlist(
        id: row['id']!.toString(),
        name: row['name']!.toString(),
        source: row['source']!.toString(),
        isRemote: (row['is_remote'] as int? ?? 1) == 1,
        channels: const [],
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at'] as int? ?? 0,
        ),
        sourceType: type,
      );
    }).toList(growable: false);
  }

  Future<void> saveServices(List<Playlist> playlists) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('services');
      for (var index = 0; index < playlists.length; index++) {
        final playlist = playlists[index];
        await txn.insert('services', {
          'id': playlist.id,
          'name': playlist.name,
          'source': playlist.source,
          'source_type': playlist.sourceType.name,
          'is_remote': playlist.isRemote ? 1 : 0,
          'display_order': index,
          'updated_at': playlist.lastUpdated.millisecondsSinceEpoch,
        });
      }
    });
  }

  Future<String?> loadSelectedServiceId() async {
    final db = await database;
    final rows = await db.query(
      'app_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['selected_service_id'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['value']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> saveSelectedServiceId(String? id) async {
    final db = await database;
    if (id == null || id.trim().isEmpty) {
      await db.delete(
        'app_state',
        where: 'key = ?',
        whereArgs: ['selected_service_id'],
      );
      return;
    }
    await db.insert(
      'app_state',
      {
        'key': 'selected_service_id',
        'value': id.trim(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> loadLegacySnapshot(String serviceId, String kind) async {
    final db = await database;
    if (!await _tableExists(db, 'catalog_snapshots')) return null;
    try {
      final rows = await db.query(
        'catalog_snapshots',
        columns: ['payload'],
        where: 'service_id = ? AND kind = ?',
        whereArgs: [serviceId, kind],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final raw = rows.first['payload']?.toString();
      if (raw == null || raw.isEmpty) return null;
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> loadLegacySnapshotUpdatedAt(
    String serviceId,
    String kind,
  ) async {
    final db = await database;
    if (!await _tableExists(db, 'catalog_snapshots')) return null;
    try {
      final rows = await db.query(
        'catalog_snapshots',
        columns: ['updated_at'],
        where: 'service_id = ? AND kind = ?',
        whereArgs: [serviceId, kind],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final raw = rows.first['updated_at'];
      final millis = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
      if (millis == null || millis <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteLegacySnapshot(String serviceId, String kind) async {
    final db = await database;
    if (!await _tableExists(db, 'catalog_snapshots')) return;
    try {
      await db.delete(
        'catalog_snapshots',
        where: 'service_id = ? AND kind = ?',
        whereArgs: [serviceId, kind],
      );
    } catch (_) {}
  }

  Future<void> clearServiceCatalogs(String serviceId) async {
    await _catalogFiles.clearService(serviceId);
    final db = await database;
    if (!await _tableExists(db, 'catalog_snapshots')) return;
    try {
      await db.delete(
        'catalog_snapshots',
        where: 'service_id = ?',
        whereArgs: [serviceId],
      );
    } catch (_) {}
  }

  Future<List<Map<String, Object?>>> loadChannelHealthRows() async {
    final db = await database;
    return db.query(
      'channel_health',
      where: 'expires_at > ?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> upsertChannelHealth({
    required String channelKey,
    required String status,
    required String reason,
    required DateTime expiresAt,
  }) async {
    final db = await database;
    await db.insert(
      'channel_health',
      {
        'channel_key': channelKey,
        'status': status,
        'reason': reason,
        'expires_at': expiresAt.millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteChannelHealth(String channelKey) async {
    final db = await database;
    await db.delete(
      'channel_health',
      where: 'channel_key = ?',
      whereArgs: [channelKey],
    );
  }

  Future<void> pruneChannelHealth() async {
    final db = await database;
    await db.delete(
      'channel_health',
      where: 'expires_at <= ?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<Map<String, String?>> loadLogoFallbacks(Set<String> keys) async {
    if (keys.isEmpty) return <String, String?>{};
    final db = await database;
    final output = <String, String?>{};
    final values = keys.toList(growable: false);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var offset = 0; offset < values.length; offset += 400) {
      final end = (offset + 400).clamp(0, values.length);
      final chunk = values.sublist(offset, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT lookup_key, url FROM channel_logo_cache '
        'WHERE expires_at > ? AND lookup_key IN ($placeholders)',
        <Object?>[now, ...chunk],
      );
      for (final row in rows) {
        final key = row['lookup_key']?.toString() ?? '';
        if (key.isEmpty) continue;
        final rawUrl = row['url']?.toString().trim() ?? '';
        output[key] = rawUrl.isEmpty ? null : rawUrl;
      }
    }
    return output;
  }

  Future<void> saveLogoFallbacks(Map<String, String?> values) async {
    if (values.isEmpty) return;
    final db = await database;
    final now = DateTime.now();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in values.entries) {
        final url = entry.value?.trim() ?? '';
        final ttl =
            url.isEmpty ? const Duration(days: 1) : const Duration(days: 30);
        batch.insert(
          'channel_logo_cache',
          {
            'lookup_key': entry.key,
            'url': url,
            'expires_at': now.add(ttl).millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> pruneLogoFallbacks() async {
    final db = await database;
    await db.delete(
      'channel_logo_cache',
      where: 'expires_at <= ?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }
}
