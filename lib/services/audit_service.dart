import 'package:flutter/foundation.dart';
import 'local_db_service.dart';
import 'auth_state_manager.dart';
import 'api_service.dart';

/// Действия менеджера, подлежащие аудиту
enum AuditAction {
  openMap,            // открыл карту кладбища
  viewGrave,          // открыл карточку места
  saveGraveRecord,    // сохранил данные захоронения
  fixCoordinates,     // зафиксировал GPS-координаты
  login,              // выполнил вход
}

extension AuditActionName on AuditAction {
  String get value {
    switch (this) {
      case AuditAction.openMap:         return 'open_map';
      case AuditAction.viewGrave:       return 'view_grave';
      case AuditAction.saveGraveRecord: return 'save_grave_record';
      case AuditAction.fixCoordinates:  return 'fix_coordinates';
      case AuditAction.login:           return 'login';
    }
  }
}

class AuditService {
  static final AuditService _instance = AuditService._internal();
  factory AuditService() => _instance;
  AuditService._internal();

  final LocalDbService _db = LocalDbService();
  final ApiService _api = ApiService();

  /// Записывает действие в локальный аудит-журнал.
  /// [entityType] — тип объекта (например, 'grave', 'cemetery')
  /// [entityId]   — ID объекта
  /// [details]    — доп. информация (JSON-строка или текст)
  Future<void> log({
    required AuditAction action,
    String? entityType,
    int? entityId,
    String? details,
  }) async {
    try {
      final phone = AuthStateManager().currentUser?.phone;
      await _db.insertAuditLog(
        action: action.value,
        entityType: entityType,
        entityId: entityId,
        details: details,
        userPhone: phone,
      );
      debugPrint('[Audit] Logged: ${action.value} entity=$entityType/$entityId');
    } catch (e) {
      debugPrint('[Audit] Log error: $e');
    }
  }

  /// Отправляет несинхронизированные записи аудита на сервер.
  Future<void> syncAuditLogs() async {
    try {
      final rows = await _db.getUnsynedAuditLogs();
      if (rows.isEmpty) return;

      final ids = rows.map((r) => r['id'] as int).toList();

      await _api.post(
        '/api/v2/manager/audit-logs',
        body: {
          'logs': rows.map((r) => {
            'action': r['action'],
            'entity_type': r['entity_type'],
            'entity_id': r['entity_id'],
            'details': r['details'],
            'device_source': 'tablet',
            'user_phone': r['user_phone'],
            'performed_at': r['performed_at'],
          }).toList(),
        },
        requiresAuth: true,
      );

      await _db.markAuditLogsSynced(ids);
      debugPrint('[Audit] Synced ${ids.length} audit records');
    } catch (e) {
      debugPrint('[Audit] Sync error: $e');
    }
  }
}
