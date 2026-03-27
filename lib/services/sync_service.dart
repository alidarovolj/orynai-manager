import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/burial_record.dart';
import 'api_service.dart';
import 'local_db_service.dart';

class SyncService {
  static SyncService? _instance;
  factory SyncService() => _instance ??= SyncService._internal();
  SyncService._internal();

  final LocalDbService _db = LocalDbService();
  final ApiService _api = ApiService();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isSyncing = false;

  final StreamController<SyncStatus?> _statusController =
      StreamController<SyncStatus?>.broadcast();

  Stream<SyncStatus?> get syncStatusStream => _statusController.stream;

  void start() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);

    _checkAndSync();
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasNetwork = results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet,
    );
    if (hasNetwork) {
      debugPrint('[Sync] Network available, starting sync');
      _checkAndSync();
    }
  }

  Future<void> _checkAndSync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final pending = await _db.getPendingBurialRecords();
      debugPrint('[Sync] Found ${pending.length} pending records');

      for (final record in pending) {
        await _syncBurialRecord(record);
      }
    } catch (e) {
      debugPrint('[Sync] Error during sync: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncBurialRecord(BurialRecord record) async {
    if (record.id == null) return;

    try {
      await _api.post(
        '/api/v2/manager/burial-records',
        body: record.toApiJson(),
        requiresAuth: true,
      );

      await _db.markBurialRecordSynced(record.id!);
      _statusController.add(SyncStatus.synced);
      debugPrint('[Sync] Synced burial record id=${record.id}');
    } catch (e) {
      await _db.markBurialRecordError(record.id!, e.toString());
      _statusController.add(SyncStatus.error);
      debugPrint('[Sync] Failed to sync record id=${record.id}: $e');
    }
  }

  Future<void> syncNow() async {
    await _checkAndSync();
  }

  Future<bool> isNetworkAvailable() async {
    final results = await Connectivity().checkConnectivity();
    return results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet,
    );
  }

  Future<BurialRecord> saveBurialRecord(BurialRecord record) async {
    final hasNetwork = await isNetworkAvailable();
    final status = hasNetwork ? SyncStatus.pending : SyncStatus.local;
    final toSave = record.copyWith(syncStatus: status);

    int id;
    if (toSave.id != null) {
      await _db.updateBurialRecord(toSave);
      id = toSave.id!;
    } else {
      id = await _db.insertBurialRecord(toSave);
    }

    final saved = toSave.copyWith(id: id);

    if (hasNetwork) {
      unawaited(_syncBurialRecord(saved));
    }

    return saved;
  }

  void stop() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  void dispose() {
    stop();
    _statusController.close();
  }
}

void unawaited(Future<void> future) {
  future.catchError((e) => debugPrint('[Sync] Unawaited error: $e'));
}
