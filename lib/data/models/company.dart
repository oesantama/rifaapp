class Company {
  final String id;
  final String name;
  final String code;
  final String status; // ACTIVA, INACTIVA
  final String adminUsername;
  final String adminPassword;
  final String adminName;
  final String adminEmail;
  final String createdAt;
  final int adminsCount;
  final List<Map<String, dynamic>> admins;
  final int rafflesCount;
  final List<Map<String, dynamic>> raffles;
  final int advisorsCount;
  final List<Map<String, dynamic>> advisors;

  Company({
    required this.id,
    required this.name,
    required this.code,
    required this.status,
    required this.adminUsername,
    required this.adminPassword,
    required this.adminName,
    required this.adminEmail,
    required this.createdAt,
    this.adminsCount = 1,
    this.admins = const [],
    this.rafflesCount = 0,
    this.raffles = const [],
    this.advisorsCount = 0,
    this.advisors = const [],
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    final rawAdmins = json['admins'] is List
        ? List<Map<String, dynamic>>.from((json['admins'] as List).map((x) => Map<String, dynamic>.from(x)))
        : <Map<String, dynamic>>[];
    final rawRaffles = json['raffles'] is List
        ? List<Map<String, dynamic>>.from((json['raffles'] as List).map((x) => Map<String, dynamic>.from(x)))
        : <Map<String, dynamic>>[];
    final rawAdvisors = json['advisors'] is List
        ? List<Map<String, dynamic>>.from((json['advisors'] as List).map((x) => Map<String, dynamic>.from(x)))
        : <Map<String, dynamic>>[];

    return Company(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      status: json['status'] ?? 'ACTIVA',
      adminUsername: json['adminUsername'] ?? 'ADMIN',
      adminPassword: json['adminPassword'] ?? '123',
      adminName: json['adminName'] ?? 'Administrador',
      adminEmail: json['adminEmail'] ?? '',
      createdAt: json['createdAt'] ?? '',
      adminsCount: json['adminsCount'] ?? (rawAdmins.isNotEmpty ? rawAdmins.length : 1),
      admins: rawAdmins.isNotEmpty
          ? rawAdmins
          : [
              {
                'name': json['adminName'] ?? 'Administrador General',
                'username': json['adminUsername'] ?? 'ADMIN',
                'email': json['adminEmail'] ?? '',
                'password': json['adminPassword'] ?? '123',
                'status': 'ACTIVO',
              }
            ],
      rafflesCount: json['rafflesCount'] ?? rawRaffles.length,
      raffles: rawRaffles,
      advisorsCount: json['advisorsCount'] ?? rawAdvisors.length,
      advisors: rawAdvisors,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'status': status,
        'adminUsername': adminUsername,
        'adminPassword': adminPassword,
        'adminName': adminName,
        'adminEmail': adminEmail,
        'createdAt': createdAt,
        'adminsCount': adminsCount,
        'admins': admins,
        'rafflesCount': rafflesCount,
        'raffles': raffles,
        'advisorsCount': advisorsCount,
        'advisors': advisors,
      };
}
