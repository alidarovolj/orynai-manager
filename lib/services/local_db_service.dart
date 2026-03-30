import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/burial_record.dart';
import '../models/cemetery.dart';
import '../models/grave.dart';
import '../models/sync_item.dart';

class LocalDbService {
  static LocalDbService? _instance;
  factory LocalDbService() => _instance ??= LocalDbService._internal();
  LocalDbService._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'manager.db');

    return openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createBurialRecordsTable(db);
    await _createSyncQueueTable(db);
    await _createCemeteriesTable(db);
    await _createGravesTable(db);
    await _createAuditLogTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createCemeteriesTable(db);
    }
    if (oldVersion < 3) {
      await _createGravesTable(db);
      await _createAuditLogTable(db);
    }
  }

  Future<void> _createBurialRecordsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS burial_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        grave_id INTEGER NOT NULL,
        cemetery_id INTEGER NOT NULL,
        deceased_name TEXT,
        deceased_iin TEXT,
        death_date TEXT,
        burial_date TEXT,
        latitude REAL,
        longitude REAL,
        gps_accuracy REAL,
        gps_fixed_at TEXT,
        notes TEXT,
        sync_status TEXT NOT NULL DEFAULT 'local',
        device_source TEXT NOT NULL DEFAULT 'tablet',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_error TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_burial_records_grave_id ON burial_records(grave_id)',
    );
  }

  Future<void> _createSyncQueueTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        error_message TEXT,
        created_at TEXT NOT NULL,
        processed_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status)',
    );
  }

  Future<void> _createCemeteriesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cemeteries (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        country TEXT,
        city TEXT,
        street_name TEXT,
        name_kz TEXT,
        description_kz TEXT,
        phone TEXT,
        location_coords TEXT NOT NULL,
        polygon_coordinates TEXT NOT NULL,
        religion TEXT,
        burial_price INTEGER DEFAULT 0,
        status TEXT DEFAULT 'active',
        capacity INTEGER DEFAULT 0,
        free_spaces INTEGER DEFAULT 0,
        reserved_spaces INTEGER DEFAULT 0,
        occupied_spaces INTEGER DEFAULT 0,
        fetched_at TEXT
      )
    ''');
  }

  // ─── Burial Records ───────────────────────────────────────────────────────

  Future<int> insertBurialRecord(BurialRecord record) async {
    final db = await database;
    final id = await db.insert(
      'burial_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('[DB] Inserted burial record id=$id for grave=${record.graveId}');
    return id;
  }

  Future<int> updateBurialRecord(BurialRecord record) async {
    final db = await database;
    final count = await db.update(
      'burial_records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
    debugPrint('[DB] Updated burial record id=${record.id}, rows=$count');
    return count;
  }

  Future<BurialRecord?> getBurialRecordByGraveId(int graveId) async {
    final db = await database;
    final rows = await db.query(
      'burial_records',
      where: 'grave_id = ?',
      whereArgs: [graveId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BurialRecord.fromMap(rows.first);
  }

  Future<List<BurialRecord>> getPendingBurialRecords() async {
    final db = await database;
    final rows = await db.query(
      'burial_records',
      where: 'sync_status IN (?, ?)',
      whereArgs: [SyncStatus.local.name, SyncStatus.pending.name],
      orderBy: 'updated_at ASC',
    );
    return rows.map(BurialRecord.fromMap).toList();
  }

  Future<void> markBurialRecordSynced(int id) async {
    final db = await database;
    await db.update(
      'burial_records',
      {
        'sync_status': SyncStatus.synced.name,
        'sync_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markBurialRecordError(int id, String error) async {
    final db = await database;
    await db.update(
      'burial_records',
      {
        'sync_status': SyncStatus.error.name,
        'sync_error': error,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─── Sync Queue ───────────────────────────────────────────────────────────

  Future<int> enqueueSyncItem(SyncItem item) async {
    final db = await database;
    final id = await db.insert('sync_queue', item.toMap());
    debugPrint('[DB] Enqueued sync item id=$id type=${item.entityType.name}');
    return id;
  }

  Future<List<SyncItem>> getPendingSyncItems() async {
    final db = await database;
    final rows = await db.query(
      'sync_queue',
      where: 'status = ? AND attempts < 5',
      whereArgs: [SyncItemStatus.pending.name],
      orderBy: 'created_at ASC',
    );
    return rows.map(SyncItem.fromMap).toList();
  }

  Future<void> updateSyncItem(SyncItem item) async {
    final db = await database;
    await db.update(
      'sync_queue',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> _createGravesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS graves (
        id INTEGER PRIMARY KEY,
        cemetery_id INTEGER NOT NULL,
        cemetery_name TEXT,
        sector_number TEXT,
        row_number TEXT,
        grave_number TEXT,
        status TEXT DEFAULT 'free',
        width INTEGER DEFAULT 0,
        height INTEGER DEFAULT 0,
        polygon_data TEXT NOT NULL,
        cached_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_graves_cemetery ON graves(cemetery_id)',
    );
  }

  Future<void> _createAuditLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        entity_type TEXT,
        entity_id INTEGER,
        details TEXT,
        device_source TEXT NOT NULL DEFAULT 'tablet',
        user_phone TEXT,
        performed_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_synced ON audit_log(synced)',
    );
  }

  // ─── Cemeteries ───────────────────────────────────────────────────────────

  /// Сохраняет список кладбищ (INSERT OR REPLACE).
  Future<void> cacheCemeteries(List<Cemetery> cemeteries) async {
    final db = await database;
    final batch = db.batch();
    for (final c in cemeteries) {
      batch.insert(
        'cemeteries',
        c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    debugPrint('[DB] Cached ${cemeteries.length} cemeteries');
  }

  /// Возвращает кладбища из локального кэша.
  Future<List<Cemetery>> getCachedCemeteries() async {
    final db = await database;
    final rows = await db.query('cemeteries', orderBy: 'name ASC');
    return rows.map(Cemetery.fromDbMap).toList();
  }

  /// Дата последнего обновления кэша кладбищ.
  Future<DateTime?> getCemeteriesCachedAt() async {
    final db = await database;
    final rows = await db.query(
      'cemeteries',
      columns: ['fetched_at'],
      orderBy: 'fetched_at DESC',
      limit: 1,
    );
    if (rows.isEmpty || rows.first['fetched_at'] == null) return null;
    return DateTime.tryParse(rows.first['fetched_at'] as String);
  }

  // ─── Graves ───────────────────────────────────────────────────────────────

  Future<void> cacheGraves(int cemeteryId, List<Grave> graves) async {
    final db = await database;
    final batch = db.batch();
    // Удаляем старый кэш этого кладбища
    batch.delete('graves', where: 'cemetery_id = ?', whereArgs: [cemeteryId]);
    for (final g in graves) {
      batch.insert('graves', g.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    debugPrint('[DB] Cached ${graves.length} graves for cemetery $cemeteryId');
  }

  Future<List<Grave>> getCachedGraves(int cemeteryId) async {
    final db = await database;
    final rows = await db.query(
      'graves',
      where: 'cemetery_id = ?',
      whereArgs: [cemeteryId],
    );
    return rows.map(Grave.fromDbMap).toList();
  }

  // ─── Audit Log ────────────────────────────────────────────────────────────

  Future<void> insertAuditLog({
    required String action,
    String? entityType,
    int? entityId,
    String? details,
    String? userPhone,
  }) async {
    final db = await database;
    await db.insert('audit_log', {
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'details': details,
      'device_source': 'tablet',
      'user_phone': userPhone,
      'performed_at': DateTime.now().toIso8601String(),
      'synced': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getUnsynedAuditLogs() async {
    final db = await database;
    return db.query('audit_log', where: 'synced = 0', orderBy: 'performed_at ASC');
  }

  Future<void> markAuditLogsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.update(
      'audit_log',
      {'synced': 1},
      where: 'id IN (${ids.map((_) => '?').join(',')})',
      whereArgs: ids,
    );
  }

  // ─── Close ────────────────────────────────────────────────────────────────

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
