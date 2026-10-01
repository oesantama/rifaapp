/// Lottery from the SuperAdmin's master list (Lotería de Boyacá, Lotería de Medellín, ...).
class Lottery {
  final String id;
  final String name;
  final bool active;

  const Lottery({required this.id, required this.name, this.active = true});

  factory Lottery.fromJson(Map<String, dynamic> json) => Lottery(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        active: json['active'] != false,
      );
}
