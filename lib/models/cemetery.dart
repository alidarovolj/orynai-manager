import 'dart:convert';

class Cemetery {
  final int id;
  final String name;
  final String description;
  final String country;
  final String city;
  final String streetName;
  final String? nameKz;
  final String? descriptionKz;
  final String phone;
  final List<double> locationCoords;
  final List<List<double>> polygonCoordinates;
  final String religion;
  final int burialPrice;
  final String status;
  final int capacity;
  final int freeSpaces;
  final int reservedSpaces;
  final int occupiedSpaces;

  Cemetery({
    required this.id,
    required this.name,
    required this.description,
    required this.country,
    required this.city,
    required this.streetName,
    this.nameKz,
    this.descriptionKz,
    required this.phone,
    required this.locationCoords,
    required this.polygonCoordinates,
    required this.religion,
    required this.burialPrice,
    required this.status,
    required this.capacity,
    required this.freeSpaces,
    required this.reservedSpaces,
    required this.occupiedSpaces,
  });

  factory Cemetery.fromJson(Map<String, dynamic> json) {
    final polygonData = json['polygon_data'];
    final List<List<double>> coordinates = polygonData != null && polygonData['coordinates'] != null
        ? (polygonData['coordinates'] as List)
            .map((coord) => List<double>.from(coord))
            .toList()
        : [];

    return Cemetery(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      country: json['country'],
      city: json['city'],
      streetName: json['street_name'],
      nameKz: json['name_kz'],
      descriptionKz: json['description_kz'],
      phone: json['phone'],
      locationCoords: List<double>.from(json['location_coords']),
      polygonCoordinates: coordinates,
      religion: json['religion'],
      burialPrice: json['burial_price'],
      status: json['status'],
      capacity: json['capacity'],
      freeSpaces: json['free_spaces'],
      reservedSpaces: json['reserved_spaces'],
      occupiedSpaces: json['occupied_spaces'],
    );
  }

  bool get isClosed => freeSpaces == 0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'country': country,
        'city': city,
        'street_name': streetName,
        'name_kz': nameKz,
        'description_kz': descriptionKz,
        'phone': phone,
        'location_coords': jsonEncode(locationCoords),
        'polygon_coordinates': jsonEncode(polygonCoordinates),
        'religion': religion,
        'burial_price': burialPrice,
        'status': status,
        'capacity': capacity,
        'free_spaces': freeSpaces,
        'reserved_spaces': reservedSpaces,
        'occupied_spaces': occupiedSpaces,
        'fetched_at': DateTime.now().toIso8601String(),
      };

  factory Cemetery.fromDbMap(Map<String, dynamic> map) {
    final locCoords = (jsonDecode(map['location_coords'] as String) as List)
        .map((e) => (e as num).toDouble())
        .toList();
    final polyCoords =
        (jsonDecode(map['polygon_coordinates'] as String) as List)
            .map((row) =>
                (row as List).map((e) => (e as num).toDouble()).toList())
            .toList();

    return Cemetery(
      id: map['id'] as int,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      country: map['country'] as String? ?? '',
      city: map['city'] as String? ?? '',
      streetName: map['street_name'] as String? ?? '',
      nameKz: map['name_kz'] as String?,
      descriptionKz: map['description_kz'] as String?,
      phone: map['phone'] as String? ?? '',
      locationCoords: locCoords,
      polygonCoordinates: polyCoords,
      religion: map['religion'] as String? ?? '',
      burialPrice: map['burial_price'] as int? ?? 0,
      status: map['status'] as String? ?? 'active',
      capacity: map['capacity'] as int? ?? 0,
      freeSpaces: map['free_spaces'] as int? ?? 0,
      reservedSpaces: map['reserved_spaces'] as int? ?? 0,
      occupiedSpaces: map['occupied_spaces'] as int? ?? 0,
    );
  }
}
