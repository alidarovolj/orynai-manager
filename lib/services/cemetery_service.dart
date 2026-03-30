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

  /// Загружает могилы: сначала пробует сеть, при ошибке возвращает кэш.
  /// При успешной загрузке с сети — обновляет кэш.
  Future<List<Grave>> getGravesByCoordinates({
    required int cemeteryId,
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
  }) async {
    try {
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

      List<Grave> graves;
      if (result is List) {
        graves = result
            .map((j) => Grave.fromJson(j as Map<String, dynamic>))
            .toList();
      } else if (result is Map<String, dynamic> && result['data'] != null) {
        graves = (result['data'] as List)
            .map((j) => Grave.fromJson(j as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Неверный формат ответа для могил');
      }

      // Кэшируем полученные могилы
      await _db.cacheGraves(cemeteryId, graves);
      return graves;
    } catch (e) {
      debugPrint('[CemeteryService] Network error loading graves: $e');
      // Возвращаем кэш при ошибке сети
      final cached = await _db.getCachedGraves(cemeteryId);
      if (cached.isNotEmpty) {
        debugPrint('[CemeteryService] Returning ${cached.length} cached graves');
        return cached;
      }
      rethrow;
    }
  }

  /// Возвращает только кэшированные могилы (без сетевого запроса).
  Future<List<Grave>> getCachedGraves(int cemeteryId) =>
      _db.getCachedGraves(cemeteryId);
}
