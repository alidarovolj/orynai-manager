import 'dart:async';

import 'package:flutter/material.dart' hide Icon, TextStyle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants.dart';
import '../models/cemetery.dart';
import '../models/grave.dart';
import '../services/cemetery_service.dart';

// Alias для Flutter виджетов
import 'package:flutter/material.dart' as flutter;

class CemeteryDetailsModal extends StatefulWidget {
  final Cemetery cemetery;

  const CemeteryDetailsModal({super.key, required this.cemetery});

  @override
  State<CemeteryDetailsModal> createState() => _CemeteryDetailsModalState();
}

class _CemeteryDetailsModalState extends State<CemeteryDetailsModal> {
  final CemeteryService _cemeteryService = CemeteryService();
  YandexMapController? _mapController;
  List<Grave> _graves = [];
  bool _isLoadingGraves = true;
  bool _isMapKitInitialized = false;
  Grave? _selectedGrave; // Выбранное место
  final Map<int, PolygonMapObject> _gravePolygons = {}; // ID могилы -> Polygon
  PolylineMapObject? _routePolyline; // Маршрут на карте
  bool _isBuildingRoute = false;

  /// Максимальная доля экрана для нижней панели (по высоте контента, не больше этого).
  static const double _sheetMaxFraction = 0.70;
  static const double _sheetMaxFractionRoute = 0.40;

  @override
  void initState() {
    super.initState();
    _initializeMapKit();
    _loadGraves();
  }

  // Инициализация Yandex MapKit только при открытии модального окна
  Future<void> _initializeMapKit() async {
    if (_isMapKitInitialized) return;

    try {
      // Новый API не требует явной инициализации через initMapkit
      // API ключ задается в нативном коде (AppDelegate для iOS, Application для Android)
      debugPrint('Yandex MapKit готов к использованию');
      setState(() {
        _isMapKitInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing Yandex MapKit: $e');
      setState(() {
        _isMapKitInitialized = true;
      });
    }
  }

  Future<void> _loadGraves() async {
    try {
      debugPrint('Cemetery ID: ${widget.cemetery.id}');
      debugPrint('Cemetery location: ${widget.cemetery.locationCoords}');

      // locationCoords от API: [latitude, longitude]
      final lat = widget.cemetery.locationCoords[0];
      final lon = widget.cemetery.locationCoords[1];

      // API ожидает: min_x/max_x = longitude, min_y/max_y = latitude
      // Расширяем границы на ~200 метров (~0.002 градуса)
      final minX = lon - 0.002; // longitude min
      final maxX = lon + 0.002; // longitude max
      final minY = lat - 0.002; // latitude min
      final maxY = lat + 0.002; // latitude max

      debugPrint(
        'Loading graves with bounds: minX=$minX, maxX=$maxX, minY=$minY, maxY=$maxY',
      );

      final graves = await _cemeteryService.getGravesByCoordinates(
        cemeteryId: widget.cemetery.id,
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
      );

      debugPrint('Loaded ${graves.length} graves');

      setState(() {
        _graves = graves;
        _isLoadingGraves = false;
      });

      // Обновляем объекты на карте после загрузки
      _updateMapObjects();

      // Повторно центрируем карту после обновления (на iOS позиция может сброситься при setState)
      if (mounted && _mapController != null) {
        final (lat, lon) = _getCemeteryCenter();
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || _mapController == null) return;
          await _mapController!.moveCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: Point(latitude: lat, longitude: lon),
                zoom: 18.0,
              ),
            ),
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading graves: $e');
      setState(() => _isLoadingGraves = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: flutter.Text(
              'booking.details.loadingGraves'.tr(
                namedArgs: {'error': e.toString()},
              ),
            ),
          ),
        );
      }
    }
  }

  // Метод для добавления объектов на карту (новый API yandex_mapkit)
  Future<void> _updateMapObjects() async {
    if (_mapController == null) return;

    _gravePolygons.clear(); // Очищаем старые полигоны

    debugPrint('Adding ${_graves.length} graves to map');

    final polygons = <PolygonMapObject>[];

    for (var grave in _graves) {
      if (grave.polygonData.coordinates.isNotEmpty) {
        // Определяем цвет
        flutter.Color fillColor;
        if (grave.isFree) {
          fillColor = flutter.Colors.green.withAlpha(180);
        } else if (grave.isReserved) {
          fillColor = flutter.Colors.orange.withAlpha(180);
        } else {
          fillColor = flutter.Colors.grey.withAlpha(180);
        }

        // Создаем полигон с новым API
        final polygon = PolygonMapObject(
          mapId: MapObjectId('grave_${grave.id}'),
          polygon: Polygon(
            outerRing: LinearRing(
              points: grave.polygonData.coordinates
                  .map(
                    (coord) => Point(latitude: coord[1], longitude: coord[0]),
                  )
                  .toList(),
            ),
            innerRings: [],
          ),
          strokeColor: flutter.Colors.black,
          strokeWidth: 2.0,
          fillColor: fillColor,
          onTap: (PolygonMapObject self, Point point) {
            debugPrint(
              'Grave tapped: ${grave.id}, sector: ${grave.sectorNumber}, row: ${grave.rowNumber}',
            );
            _onGraveTap(grave);
          },
        );

        polygons.add(polygon);
        _gravePolygons[grave.id] = polygon;
      }
    }

    // Обновляем карту с новыми полигонами
    if (mounted) {
      setState(() {});
    }
  }

  // Обработка нажатия на могилу
  void _onGraveTap(Grave grave) {
    setState(() {
      _routePolyline = null;
      // Сбрасываем выделение предыдущего места
      if (_selectedGrave != null &&
          _gravePolygons.containsKey(_selectedGrave!.id)) {
        final prevPolygon = _gravePolygons[_selectedGrave!.id]!;
        _gravePolygons[_selectedGrave!.id] = prevPolygon.copyWith(
          strokeColor: flutter.Colors.black,
          strokeWidth: 2.0,
        );
      }

      // Выделяем новое место красной рамкой
      _selectedGrave = grave;
      if (_gravePolygons.containsKey(grave.id)) {
        final currentPolygon = _gravePolygons[grave.id]!;
        _gravePolygons[grave.id] = currentPolygon.copyWith(
          strokeColor: flutter.Colors.red,
          strokeWidth: 4.0,
        );
      }
    });
  }

  /// Центр полигона могилы (среднее по координатам)
  Point _getGraveCenter(Grave grave) {
    if (grave.polygonData.coordinates.isEmpty) {
      final lat = widget.cemetery.locationCoords[0];
      final lon = widget.cemetery.locationCoords[1];
      return Point(latitude: lat, longitude: lon);
    }
    double sumLat = 0, sumLon = 0;
    final coords = grave.polygonData.coordinates;
    for (final c in coords) {
      sumLon += c[0];
      sumLat += c[1];
    }
    return Point(
      latitude: sumLat / coords.length,
      longitude: sumLon / coords.length,
    );
  }

  Future<Point?> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: flutter.Text('booking.details.locationDisabled'.tr()),
          ),
        );
      }
      return null;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: flutter.Text('booking.details.locationDenied'.tr()),
          ),
        );
      }
      return null;
    }
    try {
      final pos =
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 15),
            ),
          ).timeout(
            const Duration(seconds: 18),
            onTimeout: () => throw TimeoutException('Location timeout'),
          );
      return Point(latitude: pos.latitude, longitude: pos.longitude);
    } on TimeoutException {
      debugPrint('Geolocator timeout');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: flutter.Text('booking.details.routeError'.tr())),
        );
      }
      return null;
    } catch (e) {
      debugPrint('Geolocator error: $e');
      return null;
    }
  }

  /// Открывает маршрут до места в Apple Картах (fallback при ошибке в приложении).
  void _openInAppleMaps(Point destination) {
    final url = Uri.parse(
      'https://maps.apple.com/?daddr=${destination.latitude},${destination.longitude}&dirflg=d',
    );
    launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// Показывает SnackBar об ошибке маршрута с кнопкой «Открыть в Картах».
  void _showRouteErrorSnackBar(Point destination) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: flutter.Text('booking.details.routeErrorWithFallback'.tr()),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'booking.details.openInMaps'.tr(),
          onPressed: () => _openInAppleMaps(destination),
        ),
      ),
    );
  }

  /// Строит маршрут от текущего местоположения до выбранного места и рисует его на карте Yandex MapKit.
  /// При таймауте или ошибке предлагает открыть маршрут в Apple Картах.
  Future<void> _buildRoute() async {
    if (_selectedGrave == null) return;
    final destination = _getGraveCenter(_selectedGrave!);
    setState(() => _isBuildingRoute = true);
    try {
      await Future(() async {
        final current = await _getCurrentLocation();
        if (current == null || !mounted) throw Exception('Location failed');

        final (session, resultFuture) = await YandexDriving.requestRoutes(
          points: [
            RequestPoint(
              point: current,
              requestPointType: RequestPointType.wayPoint,
            ),
            RequestPoint(
              point: destination,
              requestPointType: RequestPointType.wayPoint,
            ),
          ],
          drivingOptions: const DrivingOptions(
            initialAzimuth: 0,
            routesCount: 1,
            avoidanceFlags: DrivingAvoidanceFlags(),
          ),
        );

        final result = await resultFuture.timeout(
          const Duration(seconds: 18),
          onTimeout: () => throw TimeoutException('Route request timeout'),
        );
        await session.close();

        if (!mounted) return;
        if (result.error != null) throw Exception(result.error);
        if (result.routes == null || result.routes!.isEmpty) {
          throw Exception('No routes');
        }

        final route = result.routes!.first;
        setState(() {
          _routePolyline = PolylineMapObject(
            mapId: const MapObjectId('route_polyline'),
            polyline: route.geometry,
            strokeColor: AppColors.buttonBackground,
            strokeWidth: 5.0,
          );
        });

        if (_mapController != null && route.geometry.points.isNotEmpty) {
          final points = route.geometry.points;
          double minLat = points.first.latitude, maxLat = minLat;
          double minLon = points.first.longitude, maxLon = minLon;
          for (final p in points) {
            if (p.latitude < minLat) minLat = p.latitude;
            if (p.latitude > maxLat) maxLat = p.latitude;
            if (p.longitude < minLon) minLon = p.longitude;
            if (p.longitude > maxLon) maxLon = p.longitude;
          }
          final centerLat = (minLat + maxLat) / 2;
          final centerLon = (minLon + maxLon) / 2;
          await _mapController!.moveCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: Point(latitude: centerLat, longitude: centerLon),
                zoom: 14.0,
              ),
            ),
          );
        }
      }).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException('Route timeout'),
      );
    } on TimeoutException catch (_) {
      if (mounted) {
        _showRouteErrorSnackBar(destination);
      }
    } catch (e) {
      debugPrint('Route build error: $e');
      if (mounted) {
        _showRouteErrorSnackBar(destination);
      }
    } finally {
      if (mounted) {
        setState(() => _isBuildingRoute = false);
      }
    }
  }

  flutter.Widget _buildSelectedGraveInfo() {
    if (_selectedGrave == null) return const flutter.SizedBox.shrink();

    final grave = _selectedGrave!;

    return flutter.Container(
      margin: const flutter.EdgeInsets.only(bottom: 10),
      padding: const flutter.EdgeInsets.all(12),
      decoration: flutter.BoxDecoration(
        color: const flutter.Color.fromRGBO(244, 240, 231, 1),
        borderRadius: flutter.BorderRadius.circular(10),
        border: flutter.Border.all(color: AppColors.buttonBackground, width: 2),
      ),
      child: flutter.Column(
        crossAxisAlignment: flutter.CrossAxisAlignment.start,
        children: [
          flutter.Row(
            mainAxisAlignment: flutter.MainAxisAlignment.spaceBetween,
            children: [
              flutter.Text(
                'booking.details.selectedPlace'.tr(),
                style: flutter.TextStyle(
                  fontSize: 15,
                  fontWeight: flutter.FontWeight.w600,
                  color: AppColors.iconAndText,
                ),
              ),
              flutter.IconButton(
                icon: const flutter.Icon(flutter.Icons.close, size: 20),
                onPressed: () {
                  setState(() {
                    _routePolyline = null;
                    // Сбрасываем выделение на карте
                    if (_selectedGrave != null &&
                        _gravePolygons.containsKey(_selectedGrave!.id)) {
                      final polygon = _gravePolygons[_selectedGrave!.id]!;
                      _gravePolygons[_selectedGrave!.id] = polygon.copyWith(
                        strokeColor: flutter.Colors.black,
                        strokeWidth: 2.0,
                      );
                    }
                    _selectedGrave = null;
                  });
                },
                padding: flutter.EdgeInsets.zero,
                constraints: const flutter.BoxConstraints(),
              ),
            ],
          ),
          const flutter.SizedBox(height: 12),
          flutter.Row(
            children: [
              flutter.Expanded(
                child: flutter.Text(
                  'booking.details.sector'.tr(
                    namedArgs: {'sector': grave.sectorNumber},
                  ),
                  style: const flutter.TextStyle(
                    fontSize: 14,
                    color: AppColors.iconAndText,
                  ),
                ),
              ),
              flutter.Expanded(
                child: flutter.Text(
                  'booking.details.place'.tr(
                    namedArgs: {'place': grave.graveNumber},
                  ),
                  style: const flutter.TextStyle(
                    fontSize: 14,
                    color: AppColors.iconAndText,
                  ),
                ),
              ),
            ],
          ),
          const flutter.SizedBox(height: 8),
          flutter.Row(
            children: [
              flutter.Container(
                width: 12,
                height: 12,
                decoration: flutter.BoxDecoration(
                  color: grave.isFree
                      ? flutter.Colors.green
                      : grave.isReserved
                      ? flutter.Colors.orange
                      : flutter.Colors.grey,
                  shape: flutter.BoxShape.circle,
                ),
              ),
              const flutter.SizedBox(width: 8),
              flutter.Text(
                'booking.details.status'.tr(
                  namedArgs: {'status': _getStatusText(grave.status)},
                ),
                style: const flutter.TextStyle(
                  fontSize: 14,
                  color: AppColors.iconAndText,
                ),
              ),
            ],
          ),
          const flutter.SizedBox(height: 12),
          // Кнопка «Проложить маршрут»
          flutter.SizedBox(
            width: double.infinity,
            height: 44,
            child: flutter.OutlinedButton.icon(
              onPressed: _isBuildingRoute ? null : () => _buildRoute(),
              icon: _isBuildingRoute
                  ? const flutter.SizedBox(
                      width: 20,
                      height: 20,
                      child: flutter.CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const flutter.Icon(flutter.Icons.directions, size: 20),
              label: flutter.Text(
                _isBuildingRoute ? '...' : 'booking.details.buildRoute'.tr(),
                style: const flutter.TextStyle(fontSize: 14),
              ),
              style: flutter.OutlinedButton.styleFrom(
                foregroundColor: AppColors.buttonBackground,
                side: const flutter.BorderSide(
                  color: AppColors.buttonBackground,
                ),
                shape: flutter.RoundedRectangleBorder(
                  borderRadius: flutter.BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'free':
        return 'booking.details.statusFree'.tr();
      case 'reserved':
        return 'booking.details.statusReserved'.tr();
      case 'occupied':
        return 'booking.details.statusOccupied'.tr();
      default:
        return status;
    }
  }

  String _getReligionIconPath() {
    return widget.cemetery.religion == 'Ислам'
        ? 'assets/icons/religions/003-islam.svg'
        : 'assets/icons/religions/christianity.svg';
  }

  /// Центр кладбища: из полигона (GeoJSON [lon, lat]) или location_coords [lat, lon].
  (double lat, double lon) _getCemeteryCenter() {
    final poly = widget.cemetery.polygonCoordinates;
    if (poly.isNotEmpty) {
      double sumLon = 0, sumLat = 0;
      for (final c in poly) {
        if (c.length >= 2) {
          sumLon += c[0];
          sumLat += c[1];
        }
      }
      final n = poly.length;
      if (n > 0) return (sumLat / n, sumLon / n);
    }
    final coords = widget.cemetery.locationCoords;
    if (coords.length >= 2) return (coords[0], coords[1]);
    return (43.25, 76.95); // fallback Алматы
  }

  @override
  flutter.Widget build(flutter.BuildContext context) {
    return flutter.Scaffold(
      backgroundColor: flutter.Colors.white,
      body: flutter.SafeArea(
        top: false,
        bottom: false,
        child: flutter.Stack(
          children: [
            // Карта на весь экран (показываем только после инициализации MapKit)
            if (_isMapKitInitialized)
              YandexMap(
                cameraBounds: const CameraBounds(minZoom: 10, maxZoom: 22),
                onMapCreated: (YandexMapController controller) async {
                  _mapController = controller;
                  final (lat, lon) = _getCemeteryCenter();

                  debugPrint(
                    'Map created (New SDK). Moving to: lat=$lat, lon=$lon',
                  );
                  debugPrint('Graves loaded: ${_graves.length}');

                  // Сразу перемещаем камеру на центр кладбища (зум 22 — макс. по API Яндекса)
                  await _mapController!.moveCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: Point(latitude: lat, longitude: lon),
                        zoom: 22.0,
                      ),
                    ),
                  );

                  // Если могилы уже загрузились к этому моменту
                  if (!_isLoadingGraves) {
                    _updateMapObjects();
                  }

                  // Показываем иконку текущего местоположения пользователя на карте
                  try {
                    await _mapController!.toggleUserLayer(
                      visible: true,
                      headingEnabled: false,
                      autoZoomEnabled: false,
                    );
                  } catch (e) {
                    debugPrint('User location layer: $e');
                  }
                },
                mapObjects: [
                  ..._gravePolygons.values,
                  if (_routePolyline != null) _routePolyline!,
                ],
              ),

            // Индикатор загрузки MapKit или могил
            if (!_isMapKitInitialized || _isLoadingGraves)
              flutter.Center(
                child: flutter.Column(
                  mainAxisSize: flutter.MainAxisSize.min,
                  children: [
                    const flutter.CircularProgressIndicator(
                      valueColor: flutter.AlwaysStoppedAnimation<flutter.Color>(
                        AppColors.buttonBackground,
                      ),
                    ),
                    const flutter.SizedBox(height: 16),
                    flutter.Text(
                      !_isMapKitInitialized
                          ? 'booking.details.mapInitializing'.tr()
                          : 'booking.details.loadingPlaces'.tr(),
                      style: const flutter.TextStyle(
                        fontSize: 14,
                        color: AppColors.iconAndText,
                      ),
                    ),
                  ],
                ),
              ),

            // Кнопка закрытия
            flutter.Positioned(
              top: 56,
              right: 16,
              child: flutter.Container(
                decoration: flutter.BoxDecoration(
                  color: flutter.Colors.white,
                  shape: flutter.BoxShape.circle,
                  boxShadow: [
                    flutter.BoxShadow(
                      color: flutter.Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: flutter.IconButton(
                  icon: const flutter.Icon(flutter.Icons.close),
                  onPressed: () => flutter.Navigator.pop(context),
                ),
              ),
            ),

            // Нижняя панель: высота по контенту (не более 70% экрана; при маршруте — 40%)
            flutter.Positioned(
              left: 0,
              right: 0,
              bottom: -40,
              child: flutter.SafeArea(
                top: false,
                child: flutter.AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: flutter.Curves.easeOut,
                  constraints: flutter.BoxConstraints(
                    maxHeight:
                        MediaQuery.of(context).size.height *
                        (_isBuildingRoute
                            ? _sheetMaxFractionRoute
                            : _sheetMaxFraction),
                  ),
                  child: flutter.Container(
                    decoration: flutter.BoxDecoration(
                      color: flutter.Colors.white,
                      borderRadius: const flutter.BorderRadius.only(
                        topLeft: flutter.Radius.circular(16),
                        topRight: flutter.Radius.circular(16),
                      ),
                      boxShadow: [
                        // Тень только сверху (верхний край модалки)
                        flutter.BoxShadow(
                          color: flutter.Colors.black.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const flutter.Offset(0, 2),
                        ),
                      ],
                    ),
                    child: flutter.SingleChildScrollView(
                      padding: flutter.EdgeInsets.fromLTRB(14, 4, 14, 30),
                      child: flutter.Column(
                        crossAxisAlignment: flutter.CrossAxisAlignment.start,
                        mainAxisSize: flutter.MainAxisSize.min,
                        children: [
                          // Ручка панели
                          flutter.Center(
                            child: flutter.Container(
                              margin: const flutter.EdgeInsets.only(
                                top: 8,
                                bottom: 4,
                              ),
                              width: 40,
                              height: 4,
                              decoration: flutter.BoxDecoration(
                                color: flutter.Colors.grey.shade400,
                                borderRadius: flutter.BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          // Название и иконка религии
                          flutter.Row(
                            children: [
                              SvgPicture.asset(
                                _getReligionIconPath(),
                                width: 26,
                                height: 26,
                                colorFilter: const flutter.ColorFilter.mode(
                                  AppColors.iconAndText,
                                  flutter.BlendMode.srcIn,
                                ),
                                placeholderBuilder:
                                    (flutter.BuildContext context) =>
                                        flutter.Container(
                                          width: 26,
                                          height: 26,
                                          color: flutter.Colors.transparent,
                                        ),
                              ),
                              const flutter.SizedBox(width: 8),
                              flutter.Expanded(
                                child: flutter.Text(
                                  widget.cemetery.name,
                                  style: const flutter.TextStyle(
                                    fontSize: 17,
                                    fontWeight: flutter.FontWeight.w700,
                                    color: AppColors.iconAndText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const flutter.SizedBox(height: 10),
                          // Легенда
                          flutter.Row(
                            children: [
                              _buildLegendItem(
                                color: flutter.Colors.green,
                                label: 'booking.details.freePlaces'.tr(
                                  namedArgs: {
                                    'count': widget.cemetery.freeSpaces
                                        .toString(),
                                  },
                                ),
                              ),
                              const flutter.SizedBox(width: 10),
                              _buildLegendItem(
                                color: flutter.Colors.orange,
                                label: 'booking.details.reservedPlaces'.tr(
                                  namedArgs: {
                                    'count': widget.cemetery.reservedSpaces
                                        .toString(),
                                  },
                                ),
                              ),
                            ],
                          ),
                          const flutter.SizedBox(height: 8),
                          _buildLegendItem(
                            color: flutter.Colors.grey,
                            label: 'booking.details.occupiedPlaces'.tr(
                              namedArgs: {
                                'count': widget.cemetery.occupiedSpaces
                                    .toString(),
                              },
                            ),
                          ),
                          const flutter.SizedBox(height: 10),
                          // Адрес
                          flutter.Row(
                            children: [
                              const flutter.Icon(
                                flutter.Icons.location_on,
                                size: 18,
                                color: AppColors.iconAndText,
                              ),
                              const flutter.SizedBox(width: 8),
                              flutter.Expanded(
                                child: flutter.Text(
                                  '${widget.cemetery.streetName}, ${widget.cemetery.city}',
                                  style: const flutter.TextStyle(
                                    fontSize: 13,
                                    color: AppColors.iconAndText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const flutter.SizedBox(height: 6),
                          // Телефон
                          flutter.Row(
                            children: [
                              const flutter.Icon(
                                flutter.Icons.phone,
                                size: 18,
                                color: AppColors.iconAndText,
                              ),
                              const flutter.SizedBox(width: 8),
                              flutter.Text(
                                '+${widget.cemetery.phone}',
                                style: const flutter.TextStyle(
                                  fontSize: 13,
                                  color: AppColors.iconAndText,
                                ),
                              ),
                            ],
                          ),
                          const flutter.SizedBox(height: 8),
                          // Описание
                          flutter.Text(
                            widget.cemetery.description,
                            style: const flutter.TextStyle(
                              fontSize: 13,
                              color: AppColors.iconAndText,
                              height: 1.4,
                            ),
                          ),
                          const flutter.SizedBox(height: 12),
                          // Информация о выбранном месте
                          _buildSelectedGraveInfo(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  flutter.Widget _buildLegendItem({
    required flutter.Color color,
    required String label,
  }) {
    return flutter.Row(
      mainAxisSize: flutter.MainAxisSize.min,
      children: [
        flutter.Container(
          width: 16,
          height: 16,
          decoration: flutter.BoxDecoration(
            color: color.withValues(alpha: 0.6),
            border: flutter.Border.all(color: flutter.Colors.black, width: 1),
            borderRadius: flutter.BorderRadius.circular(4),
          ),
        ),
        const flutter.SizedBox(width: 6),
        flutter.Text(
          label,
          style: const flutter.TextStyle(
            fontSize: 12,
            color: AppColors.iconAndText,
          ),
        ),
      ],
    );
  }
}
