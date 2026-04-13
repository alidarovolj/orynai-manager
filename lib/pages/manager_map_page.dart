import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Icon, TextStyle;
import 'package:flutter/material.dart' as flutter;
// yandex_maps_mapkit_lite — экспортирует Point, CameraPosition, Polygon, LinearRing,
// PolygonMapObject, MapObjectTapListener, MapObject, MapWindow, UserLocationLayer
import 'package:yandex_maps_mapkit_lite/mapkit.dart' hide Map;
import 'package:yandex_maps_mapkit_lite/yandex_map.dart';
import 'package:yandex_maps_mapkit_lite/mapkit_factory.dart' as mk_factory;
import '../constants.dart';
import '../models/cemetery.dart';
import '../models/grave.dart';
import '../services/cemetery_service.dart';
import '../services/location_service.dart';
import '../services/audit_service.dart';
import 'grave_detail_page.dart';

class ManagerMapPage extends StatefulWidget {
  final Cemetery cemetery;

  /// Без собственного [Scaffold] и кнопки «Назад» — для встраивания рядом со списком.
  final bool embedded;

  /// Выбранное место снаружи (например сайдбар на [ManagerHomePage]).
  final Grave? selectedGrave;

  /// Сообщить родителю о выборе / сбросе места (тогда нижний лист на карте не показывается).
  final ValueChanged<Grave?>? onSelectedGraveChanged;

  const ManagerMapPage({
    super.key,
    required this.cemetery,
    this.embedded = false,
    this.selectedGrave,
    this.onSelectedGraveChanged,
  });

  @override
  State<ManagerMapPage> createState() => _ManagerMapPageState();
}

class _ManagerMapPageState extends State<ManagerMapPage> {
  final CemeteryService _cemeteryService = CemeteryService();
  final LocationService _locationService = LocationService();
  final AuditService _audit = AuditService();

  MapWindow? _mapWindow;
  MapObjectCollection? _mapObjects;

  List<Grave> _graves = [];
  bool _isLoadingGraves = true;
  bool _isFromCache = false;
  Grave? _selectedGrave;
  final Map<int, PolygonMapObject> _gravePolygons = {};

  // Сильные ссылки на tap-слушатели (MapKit держит их weak ref)
  final List<_GraveTapListener> _tapListeners = [];

  bool _isLocating = false;

  // Поиск по номеру
  final flutter.TextEditingController _searchController =
      flutter.TextEditingController();
  List<Grave> _searchResults = [];

  static const double _sheetMaxFraction = 0.45;

  @override
  void initState() {
    super.initState();
    _audit.log(
      action: AuditAction.openMap,
      entityType: 'cemetery',
      entityId: widget.cemetery.id,
      details: widget.cemetery.name,
    );
    _loadGraves();
    // Прогреваем GPS заранее — к моменту нажатия "Моё местоположение"
    // GNSS-чип уже будет иметь фикс.
    _locationService.startTracking();
  }

  @override
  void dispose() {
    _locationService.stopTracking();
    _searchController.dispose();
    super.dispose();
  }

  bool get _usesExternalSelection => widget.onSelectedGraveChanged != null;

  Grave? get _effectiveSelected =>
      _usesExternalSelection ? widget.selectedGrave : _selectedGrave;

  @override
  void didUpdateWidget(ManagerMapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_usesExternalSelection &&
        oldWidget.selectedGrave?.id != widget.selectedGrave?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapWindow != null) _updateMapObjects();
      });
    }
  }

  Future<void> _loadGraves() async {
    setState(() => _isLoadingGraves = true);

    // 1. Сначала показываем кэш мгновенно
    final cached = await _cemeteryService.getCachedGraves(widget.cemetery.id);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _graves = cached;
        _isFromCache = true;
        _isLoadingGraves = false;
      });
      _updateMapObjects();
    }

    // 2. Загружаем с сервера (обновляет кэш внутри сервиса)
    try {
      final lat = widget.cemetery.locationCoords[0];
      final lon = widget.cemetery.locationCoords[1];

      final graves = await _cemeteryService.getGravesByCoordinates(
        cemeteryId: widget.cemetery.id,
        minX: lon - 0.005,
        maxX: lon + 0.005,
        minY: lat - 0.005,
        maxY: lat + 0.005,
      );

      if (mounted) {
        setState(() {
          _graves = graves;
          _isFromCache = false;
          _isLoadingGraves = false;
        });
        _updateMapObjects();

        if (_mapWindow != null) {
          final (cLat, cLon) = _getCemeteryCenter();
          _moveCamera(cLat, cLon, 18.0);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingGraves = false);
        if (cached.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            flutter.SnackBar(
              content: flutter.Text('Нет данных. Проверьте подключение.'),
            ),
          );
        }
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

  void _updateMapObjects() {
    final mapObjs = _mapObjects;
    if (mapObjs == null) return;

    // Очищаем все объекты и tap-слушатели
    mapObjs.clear();
    _gravePolygons.clear();
    _tapListeners.clear();

    final selectedId = _effectiveSelected?.id;

    for (final grave in _graves) {
      if (grave.polygonData.coordinates.isEmpty) continue;

      final isSelected = grave.id == selectedId;
      final points = grave.polygonData.coordinates
          .map((c) => Point(latitude: c[1], longitude: c[0]))
          .toList();

      final polygon = mapObjs.addPolygon(
        Polygon(LinearRing(points), []),
      );

      polygon.fillColor = _graveColor(grave);
      polygon.strokeColor =
          isSelected ? flutter.Colors.red : flutter.Colors.black;
      polygon.strokeWidth = isSelected ? 4.0 : 2.0;

      // Создаём и сохраняем tap-слушатель (strong ref!)
      final listener = _GraveTapListener(
        grave: grave,
        onTap: _onGraveTap,
      );
      _tapListeners.add(listener);
      polygon.addTapListener(listener);

      _gravePolygons[grave.id] = polygon;
    }

    if (mounted) setState(() {});
  }

  void _onGraveTap(Grave grave) {
    if (_usesExternalSelection) {
      widget.onSelectedGraveChanged!(grave);
      return;
    }

    // Сбросить выделение предыдущего
    if (_selectedGrave != null) {
      final prev = _gravePolygons[_selectedGrave!.id];
      if (prev != null) {
        prev.strokeColor = flutter.Colors.black;
        prev.strokeWidth = 2.0;
      }
    }

    // Выделить новый
    final cur = _gravePolygons[grave.id];
    if (cur != null) {
      cur.strokeColor = flutter.Colors.red;
      cur.strokeWidth = 4.0;
    }

    setState(() => _selectedGrave = grave);
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

  void _moveCamera(double lat, double lon, double zoom) {
    _mapWindow?.map.move(
      CameraPosition(
        Point(latitude: lat, longitude: lon),
        zoom: zoom,
        azimuth: 0.0,
        tilt: 0.0,
      ),
    );
  }

  Future<void> _centerOnMyLocation() async {
    setState(() => _isLocating = true);
    try {
      final pos = await _locationService.getCurrentPosition();
      if (pos != null && _mapWindow != null) {
        _moveCamera(pos.latitude, pos.longitude, 19.0);
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
    _audit.log(
      action: AuditAction.viewGrave,
      entityType: 'grave',
      entityId: grave.id,
      details: grave.fullNumber,
    );
    Navigator.push(
      context,
      flutter.MaterialPageRoute(
        builder: (_) =>
            GraveDetailPage(grave: grave, cemetery: widget.cemetery),
      ),
    ).then((_) => _loadGraves());
  }

  // ─── Поиск по номеру ──────────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final q = query.trim().toLowerCase();
    setState(() {
      _searchResults = _graves
          .where((g) {
            return g.graveNumber.toLowerCase().contains(q) ||
                g.sectorNumber.toLowerCase().contains(q) ||
                g.rowNumber.toLowerCase().contains(q) ||
                g.fullNumber.toLowerCase().contains(q);
          })
          .take(20)
          .toList();
    });
  }

  void _selectFromSearch(Grave grave) {
    _searchController.clear();
    setState(() => _searchResults = []);
    if (_usesExternalSelection) {
      widget.onSelectedGraveChanged!(grave);
    } else {
      _onGraveTap(grave);
    }
    // Центрируем камеру на могиле
    if (grave.polygonData.coordinates.isNotEmpty) {
      double sumLat = 0, sumLon = 0;
      for (final c in grave.polygonData.coordinates) {
        sumLon += c[0];
        sumLat += c[1];
      }
      final n = grave.polygonData.coordinates.length;
      _moveCamera(sumLat / n, sumLon / n, 21.0);
    }
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

  // ─── Инициализация карты ──────────────────────────────────────────────────

  void _onMapCreated(MapWindow mapWindow) {
    _mapWindow = mapWindow;
    _mapObjects = mapWindow.map.mapObjects;

    final (lat, lon) = _getCemeteryCenter();
    _moveCamera(lat, lon, 18.0);

    // Слой геолокации пользователя
    try {
      final userLayer = mk_factory.mapkit.createUserLocationLayer(mapWindow);
      userLayer.setVisible(true);
      userLayer.headingModeActive = true;
    } catch (e) {
      debugPrint('User location layer error: $e');
    }

    if (!_isLoadingGraves) _updateMapObjects();
  }

  flutter.Widget _buildMapStack(flutter.BuildContext context) {
    return flutter.LayoutBuilder(
      builder: (context, constraints) {
        final screenH = MediaQuery.sizeOf(context).height;
        final panelH =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : screenH;
        final fabBottom = _effectiveSelected != null &&
                !_usesExternalSelection
            ? panelH * _sheetMaxFraction + 12
            : 120.0;
        final sheetMaxH = panelH * _sheetMaxFraction;

        return flutter.Stack(
          fit: StackFit.expand,
          children: [
            // Карта на весь экран — только Android; на iOS MapKit недоступен
            if (Platform.isAndroid)
              YandexMap(onMapCreated: _onMapCreated)
            else
              const flutter.Center(
                child: flutter.Text('Карта доступна только на Android'),
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

            // Верхняя панель: поиск + статус-бейджи
            flutter.Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: flutter.SafeArea(
                bottom: false,
                child: flutter.Column(
                  mainAxisSize: flutter.MainAxisSize.min,
                  children: [
                    // Заголовок — только в не-embedded режиме
                    if (!widget.embedded)
                      flutter.Container(
                        margin: const flutter.EdgeInsets.fromLTRB(12, 12, 12, 0),
                        decoration: flutter.BoxDecoration(
                          color: flutter.Colors.white,
                          borderRadius: flutter.BorderRadius.circular(12),
                          boxShadow: [
                            flutter.BoxShadow(
                              color: flutter.Colors.black.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const flutter.Offset(0, 2),
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
                            if (_isFromCache)
                              const flutter.Padding(
                                padding: flutter.EdgeInsets.only(right: 4),
                                child: flutter.Tooltip(
                                  message: 'Показаны сохранённые данные',
                                  child: flutter.Icon(
                                    flutter.Icons.offline_bolt,
                                    color: flutter.Colors.orange,
                                    size: 18,
                                  ),
                                ),
                              ),
                            flutter.IconButton(
                              icon: const flutter.Icon(
                                flutter.Icons.refresh,
                                color: AppColors.iconAndText,
                                size: 20,
                              ),
                              onPressed: _loadGraves,
                              tooltip: 'Обновить',
                            ),
                          ],
                        ),
                      ),
                    // Поиск + статус-бейджи в одну строку
                    flutter.Container(
                      margin: flutter.EdgeInsets.fromLTRB(
                        12,
                        widget.embedded ? 12 : 8,
                        12,
                        0,
                      ),
                      padding: const flutter.EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      decoration: flutter.BoxDecoration(
                        color: flutter.Colors.white,
                        borderRadius: flutter.BorderRadius.circular(12),
                        boxShadow: [
                          flutter.BoxShadow(
                            color: flutter.Colors.black.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: const flutter.Offset(0, 2),
                          ),
                        ],
                      ),
                      child: flutter.Row(
                        children: [
                          // Поле поиска
                          flutter.Expanded(
                            child: flutter.TextField(
                              controller: _searchController,
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: const [],
                              style: const flutter.TextStyle(
                                fontSize: 14,
                                color: AppColors.iconAndText,
                              ),
                              decoration: flutter.InputDecoration(
                                hintText: 'Поиск по сектору или номеру места...',
                                hintStyle: flutter.TextStyle(
                                  fontSize: 13,
                                  color: AppColors.iconAndText.withValues(alpha: 0.45),
                                ),
                                prefixIcon: const flutter.Icon(
                                  flutter.Icons.search,
                                  size: 18,
                                  color: AppColors.iconAndText,
                                ),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? flutter.IconButton(
                                        icon: const flutter.Icon(
                                          flutter.Icons.clear,
                                          size: 16,
                                          color: AppColors.iconAndText,
                                        ),
                                        onPressed: () {
                                          _searchController.clear();
                                          _onSearchChanged('');
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: AppColors.background,
                                isDense: true,
                                border: flutter.OutlineInputBorder(
                                  borderRadius: flutter.BorderRadius.circular(8),
                                  borderSide: flutter.BorderSide.none,
                                ),
                                enabledBorder: flutter.OutlineInputBorder(
                                  borderRadius: flutter.BorderRadius.circular(8),
                                  borderSide: flutter.BorderSide.none,
                                ),
                                focusedBorder: flutter.OutlineInputBorder(
                                  borderRadius: flutter.BorderRadius.circular(8),
                                  borderSide: const flutter.BorderSide(
                                    color: AppColors.buttonBackground,
                                    width: 1.5,
                                  ),
                                ),
                                contentPadding: const flutter.EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                              ),
                              onChanged: _onSearchChanged,
                            ),
                          ),
                          // Статус-бейджи
                          const flutter.SizedBox(width: 6),
                          _StatusBadge(
                            label: 'Свободно',
                            count: widget.cemetery.freeSpaces,
                            color: const flutter.Color(0xFF4CAF50),
                            textColor: flutter.Colors.white,
                          ),
                          const flutter.SizedBox(width: 4),
                          _StatusBadge(
                            label: 'Захоронено',
                            count: widget.cemetery.occupiedSpaces,
                            color: const flutter.Color(0xFFBDBDBD),
                            textColor: const flutter.Color(0xFF424242),
                          ),
                          const flutter.SizedBox(width: 4),
                          _StatusBadge(
                            label: 'Бронь',
                            count: widget.cemetery.reservedSpaces,
                            color: AppColors.buttonBackground,
                            textColor: flutter.Colors.white,
                          ),
                          const flutter.SizedBox(width: 4),
                        ],
                      ),
                    ),
                    // Выпадающий список результатов
                    if (_searchResults.isNotEmpty)
                      flutter.Container(
                        margin: const flutter.EdgeInsets.fromLTRB(12, 4, 12, 0),
                        constraints: const flutter.BoxConstraints(maxHeight: 260),
                        decoration: flutter.BoxDecoration(
                          color: flutter.Colors.white,
                          borderRadius: flutter.BorderRadius.circular(12),
                          boxShadow: [
                            flutter.BoxShadow(
                              color: flutter.Colors.black.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const flutter.Offset(0, 2),
                            ),
                          ],
                        ),
                        child: flutter.ClipRRect(
                          borderRadius: flutter.BorderRadius.circular(12),
                          child: flutter.ListView.separated(
                            shrinkWrap: true,
                            padding: flutter.EdgeInsets.zero,
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) =>
                                const flutter.Divider(height: 1, indent: 16, endIndent: 16),
                            itemBuilder: (_, i) {
                              final g = _searchResults[i];
                              return flutter.InkWell(
                                onTap: () => _selectFromSearch(g),
                                child: flutter.Padding(
                                  padding: const flutter.EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10,
                                  ),
                                  child: flutter.Row(
                                    children: [
                                      flutter.Container(
                                        width: 12,
                                        height: 12,
                                        decoration: flutter.BoxDecoration(
                                          color: _graveColor(g),
                                          shape: flutter.BoxShape.circle,
                                          border: flutter.Border.all(
                                            color: flutter.Colors.black26,
                                            width: 0.5,
                                          ),
                                        ),
                                      ),
                                      const flutter.SizedBox(width: 12),
                                      flutter.Expanded(
                                        child: flutter.Column(
                                          crossAxisAlignment: flutter.CrossAxisAlignment.start,
                                          children: [
                                            flutter.Text(
                                              'Участок ${g.sectorNumber}  ·  Ряд ${g.rowNumber}  ·  Место ${g.graveNumber}',
                                              style: const flutter.TextStyle(
                                                fontSize: 14,
                                                fontWeight: flutter.FontWeight.w500,
                                                color: AppColors.iconAndText,
                                              ),
                                            ),
                                            flutter.Text(
                                              _statusLabel(g.status),
                                              style: flutter.TextStyle(
                                                fontSize: 12,
                                                color: _statusColor(g.status),
                                                fontWeight: flutter.FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const flutter.Icon(
                                        flutter.Icons.arrow_forward_ios,
                                        size: 14,
                                        color: AppColors.iconAndText,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    // «Ничего не найдено» — только когда запрос непустой
                    if (_searchController.text.isNotEmpty &&
                        _searchResults.isEmpty &&
                        !_isLoadingGraves)
                      flutter.Container(
                        margin: const flutter.EdgeInsets.fromLTRB(12, 4, 12, 0),
                        padding: const flutter.EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: flutter.BoxDecoration(
                          color: flutter.Colors.white,
                          borderRadius: flutter.BorderRadius.circular(12),
                          boxShadow: [
                            flutter.BoxShadow(
                              color: flutter.Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: flutter.Row(
                          children: [
                            flutter.Icon(
                              flutter.Icons.search_off,
                              size: 18,
                              color: AppColors.iconAndText.withValues(alpha: 0.5),
                            ),
                            const flutter.SizedBox(width: 10),
                            flutter.Text(
                              'Место не найдено',
                              style: flutter.TextStyle(
                                fontSize: 13,
                                color: AppColors.iconAndText.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Кнопка моего местоположения
            flutter.Positioned(
              bottom: fabBottom,
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

            // Нижняя панель — только без внешнего сайдбара (полноэкранная карта)
            if (_effectiveSelected != null && !_usesExternalSelection)
              flutter.Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: flutter.SafeArea(
                  top: false,
                  child: flutter.Container(
                    constraints: flutter.BoxConstraints(maxHeight: sheetMaxH),
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
                      child: _buildSelectedGravePanel(_effectiveSelected!),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  flutter.Widget build(flutter.BuildContext context) {
    final stack = _buildMapStack(context);
    if (widget.embedded) {
      return flutter.ColoredBox(color: flutter.Colors.white, child: stack);
    }
    return flutter.Scaffold(backgroundColor: flutter.Colors.white, body: stack);
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
                // Сбросить выделение полигона
                final sel = _selectedGrave;
                if (sel != null) {
                  final p = _gravePolygons[sel.id];
                  if (p != null) {
                    p.strokeColor = flutter.Colors.black;
                    p.strokeWidth = 2.0;
                  }
                }
                setState(() => _selectedGrave = null);
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
            _InfoChip(label: 'Участок', value: grave.sectorNumber),
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

// ─── Tap-слушатель для полигона могилы ────────────────────────────────────────

class _GraveTapListener implements MapObjectTapListener {
  final Grave grave;
  final void Function(Grave) onTap;

  _GraveTapListener({required this.grave, required this.onTap});

  @override
  bool onMapObjectTap(MapObject mapObject, Point point) {
    onTap(grave);
    return true;
  }
}

// ─── Вспомогательные виджеты ──────────────────────────────────────────────────

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
            child: flutter.Icon(icon, color: AppColors.iconAndText, size: 22),
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

class _StatusBadge extends flutter.StatelessWidget {
  final String label;
  final int count;
  final flutter.Color color;
  final flutter.Color textColor;

  const _StatusBadge({
    required this.label,
    required this.count,
    required this.color,
    required this.textColor,
  });

  @override
  flutter.Widget build(flutter.BuildContext context) {
    return flutter.Container(
      padding: const flutter.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: flutter.BoxDecoration(
        color: color,
        borderRadius: flutter.BorderRadius.circular(6),
      ),
      child: flutter.Text(
        '$label: $count',
        style: flutter.TextStyle(
          fontSize: 12,
          fontWeight: flutter.FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
