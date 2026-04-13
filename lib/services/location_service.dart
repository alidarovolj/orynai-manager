import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static LocationService? _instance;
  factory LocationService() => _instance ??= LocationService._internal();
  LocationService._internal();

  StreamSubscription<Position>? _positionSubscription;
  final StreamController<Position?> _positionController =
      StreamController<Position?>.broadcast();

  Position? _lastPosition;
  DateTime? _lastPositionTime;
  bool _isTracking = false;

  Position? get lastPosition => _lastPosition;
  bool get isTracking => _isTracking;

  Stream<Position?> get positionStream => _positionController.stream;

  /// Позиция считается свежей, если получена не позднее 5 секунд назад.
  static const _freshDuration = Duration(seconds: 5);

  bool get _isPositionFresh =>
      _lastPosition != null &&
      _lastPositionTime != null &&
      DateTime.now().difference(_lastPositionTime!) < _freshDuration;

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[GPS] Location services are disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('[GPS] Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('[GPS] Location permission denied forever');
      return false;
    }

    return true;
  }

  /// Запускает непрерывное отслеживание позиции.
  /// Использует forceLocationManager=true для прямого доступа к GNSS-чипу
  /// и поддержки mock location от внешних GNSS-модулей (Bluetooth/USB).
  Future<void> startTracking() async {
    if (_isTracking) return;

    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    _isTracking = true;
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        // true = LocationManager.GPS_PROVIDER — прямой доступ к GNSS-чипу
        // и принимает mock location от внешних GNSS-приёмников.
        // FusedLocationProvider (false) в Android 12+ игнорирует mock locations.
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 1),
      ),
    ).listen(
      (position) {
        _lastPosition = position;
        _lastPositionTime = DateTime.now();
        _positionController.add(position);
        debugPrint(
          '[GPS] ${position.latitude.toStringAsFixed(7)}, '
          '${position.longitude.toStringAsFixed(7)} '
          '±${position.accuracy.toStringAsFixed(1)}m',
        );
      },
      onError: (e) {
        debugPrint('[GPS] Stream error: $e');
        _positionController.add(null);
      },
      cancelOnError: false,
    );
  }

  /// Возвращает текущую позицию.
  ///
  /// Порядок:
  /// 1. Если есть свежая кешированная позиция (< 5 с) — возвращает её сразу.
  /// 2. Запускает непрерывное отслеживание (если не запущено).
  /// 3. Если уже есть любая позиция — возвращает её.
  /// 4. Ждёт первую позицию из потока с таймаутом 60 с (для GNSS cold start).
  Future<Position?> getCurrentPosition() async {
    if (_isPositionFresh) return _lastPosition;

    await startTracking();
    if (!_isTracking) return null;

    if (_lastPosition != null) return _lastPosition;

    try {
      final pos = await positionStream
          .where((p) => p != null)
          .cast<Position>()
          .first
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              debugPrint('[GPS] Timeout: GNSS cold start > 60s');
              throw TimeoutException('GNSS cold start timeout');
            },
          );
      return pos;
    } on TimeoutException {
      debugPrint('[GPS] Returning last known position after timeout');
      return _lastPosition;
    } catch (e) {
      debugPrint('[GPS] Error waiting for position: $e');
      return _lastPosition;
    }
  }

  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
  }

  void dispose() {
    stopTracking();
    _positionController.close();
  }
}
