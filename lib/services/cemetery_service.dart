import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'local_db_service.dart';
import '../models/cemetery.dart';
import '../models/grave.dart';

class CemeteryService {
  final ApiService _apiService = ApiService();
  final LocalDbService _db = LocalDbService();

  static const String _cemeteriesUrl = 'https://orynai.kz/api/v1/cemeteries';

  // ─── Кладбища ─────────────────────────────────────────────────────────────

  /// Возвращает кладбища из локального кэша (мгновенно).
  /// Может вернуть пустой список, если кэш пуст.
  Future<List<Cemetery>> getCachedCemeteries() async {
    return _db.getCachedCemeteries();
  }

  /// Дата последнего обновления кэша.
  Future<DateTime?> getCemeteriesCachedAt() => _db.getCemeteriesCachedAt();

  /// Загружает свежие данные с сервера и обновляет кэш.
  /// Возвращает список кладбищ при успехе.
  /// Бросает исключение при ошибке сети.
  Future<List<Cemetery>> fetchCemeteriesFromNetwork() async {
    final result = await _apiService.get(_cemeteriesUrl);

    if (result is Map<String, dynamic> && result['data'] != null) {
      final List<dynamic> raw = result['data'];
      final cemeteries = raw.map((j) => Cemetery.fromJson(j as Map<String, dynamic>)).toList();
      await _db.cacheCemeteries(cemeteries);
      debugPrint('[CemeteryService] Fetched & cached ${cemeteries.length} cemeteries');
      return cemeteries;
    }
    throw Exception('Неверный формат ответа сервера');
  }

  // ─── Могилы ───────────────────────────────────────────────────────────────

  Future<List<Grave>> getGravesByCoordinates({
    required int cemeteryId,
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
  }) async {
    final result = await _apiService.get(
      'https://orynai.kz/api/v1/graves/by-coordinates',
      queryParameters: {
        'min_x': minX.toString(),
        'max_x': maxX.toString(),
        'min_y': minY.toString(),
        'max_y': maxY.toString(),
        'cemetery_id': cemeteryId.toString(),
      },
    );

    if (result is List) {
      return result
          .map((j) => Grave.fromJson(j as Map<String, dynamic>))
          .toList();
    } else if (result is Map<String, dynamic> && result['data'] != null) {
      return (result['data'] as List)
          .map((j) => Grave.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Неверный формат ответа для могил');
  }
}
