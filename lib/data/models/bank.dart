/// Bank or wallet from the SuperAdmin's master list (Nequi, Bancolombia, ...).
class Bank {
  final String id;
  final String name;
  final bool active;

  const Bank({required this.id, required this.name, this.active = true});

  factory Bank.fromJson(Map<String, dynamic> json) => Bank(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        active: json['active'] != false,
      );
}
