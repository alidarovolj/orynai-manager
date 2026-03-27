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
  Position? get lastPosition => _lastPosition;

  Stream<Position?> get positionStream => _positionController.stream;

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

  Future<void> startTracking() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen(
      (position) {
        _lastPosition = position;
        _positionController.add(position);
        debugPrint(
          '[GPS] Position: ${position.latitude}, ${position.longitude} ±${position.accuracy}m',
        );
      },
      onError: (e) {
        debugPrint('[GPS] Stream error: $e');
        _positionController.add(null);
      },
    );
  }

  Future<Position?> getCurrentPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      _lastPosition = position;
      return position;
    } catch (e) {
      debugPrint('[GPS] Error getting current position: $e');
      return null;
    }
  }

  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void dispose() {
    stopTracking();
    _positionController.close();
  }
}
