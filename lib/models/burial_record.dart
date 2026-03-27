import 'dart:convert';

enum SyncStatus { local, pending, synced, error }

class BurialRecord {
  final int? id;
  final int graveId;
  final int cemeteryId;
  final String? deceasedName;
  final String? deceasedIin;
  final String? deathDate;
  final String? burialDate;
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracy;
  final DateTime? gpsFixedAt;
  final String? notes;
  final SyncStatus syncStatus;
  final String deviceSource;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? syncError;

  BurialRecord({
    this.id,
    required this.graveId,
    required this.cemeteryId,
    this.deceasedName,
    this.deceasedIin,
    this.deathDate,
    this.burialDate,
    this.latitude,
    this.longitude,
    this.gpsAccuracy,
    this.gpsFixedAt,
    this.notes,
    this.syncStatus = SyncStatus.local,
    this.deviceSource = 'tablet',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncError,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  BurialRecord copyWith({
    int? id,
    int? graveId,
    int? cemeteryId,
    String? deceasedName,
    String? deceasedIin,
    String? deathDate,
    String? burialDate,
    double? latitude,
    double? longitude,
    double? gpsAccuracy,
    DateTime? gpsFixedAt,
    String? notes,
    SyncStatus? syncStatus,
    String? deviceSource,
    DateTime? updatedAt,
    String? syncError,
  }) {
    return BurialRecord(
      id: id ?? this.id,
      graveId: graveId ?? this.graveId,
      cemeteryId: cemeteryId ?? this.cemeteryId,
      deceasedName: deceasedName ?? this.deceasedName,
      deceasedIin: deceasedIin ?? this.deceasedIin,
      deathDate: deathDate ?? this.deathDate,
      burialDate: burialDate ?? this.burialDate,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      gpsFixedAt: gpsFixedAt ?? this.gpsFixedAt,
      notes: notes ?? this.notes,
      syncStatus: syncStatus ?? this.syncStatus,
      deviceSource: deviceSource ?? this.deviceSource,
      createdAt: this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      syncError: syncError ?? this.syncError,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'grave_id': graveId,
      'cemetery_id': cemeteryId,
      'deceased_name': deceasedName,
      'deceased_iin': deceasedIin,
      'death_date': deathDate,
      'burial_date': burialDate,
      'latitude': latitude,
      'longitude': longitude,
      'gps_accuracy': gpsAccuracy,
      'gps_fixed_at': gpsFixedAt?.toIso8601String(),
      'notes': notes,
      'sync_status': syncStatus.name,
      'device_source': deviceSource,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_error': syncError,
    };
  }

  factory BurialRecord.fromMap(Map<String, dynamic> map) {
    return BurialRecord(
      id: map['id'] as int?,
      graveId: map['grave_id'] as int,
      cemeteryId: map['cemetery_id'] as int,
      deceasedName: map['deceased_name'] as String?,
      deceasedIin: map['deceased_iin'] as String?,
      deathDate: map['death_date'] as String?,
      burialDate: map['burial_date'] as String?,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      gpsAccuracy: map['gps_accuracy'] as double?,
      gpsFixedAt: map['gps_fixed_at'] != null
          ? DateTime.tryParse(map['gps_fixed_at'] as String)
          : null,
      notes: map['notes'] as String?,
      syncStatus: SyncStatus.values.firstWhere(
        (e) => e.name == map['sync_status'],
        orElse: () => SyncStatus.local,
      ),
      deviceSource: map['device_source'] as String? ?? 'tablet',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncError: map['sync_error'] as String?,
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'grave_id': graveId,
      'cemetery_id': cemeteryId,
      'deceased_name': deceasedName,
      'deceased_iin': deceasedIin,
      'death_date': deathDate,
      'burial_date': burialDate,
      'latitude': latitude,
      'longitude': longitude,
      'gps_accuracy': gpsAccuracy,
      'gps_fixed_at': gpsFixedAt?.toIso8601String(),
      'notes': notes,
      'device_source': deviceSource,
    };
  }

  String get syncStatusLabel {
    switch (syncStatus) {
      case SyncStatus.local:
        return 'Сохранено локально';
      case SyncStatus.pending:
        return 'Ожидает синхронизации';
      case SyncStatus.synced:
        return 'Синхронизировано';
      case SyncStatus.error:
        return 'Ошибка синхронизации';
    }
  }

  bool get hasGps => latitude != null && longitude != null;

  @override
  String toString() => jsonEncode(toMap());
}
