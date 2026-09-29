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
  });

  factory Company.fromJson(Map<String, dynamic> json) {
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
      };
}
