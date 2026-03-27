import 'dart:async';

import 'package:flutter/material.dart' hide Icon, TextStyle;
import 'package:flutter/material.dart' as flutter;
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../constants.dart';
import '../models/cemetery.dart';
import '../models/grave.dart';
import '../services/cemetery_service.dart';
import '../services/location_service.dart';
import '../widgets/grave_status_legend.dart';
import 'grave_detail_page.dart';

class ManagerMapPage extends StatefulWidget {
  final Cemetery cemetery;

  const ManagerMapPage({super.key, required this.cemetery});

  @override
  State<ManagerMapPage> createState() => _ManagerMapPageState();
}

class _ManagerMapPageState extends State<ManagerMapPage> {
  final CemeteryService _cemeteryService = CemeteryService();
  final LocationService _locationService = LocationService();

  YandexMapController? _mapController;
  List<Grave> _graves = [];
  bool _isLoadingGraves = true;
  Grave? _selectedGrave;
  final Map<int, PolygonMapObject> _gravePolygons = {};
  bool _isLocating = false;
  bool _showLegend = true;

  static const double _sheetMaxFraction = 0.45;

  @override
  void initState() {
    super.initState();
    _loadGraves();
  }

  @override
  void dispose() {
    _locationService.stopTracking();
    super.dispose();
  }

  Future<void> _loadGraves() async {
    try {
      final lat = widget.cemetery.locationCoords[0];
      final lon = widget.cemetery.locationCoords[1];

      final minX = lon - 0.002;
      final maxX = lon + 0.002;
      final minY = lat - 0.002;
      final maxY = lat + 0.002;

      final graves = await _cemeteryService.getGravesByCoordinates(
        cemeteryId: widget.cemetery.id,
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
      );

      setState(() {
        _graves = graves;
        _isLoadingGraves = false;
      });

      _updateMapObjects();

      if (mounted && _mapController != null) {
        final (cLat, cLon) = _getCemeteryCenter();
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || _mapController == null) return;
          await _mapController!.moveCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: Point(latitude: cLat, longitude: cLon),
                zoom: 18.0,
              ),
            ),
          );
        });
      }
    } catch (e) {
      setState(() => _isLoadingGraves = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          flutter.SnackBar(
            content: flutter.Text('Ошибка загрузки могил: $e'),
          ),
        );
      }
    }
  }

  flutter.Color _graveColor(Grave grave) {
    switch (grave.status) {
      case 'free':
        return flutter.Colors.green.withAlpha(180);
      case 'reserved':
        return flutter.Colors.orange.withAlpha(180);
      case 'occupied':
        return flutter.Colors.grey.shade600.withAlpha(200);
      default:
        return flutter.Colors.blue.shade400.withAlpha(180);
    }
  }

  Future<void> _updateMapObjects() async {
    if (_mapController == null) return;
    _gravePolygons.clear();

    for (final grave in _graves) {
      if (grave.polygonData.coordinates.isNotEmpty) {
        final polygon = PolygonMapObject(
          mapId: MapObjectId('grave_${grave.id}'),
          polygon: Polygon(
            outerRing: LinearRing(
              points: grave.polygonData.coordinates
                  .map((c) => Point(latitude: c[1], longitude: c[0]))
                  .toList(),
            ),
            innerRings: const [],
          ),
          strokeColor: flutter.Colors.black,
          strokeWidth: 2.0,
          fillColor: _graveColor(grave),
          onTap: (_, __) => _onGraveTap(grave),
        );
        _gravePolygons[grave.id] = polygon;
      }
    }

    if (mounted) setState(() {});
  }

  void _onGraveTap(Grave grave) {
    setState(() {
      // Сбрасываем рамку предыдущего
      if (_selectedGrave != null &&
          _gravePolygons.containsKey(_selectedGrave!.id)) {
        final prev = _gravePolygons[_selectedGrave!.id]!;
        _gravePolygons[_selectedGrave!.id] = prev.copyWith(
          strokeColor: flutter.Colors.black,
          strokeWidth: 2.0,
        );
      }
      _selectedGrave = grave;
      // Выделяем выбранное красной рамкой
      if (_gravePolygons.containsKey(grave.id)) {
        final cur = _gravePolygons[grave.id]!;
        _gravePolygons[grave.id] = cur.copyWith(
          strokeColor: flutter.Colors.red,
          strokeWidth: 4.0,
        );
      }
    });
  }

  (double, double) _getCemeteryCenter() {
    final poly = widget.cemetery.polygonCoordinates;
    if (poly.isNotEmpty) {
      double sLon = 0, sLat = 0;
      for (final c in poly) {
        if (c.length >= 2) {
          sLon += c[0];
          sLat += c[1];
        }
      }
      final n = poly.length;
      if (n > 0) return (sLat / n, sLon / n);
    }
    final coords = widget.cemetery.locationCoords;
    if (coords.length >= 2) return (coords[0], coords[1]);
    return (43.25, 76.95);
  }

  Future<void> _centerOnMyLocation() async {
    setState(() => _isLocating = true);
    try {
      final pos = await _locationService.getCurrentPosition();
      if (pos != null && _mapController != null) {
        await _mapController!.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: Point(latitude: pos.latitude, longitude: pos.longitude),
              zoom: 19.0,
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const flutter.SnackBar(
            content: flutter.Text(
              'Не удалось определить местоположение. Проверьте GPS.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _openGraveDetail(Grave grave) {
    Navigator.push(
      context,
      flutter.MaterialPageRoute(
        builder: (_) => GraveDetailPage(
          grave: grave,
          cemetery: widget.cemetery,
        ),
      ),
    ).then((_) {
      // Перезагружаем могилы после возврата (данные могли измениться)
      _loadGraves();
    });
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'free':
        return 'Свободно';
      case 'reserved':
        return 'Забронировано';
      case 'occupied':
        return 'Захоронено';
      default:
        return 'Резерв';
    }
  }

  flutter.Color _statusColor(String status) {
    switch (status) {
      case 'free':
        return flutter.Colors.green;
      case 'reserved':
        return flutter.Colors.orange;
      case 'occupied':
        return flutter.Colors.grey;
      default:
        return flutter.Colors.blue.shade400;
    }
  }

  @override
  flutter.Widget build(flutter.BuildContext context) {
    return flutter.Scaffold(
      backgroundColor: flutter.Colors.white,
      body: flutter.Stack(
        children: [
          // Карта на весь экран
          YandexMap(
            cameraBounds: const CameraBounds(minZoom: 10, maxZoom: 22),
            onMapCreated: (YandexMapController controller) async {
              _mapController = controller;
              final (lat, lon) = _getCemeteryCenter();
              await _mapController!.moveCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: Point(latitude: lat, longitude: lon),
                    zoom: 18.0,
                  ),
                ),
              );
              if (!_isLoadingGraves) _updateMapObjects();
              try {
                await _mapController!.toggleUserLayer(
                  visible: true,
                  headingEnabled: true,
                  autoZoomEnabled: false,
                );
              } catch (e) {
                debugPrint('User location layer: $e');
              }
            },
            mapObjects: [
              ..._gravePolygons.values,
            ],
          ),

          // Индикатор загрузки
          if (_isLoadingGraves)
            const flutter.Center(
              child: flutter.Card(
                child: flutter.Padding(
                  padding: flutter.EdgeInsets.all(16),
                  child: flutter.Column(
                    mainAxisSize: flutter.MainAxisSize.min,
                    children: [
                      flutter.CircularProgressIndicator(
                        color: AppColors.buttonBackground,
                      ),
                      flutter.SizedBox(height: 12),
                      flutter.Text('Загрузка мест...'),
                    ],
                  ),
                ),
              ),
            ),

          // Кнопка назад и заголовок
          flutter.Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: flutter.SafeArea(
              bottom: false,
              child: flutter.Container(
                margin: const flutter.EdgeInsets.all(12),
                decoration: flutter.BoxDecoration(
                  color: flutter.Colors.white,
                  borderRadius: flutter.BorderRadius.circular(12),
                  boxShadow: [
                    flutter.BoxShadow(
                      color: flutter.Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: flutter.Row(
                  children: [
                    flutter.IconButton(
                      icon: const flutter.Icon(
                        flutter.Icons.arrow_back,
                        color: AppColors.iconAndText,
                      ),
                      onPressed: () => flutter.Navigator.pop(context),
                    ),
                    flutter.Expanded(
                      child: flutter.Text(
                        widget.cemetery.name,
                        style: const flutter.TextStyle(
                          fontSize: 15,
                          fontWeight: flutter.FontWeight.w600,
                          color: AppColors.iconAndText,
                        ),
                        overflow: flutter.TextOverflow.ellipsis,
                      ),
                    ),
                    flutter.IconButton(
                      icon: const flutter.Icon(
                        flutter.Icons.refresh,
                        color: AppColors.iconAndText,
                      ),
                      onPressed: _loadGraves,
                      tooltip: 'Обновить карту',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Легенда
          flutter.Positioned(
            top: 80,
            left: 12,
            child: flutter.SafeArea(
                child: flutter.AnimatedOpacity(
                  opacity: _showLegend ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                child: const GraveStatusLegend(),
              ),
            ),
          ),

          // Кнопка скрыть/показать легенду
          flutter.Positioned(
            top: 80,
            right: 12,
            child: flutter.SafeArea(
              child: flutter.Column(
                children: [
                  _MapButton(
                    icon: _showLegend
                        ? flutter.Icons.layers_clear
                        : flutter.Icons.layers,
                    tooltip: _showLegend ? 'Скрыть легенду' : 'Легенда',
                    onTap: () => setState(() => _showLegend = !_showLegend),
                  ),
                ],
              ),
            ),
          ),

          // Кнопка моего местоположения
          flutter.Positioned(
            bottom: _selectedGrave != null
                ? MediaQuery.of(context).size.height * _sheetMaxFraction + 12
                : 120,
            right: 12,
            child: _isLocating
                ? const flutter.Card(
                    child: flutter.Padding(
                      padding: flutter.EdgeInsets.all(12),
                      child: flutter.SizedBox(
                        width: 24,
                        height: 24,
                        child: flutter.CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.buttonBackground,
                        ),
                      ),
                    ),
                  )
                : _MapButton(
                    icon: flutter.Icons.my_location,
                    tooltip: 'Моё местоположение',
                    onTap: _centerOnMyLocation,
                  ),
          ),

          // Нижняя панель выбранного места
          if (_selectedGrave != null)
            flutter.Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: flutter.SafeArea(
                top: false,
                child: flutter.Container(
                  constraints: flutter.BoxConstraints(
                    maxHeight:
                        MediaQuery.of(context).size.height * _sheetMaxFraction,
                  ),
                  decoration: flutter.BoxDecoration(
                    color: flutter.Colors.white,
                    borderRadius: const flutter.BorderRadius.only(
                      topLeft: flutter.Radius.circular(16),
                      topRight: flutter.Radius.circular(16),
                    ),
                    boxShadow: [
                      flutter.BoxShadow(
                        color: flutter.Colors.black.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const flutter.Offset(0, -2),
                      ),
                    ],
                  ),
                  child: flutter.SingleChildScrollView(
                    padding: const flutter.EdgeInsets.fromLTRB(16, 4, 16, 24),
                    child: _buildSelectedGravePanel(_selectedGrave!),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  flutter.Widget _buildSelectedGravePanel(Grave grave) {
    return flutter.Column(
      mainAxisSize: flutter.MainAxisSize.min,
      crossAxisAlignment: flutter.CrossAxisAlignment.start,
      children: [
        // Ручка
        flutter.Center(
          child: flutter.Container(
            margin: const flutter.EdgeInsets.only(top: 8, bottom: 12),
            width: 40,
            height: 4,
            decoration: flutter.BoxDecoration(
              color: flutter.Colors.grey.shade300,
              borderRadius: flutter.BorderRadius.circular(2),
            ),
          ),
        ),

        flutter.Row(
          children: [
            flutter.Expanded(
              child: flutter.Text(
                'Место ${grave.sectorNumber}-${grave.rowNumber}-${grave.graveNumber}',
                style: const flutter.TextStyle(
                  fontSize: 17,
                  fontWeight: flutter.FontWeight.w700,
                  color: AppColors.iconAndText,
                ),
              ),
            ),
            flutter.IconButton(
              icon: const flutter.Icon(flutter.Icons.close, size: 20),
              onPressed: () {
                setState(() {
                  if (_gravePolygons.containsKey(_selectedGrave!.id)) {
                    final p = _gravePolygons[_selectedGrave!.id]!;
                    _gravePolygons[_selectedGrave!.id] = p.copyWith(
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

        const flutter.SizedBox(height: 8),

        flutter.Row(
          children: [
            flutter.Container(
              width: 12,
              height: 12,
              decoration: flutter.BoxDecoration(
                color: _statusColor(grave.status),
                shape: flutter.BoxShape.circle,
              ),
            ),
            const flutter.SizedBox(width: 8),
            flutter.Text(
              _statusLabel(grave.status),
              style: flutter.TextStyle(
                fontSize: 14,
                color: _statusColor(grave.status),
                fontWeight: flutter.FontWeight.w600,
              ),
            ),
          ],
        ),

        const flutter.SizedBox(height: 6),

        flutter.Row(
          children: [
            _InfoChip(
              label: 'Участок',
              value: grave.sectorNumber,
            ),
            const flutter.SizedBox(width: 8),
            _InfoChip(label: 'Ряд', value: grave.rowNumber),
            const flutter.SizedBox(width: 8),
            _InfoChip(label: 'Место', value: grave.graveNumber),
          ],
        ),

        const flutter.SizedBox(height: 16),

        flutter.SizedBox(
          width: double.infinity,
          height: 48,
          child: flutter.ElevatedButton.icon(
            icon: const flutter.Icon(
              flutter.Icons.edit_note,
              size: 20,
              color: flutter.Colors.white,
            ),
            label: const flutter.Text(
              'Открыть карточку',
              style: flutter.TextStyle(
                fontSize: 15,
                fontWeight: flutter.FontWeight.w600,
                color: flutter.Colors.white,
              ),
            ),
            onPressed: () => _openGraveDetail(grave),
            style: flutter.ElevatedButton.styleFrom(
              backgroundColor: AppColors.buttonBackground,
              shape: flutter.RoundedRectangleBorder(
                borderRadius: flutter.BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapButton extends flutter.StatelessWidget {
  final flutter.IconData icon;
  final String tooltip;
  final flutter.VoidCallback onTap;

  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  flutter.Widget build(flutter.BuildContext context) {
    return flutter.Tooltip(
      message: tooltip,
      child: flutter.Material(
        color: flutter.Colors.white,
        shape: const flutter.CircleBorder(),
        elevation: 4,
        child: flutter.InkWell(
          customBorder: const flutter.CircleBorder(),
          onTap: onTap,
          child: flutter.Padding(
            padding: const flutter.EdgeInsets.all(12),
            child: flutter.Icon(
              icon,
              color: AppColors.iconAndText,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends flutter.StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  flutter.Widget build(flutter.BuildContext context) {
    return flutter.Container(
      padding: const flutter.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: flutter.BoxDecoration(
        color: const flutter.Color(0xFFF4F0E7),
        borderRadius: flutter.BorderRadius.circular(8),
      ),
      child: flutter.Column(
        mainAxisSize: flutter.MainAxisSize.min,
        children: [
          flutter.Text(
            label,
            style: const flutter.TextStyle(
              fontSize: 10,
              color: AppColors.iconAndText,
            ),
          ),
          flutter.Text(
            value,
            style: const flutter.TextStyle(
              fontSize: 14,
              fontWeight: flutter.FontWeight.w700,
              color: AppColors.iconAndText,
            ),
          ),
        ],
      ),
    );
  }
}
