enum SyncItemStatus { pending, processing, done, error }

enum SyncEntityType { burialRecord, graveCoordinates }

class SyncItem {
  final int? id;
  final SyncEntityType entityType;
  final int entityId;
  final String action;
  final String payload;
  final SyncItemStatus status;
  final int attempts;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? processedAt;

  SyncItem({
    this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.payload,
    this.status = SyncItemStatus.pending,
    this.attempts = 0,
    this.errorMessage,
    DateTime? createdAt,
    this.processedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  SyncItem copyWith({
    int? id,
    SyncItemStatus? status,
    int? attempts,
    String? errorMessage,
    DateTime? processedAt,
  }) {
    return SyncItem(
      id: id ?? this.id,
      entityType: entityType,
      entityId: entityId,
      action: action,
      payload: payload,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt,
      processedAt: processedAt ?? this.processedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'entity_type': entityType.name,
      'entity_id': entityId,
      'action': action,
      'payload': payload,
      'status': status.name,
      'attempts': attempts,
      'error_message': errorMessage,
      'created_at': createdAt.toIso8601String(),
      'processed_at': processedAt?.toIso8601String(),
    };
  }

  factory SyncItem.fromMap(Map<String, dynamic> map) {
    return SyncItem(
      id: map['id'] as int?,
      entityType: SyncEntityType.values.firstWhere(
        (e) => e.name == map['entity_type'],
        orElse: () => SyncEntityType.burialRecord,
      ),
      entityId: map['entity_id'] as int,
      action: map['action'] as String,
      payload: map['payload'] as String,
      status: SyncItemStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => SyncItemStatus.pending,
      ),
      attempts: map['attempts'] as int? ?? 0,
      errorMessage: map['error_message'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      processedAt: map['processed_at'] != null
          ? DateTime.tryParse(map['processed_at'] as String)
          : null,
    );
  }
}
