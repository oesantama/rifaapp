import 'package:flutter/material.dart';
import 'package:rifaapp/ui/core/theme.dart';

/// Marca que se dibuja sobre los números apartados o vendidos del afiche. Puede ser un icono de Material o un emoji.
class PosterMarker {
  final String key;
  final String label;
  final String category;
  final IconData? icon;
  final String? emoji;

  const PosterMarker(this.key, this.label, this.category, {this.icon, this.emoji});

  /// Dibuja la marca en [size] con [color] (los emojis llevan su propio color).
  Widget build(double size, Color color) {
    if (emoji != null) return Text(emoji!, style: TextStyle(fontSize: size * 0.9, height: 1));
    return Icon(icon, size: size, color: color);
  }
}

const String kDefaultMarkerKey = 'close';

const List<String> kMarkerCategories = ['Marcas', 'Carros y motos', 'Aire y mar', 'Casas', 'Balones y deportes', 'Premios y dinero', 'Fiesta', 'Velas y luz', 'Tecnología', 'Naturaleza', 'Otros'];

const List<PosterMarker> kPosterMarkers = [
  // Marcas
  PosterMarker('close', 'X', 'Marcas', icon: Icons.close),
  PosterMarker('check', 'Visto bueno', 'Marcas', icon: Icons.check),
  PosterMarker('check_circle', 'Visto en círculo', 'Marcas', icon: Icons.check_circle),
  PosterMarker('cancel', 'X en círculo', 'Marcas', icon: Icons.cancel),
  PosterMarker('block', 'Prohibido', 'Marcas', icon: Icons.block),
  PosterMarker('circle', 'Círculo', 'Marcas', icon: Icons.circle),
  PosterMarker('star', 'Estrella', 'Marcas', icon: Icons.star),
  PosterMarker('favorite', 'Corazón', 'Marcas', icon: Icons.favorite),
  PosterMarker('flag', 'Bandera', 'Marcas', icon: Icons.flag),
  PosterMarker('bookmark', 'Marcador', 'Marcas', icon: Icons.bookmark),
  PosterMarker('lock', 'Candado', 'Marcas', icon: Icons.lock),
  PosterMarker('thumb_up', 'Me gusta', 'Marcas', icon: Icons.thumb_up),
  PosterMarker('verified', 'Verificado', 'Marcas', icon: Icons.verified),
  PosterMarker('push_pin', 'Chincheta', 'Marcas', icon: Icons.push_pin),
  PosterMarker('square', 'Cuadro', 'Marcas', icon: Icons.square),
  PosterMarker('diamond_shape', 'Rombo', 'Marcas', icon: Icons.diamond),
  PosterMarker('hexagon', 'Hexágono', 'Marcas', icon: Icons.hexagon),
  PosterMarker('change_history', 'Triángulo', 'Marcas', icon: Icons.change_history),

  // Carros y motos
  PosterMarker('car', 'Carro', 'Carros y motos', icon: Icons.directions_car),
  PosterMarker('car_filled', 'Carro (lleno)', 'Carros y motos', icon: Icons.directions_car_filled),
  PosterMarker('electric_car', 'Carro eléctrico', 'Carros y motos', icon: Icons.electric_car),
  PosterMarker('taxi', 'Taxi', 'Carros y motos', icon: Icons.local_taxi),
  PosterMarker('suv', 'Camioneta', 'Carros y motos', icon: Icons.airport_shuttle),
  PosterMarker('truck', 'Camión', 'Carros y motos', icon: Icons.local_shipping),
  PosterMarker('bus', 'Bus', 'Carros y motos', icon: Icons.directions_bus),
  PosterMarker('moto', 'Moto', 'Carros y motos', icon: Icons.two_wheeler),
  PosterMarker('bike', 'Bicicleta', 'Carros y motos', icon: Icons.pedal_bike),
  PosterMarker('scooter', 'Scooter', 'Carros y motos', icon: Icons.electric_scooter),
  PosterMarker('moped', 'Motocarro', 'Carros y motos', icon: Icons.moped),
  PosterMarker('tractor', 'Tractor', 'Carros y motos', emoji: '🚜'),
  PosterMarker('race_car', 'Carro de carreras', 'Carros y motos', emoji: '🏎️'),
  PosterMarker('pickup', 'Camioneta pick-up', 'Carros y motos', emoji: '🛻'),
  PosterMarker('motorcycle_emoji', 'Moto deportiva', 'Carros y motos', emoji: '🏍️'),

  // Aire y mar
  PosterMarker('plane', 'Avión', 'Aire y mar', icon: Icons.flight),
  PosterMarker('helicopter', 'Helicóptero', 'Aire y mar', emoji: '🚁'),
  PosterMarker('sailboat', 'Velero', 'Aire y mar', icon: Icons.sailing),
  PosterMarker('boat', 'Lancha', 'Aire y mar', icon: Icons.directions_boat),
  PosterMarker('ferry', 'Barco', 'Aire y mar', icon: Icons.directions_ferry),
  PosterMarker('rocket', 'Cohete', 'Aire y mar', icon: Icons.rocket_launch),
  PosterMarker('train', 'Tren', 'Aire y mar', icon: Icons.train),
  PosterMarker('anchor', 'Ancla', 'Aire y mar', emoji: '⚓'),

  // Casas
  PosterMarker('home', 'Casa', 'Casas', icon: Icons.home),
  PosterMarker('house', 'Casa (techo)', 'Casas', icon: Icons.house),
  PosterMarker('cottage', 'Cabaña', 'Casas', icon: Icons.cottage),
  PosterMarker('villa', 'Villa', 'Casas', icon: Icons.villa),
  PosterMarker('cabin', 'Cabaña de campo', 'Casas', icon: Icons.cabin),
  PosterMarker('apartment', 'Apartamento', 'Casas', icon: Icons.apartment),
  PosterMarker('business', 'Edificio', 'Casas', icon: Icons.business),
  PosterMarker('warehouse', 'Bodega', 'Casas', icon: Icons.warehouse),
  PosterMarker('store', 'Local / tienda', 'Casas', icon: Icons.storefront),
  PosterMarker('holiday_village', 'Casa de campo', 'Casas', icon: Icons.holiday_village),
  PosterMarker('real_estate', 'Lote / agente', 'Casas', icon: Icons.real_estate_agent),
  PosterMarker('key', 'Llave', 'Casas', icon: Icons.key),
  PosterMarker('door', 'Puerta', 'Casas', icon: Icons.door_front_door),
  PosterMarker('house_emoji', 'Casa con jardín', 'Casas', emoji: '🏡'),

  // Balones y deportes
  PosterMarker('soccer', 'Balón de fútbol', 'Balones y deportes', icon: Icons.sports_soccer),
  PosterMarker('basketball', 'Balón de baloncesto', 'Balones y deportes', icon: Icons.sports_basketball),
  PosterMarker('volleyball', 'Balón de voleibol', 'Balones y deportes', icon: Icons.sports_volleyball),
  PosterMarker('football', 'Balón americano', 'Balones y deportes', icon: Icons.sports_football),
  PosterMarker('baseball', 'Béisbol', 'Balones y deportes', icon: Icons.sports_baseball),
  PosterMarker('tennis', 'Tenis', 'Balones y deportes', icon: Icons.sports_tennis),
  PosterMarker('rugby', 'Rugby', 'Balones y deportes', icon: Icons.sports_rugby),
  PosterMarker('handball', 'Balonmano', 'Balones y deportes', icon: Icons.sports_handball),
  PosterMarker('golf', 'Golf', 'Balones y deportes', icon: Icons.sports_golf),
  PosterMarker('cricket', 'Cricket', 'Balones y deportes', icon: Icons.sports_cricket),
  PosterMarker('hockey', 'Hockey', 'Balones y deportes', icon: Icons.sports_hockey),
  PosterMarker('mma', 'Boxeo / MMA', 'Balones y deportes', icon: Icons.sports_mma),
  PosterMarker('gym', 'Pesas', 'Balones y deportes', icon: Icons.fitness_center),
  PosterMarker('sport', 'Deportes', 'Balones y deportes', icon: Icons.sports),
  PosterMarker('trophy', 'Trofeo', 'Balones y deportes', icon: Icons.emoji_events),
  PosterMarker('medal', 'Medalla', 'Balones y deportes', icon: Icons.military_tech),
  PosterMarker('billiard', 'Billar', 'Balones y deportes', emoji: '🎱'),
  PosterMarker('bowling', 'Bolos', 'Balones y deportes', emoji: '🎳'),

  // Premios y dinero
  PosterMarker('money', 'Dinero', 'Premios y dinero', icon: Icons.attach_money),
  PosterMarker('paid', 'Pagado', 'Premios y dinero', icon: Icons.paid),
  PosterMarker('savings', 'Alcancía', 'Premios y dinero', icon: Icons.savings),
  PosterMarker('wallet', 'Billetera', 'Premios y dinero', icon: Icons.account_balance_wallet),
  PosterMarker('payments', 'Billetes', 'Premios y dinero', icon: Icons.payments),
  PosterMarker('diamond', 'Diamante', 'Premios y dinero', icon: Icons.diamond_outlined),
  PosterMarker('workspace_premium', 'Premio', 'Premios y dinero', icon: Icons.workspace_premium),
  PosterMarker('gift', 'Regalo', 'Premios y dinero', icon: Icons.redeem),
  PosterMarker('card_giftcard', 'Tarjeta de regalo', 'Premios y dinero', icon: Icons.card_giftcard),
  PosterMarker('confirmation', 'Boleto', 'Premios y dinero', icon: Icons.confirmation_number),
  PosterMarker('money_bag', 'Bolsa de dinero', 'Premios y dinero', emoji: '💰'),
  PosterMarker('clover', 'Trébol de la suerte', 'Premios y dinero', emoji: '🍀'),
  PosterMarker('dice', 'Dado', 'Premios y dinero', emoji: '🎲'),

  // Fiesta
  PosterMarker('celebration', 'Celebración', 'Fiesta', icon: Icons.celebration),
  PosterMarker('cake', 'Torta', 'Fiesta', icon: Icons.cake),
  PosterMarker('party', 'Fiesta', 'Fiesta', icon: Icons.party_mode),
  PosterMarker('music', 'Música', 'Fiesta', icon: Icons.music_note),
  PosterMarker('mic', 'Micrófono', 'Fiesta', icon: Icons.mic),
  PosterMarker('beer', 'Cerveza', 'Fiesta', icon: Icons.sports_bar),
  PosterMarker('wine', 'Copa', 'Fiesta', icon: Icons.wine_bar),
  PosterMarker('cocktail', 'Cóctel', 'Fiesta', icon: Icons.local_bar),
  PosterMarker('pizza', 'Pizza', 'Fiesta', icon: Icons.local_pizza),
  PosterMarker('restaurant', 'Comida', 'Fiesta', icon: Icons.restaurant),
  PosterMarker('fireworks', 'Fuegos artificiales', 'Fiesta', emoji: '🎆'),
  PosterMarker('confetti', 'Confeti', 'Fiesta', emoji: '🎉'),
  PosterMarker('balloon', 'Globo', 'Fiesta', emoji: '🎈'),
  PosterMarker('guitar', 'Guitarra', 'Fiesta', emoji: '🎸'),

  // Velas y luz
  PosterMarker('candle', 'Vela', 'Velas y luz', emoji: '🕯️'),
  PosterMarker('lamp', 'Lámpara de aceite', 'Velas y luz', emoji: '🪔'),
  PosterMarker('fire', 'Llama', 'Velas y luz', icon: Icons.local_fire_department),
  PosterMarker('whatshot', 'Fuego', 'Velas y luz', icon: Icons.whatshot),
  PosterMarker('bulb', 'Bombillo', 'Velas y luz', icon: Icons.lightbulb),
  PosterMarker('flare', 'Destello', 'Velas y luz', icon: Icons.flare),
  PosterMarker('bolt', 'Rayo', 'Velas y luz', icon: Icons.bolt),
  PosterMarker('sun', 'Sol', 'Velas y luz', icon: Icons.wb_sunny),
  PosterMarker('moon', 'Luna', 'Velas y luz', icon: Icons.nightlight_round),
  PosterMarker('auto_awesome', 'Brillos', 'Velas y luz', icon: Icons.auto_awesome),
  PosterMarker('cross', 'Cruz', 'Velas y luz', emoji: '✝️'),
  PosterMarker('pray', 'Oración', 'Velas y luz', emoji: '🙏'),

  // Tecnología
  PosterMarker('phone', 'Celular', 'Tecnología', icon: Icons.smartphone),
  PosterMarker('laptop', 'Portátil', 'Tecnología', icon: Icons.laptop),
  PosterMarker('tv', 'Televisor', 'Tecnología', icon: Icons.tv),
  PosterMarker('tablet', 'Tablet', 'Tecnología', icon: Icons.tablet_mac),
  PosterMarker('watch', 'Reloj', 'Tecnología', icon: Icons.watch),
  PosterMarker('headphones', 'Audífonos', 'Tecnología', icon: Icons.headphones),
  PosterMarker('camera', 'Cámara', 'Tecnología', icon: Icons.photo_camera),
  PosterMarker('gamepad', 'Videojuegos', 'Tecnología', icon: Icons.sports_esports),
  PosterMarker('kitchen', 'Nevera', 'Tecnología', icon: Icons.kitchen),
  PosterMarker('washer', 'Lavadora', 'Tecnología', icon: Icons.local_laundry_service),
  PosterMarker('speaker', 'Parlante', 'Tecnología', icon: Icons.speaker),
  PosterMarker('computer', 'Computador', 'Tecnología', icon: Icons.desktop_windows),

  // Naturaleza
  PosterMarker('pets', 'Mascota', 'Naturaleza', icon: Icons.pets),
  PosterMarker('flower', 'Flor', 'Naturaleza', icon: Icons.local_florist),
  PosterMarker('tree', 'Árbol', 'Naturaleza', icon: Icons.park),
  PosterMarker('spa', 'Hoja', 'Naturaleza', icon: Icons.spa),
  PosterMarker('water', 'Gota', 'Naturaleza', icon: Icons.water_drop),
  PosterMarker('cloud', 'Nube', 'Naturaleza', icon: Icons.cloud),
  PosterMarker('terrain', 'Montaña', 'Naturaleza', icon: Icons.terrain),
  PosterMarker('horse', 'Caballo', 'Naturaleza', emoji: '🐎'),
  PosterMarker('cow', 'Vaca', 'Naturaleza', emoji: '🐄'),
  PosterMarker('rooster', 'Gallo', 'Naturaleza', emoji: '🐓'),
  PosterMarker('sunflower', 'Girasol', 'Naturaleza', emoji: '🌻'),

  // Otros
  PosterMarker('beach', 'Playa', 'Otros', icon: Icons.beach_access),
  PosterMarker('luggage', 'Viaje', 'Otros', icon: Icons.luggage),
  PosterMarker('hotel', 'Hotel', 'Otros', icon: Icons.hotel),
  PosterMarker('school', 'Educación', 'Otros', icon: Icons.school),
  PosterMarker('health', 'Salud', 'Otros', icon: Icons.favorite_border),
  PosterMarker('shopping', 'Compras', 'Otros', icon: Icons.shopping_bag),
  PosterMarker('tool', 'Herramientas', 'Otros', icon: Icons.build),
  PosterMarker('palette', 'Arte', 'Otros', icon: Icons.palette),
  PosterMarker('book', 'Libro', 'Otros', icon: Icons.menu_book),
  PosterMarker('crown', 'Corona', 'Otros', emoji: '👑'),
  PosterMarker('smile', 'Sonrisa', 'Otros', emoji: '😀'),
  PosterMarker('fire_emoji', 'Fuego (emoji)', 'Otros', emoji: '🔥'),
];

PosterMarker posterMarkerByKey(String? key) =>
    kPosterMarkers.firstWhere((m) => m.key == key, orElse: () => kPosterMarkers.first);

/// Selector con buscador y categorías: devuelve la clave del icono elegido o null si se cierra sin elegir.
Future<String?> pickPosterMarker(BuildContext context, {required String current, String title = 'Elegir icono'}) {
  String query = '';
  String category = 'Todos';
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        final q = query.trim().toLowerCase();
        final items = kPosterMarkers.where((m) => (category == 'Todos' || m.category == category) && (q.isEmpty || m.label.toLowerCase().contains(q))).toList();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.emoji_symbols, color: AppTheme.primaryBlue),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
            IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
          ]),
          content: SizedBox(
            width: 560,
            height: 480,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Buscar: carro, casa, balón, vela…', border: OutlineInputBorder()),
                  onChanged: (v) => setD(() => query = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final c in ['Todos', ...kMarkerCategories])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(label: Text(c, style: const TextStyle(fontSize: 11.5)), selected: category == c, onSelected: (_) => setD(() => category = c)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('Sin resultados', style: TextStyle(color: Colors.grey)))
                      : GridView.builder(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 92, mainAxisExtent: 82, crossAxisSpacing: 6, mainAxisSpacing: 6),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final m = items[i];
                            final selected = m.key == current;
                            return InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => Navigator.pop(ctx, m.key),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: selected ? AppTheme.primaryBlue.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: selected ? AppTheme.primaryBlue : Colors.grey.withValues(alpha: 0.25), width: selected ? 2 : 1),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    m.build(28, Colors.black87),
                                    const SizedBox(height: 4),
                                    Text(m.label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, height: 1.1)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
