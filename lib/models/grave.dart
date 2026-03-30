import 'dart:convert';

class Grave {
  final int id;
  final int cemeteryId;
  final String cemeteryName;
  final String sectorNumber;
  final String rowNumber;
  final String graveNumber;
  final String status;
  final int width;
  final int height;
  final PolygonData polygonData;

  Grave({
    required this.id,
    required this.cemeteryId,
    required this.cemeteryName,
    required this.sectorNumber,
    required this.rowNumber,
    required this.graveNumber,
    required this.status,
    required this.width,
    required this.height,
    required this.polygonData,
  });

  factory Grave.fromJson(Map<String, dynamic> json) {
    return Grave(
      id: json['id'],
      cemeteryId: json['cemetery_id'],
      cemeteryName: json['cemetery_name'],
      sectorNumber: json['sector_number'],
      rowNumber: json['row_number'],
      graveNumber: json['grave_number'],
      status: json['status'],
      width: json['width'],
      height: json['height'],
      polygonData: PolygonData.fromJson(json['polygon_data']),
    );
  }

  bool get isFree => status == 'free';
  bool get isReserved => status == 'reserved';
  bool get isOccupied => status == 'occupied';

  /// Полный номер для поиска: "Участок-Ряд-Место"
  String get fullNumber => '$sectorNumber-$rowNumber-$graveNumber';

  Map<String, dynamic> toMap() => {
        'id': id,
        'cemetery_id': cemeteryId,
        'cemetery_name': cemeteryName,
        'sector_number': sectorNumber,
        'row_number': rowNumber,
        'grave_number': graveNumber,
        'status': status,
        'width': width,
        'height': height,
        'polygon_data': jsonEncode({
          'coordinates': polygonData.coordinates,
          'color': polygonData.color,
          'stroke_width': polygonData.strokeWidth,
          'stroke_color': polygonData.strokeColor,
        }),
        'cached_at': DateTime.now().toIso8601String(),
      };

  factory Grave.fromDbMap(Map<String, dynamic> map) {
    final polyJson =
        jsonDecode(map['polygon_data'] as String) as Map<String, dynamic>;
    return Grave(
      id: map['id'] as int,
      cemeteryId: map['cemetery_id'] as int,
      cemeteryName: map['cemetery_name'] as String? ?? '',
      sectorNumber: map['sector_number'] as String? ?? '',
      rowNumber: map['row_number'] as String? ?? '',
      graveNumber: map['grave_number'] as String? ?? '',
      status: map['status'] as String? ?? 'free',
      width: map['width'] as int? ?? 0,
      height: map['height'] as int? ?? 0,
      polygonData: PolygonData.fromJson(polyJson),
    );
  }
}

class PolygonData {
  final List<List<double>> coordinates;
  final String color;
  final int strokeWidth;
  final String strokeColor;

  PolygonData({
    required this.coordinates,
    required this.color,
    required this.strokeWidth,
    required this.strokeColor,
  });

  factory PolygonData.fromJson(Map<String, dynamic> json) {
    return PolygonData(
      coordinates: (json['coordinates'] as List)
          .map((coord) => List<double>.from(coord))
          .toList(),
      color: json['color'] ?? '#008000',
      strokeWidth: json['stroke_width'] ?? 2,
      strokeColor: json['stroke_color'] ?? '#000000',
    );
  }
}
