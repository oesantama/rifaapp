/// Sale / contact channel from the SuperAdmin's master list (Facebook, WhatsApp, ...).
class SaleChannel {
  final String id;
  final String name;
  final String color; // #RRGGBB
  final String icon; // key from SaleChannels.iconKeys
  final bool active;
  final int order;

  const SaleChannel({
    required this.id,
    required this.name,
    this.color = '#64748B',
    this.icon = 'more',
    this.active = true,
    this.order = 0,
  });

  factory SaleChannel.fromJson(Map<String, dynamic> json) => SaleChannel(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        color: json['color'] ?? '#64748B',
        icon: json['icon'] ?? 'more',
        active: json['active'] != false,
        order: (json['order'] as num?)?.toInt() ?? 0,
      );
}
