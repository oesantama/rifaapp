// Responsive layout regression test: logs in as each role (superadmin, admin, asesor),
// renders every tab and the main dialogs at phone size (360x760) and desktop size
// (1280x800) with mocked API data, and fails on any overflow/layout error.
// Uses Noto Sans (Fedora: /usr/share/fonts/google-noto) for realistic text widths.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rifaapp/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

final overflows = <String>[];

final _companies = [
  {
    'id': 'comp-1', 'name': 'contruexito', 'code': 'EMP01', 'status': 'ACTIVA', 'adminUsername': 'william', 'adminPassword': '1234',
    'adminName': 'WILLIAM SANTAMARIA', 'adminEmail': 'william@santamaria.com', 'createdAt': '2026-09-29T19:54:13.535Z',
    'adminsCount': 1, 'admins': [{'name': 'WILLIAM SANTAMARIA', 'username': 'william', 'email': 'william@santamaria.com', 'password': '1234'}],
    'rafflesCount': 1, 'raffles': [], 'advisorsCount': 1, 'advisors': [],
  },
  {
    'id': 'comp-2', 'name': 'marisol y edgar distribuciones del norte', 'code': 'SANT-01', 'status': 'INACTIVA', 'adminUsername': 'marisol',
    'adminPassword': '12345678', 'adminName': 'marisol santamaria', 'adminEmail': 'marisol.santamaria.larga@gmail.com',
    'createdAt': '2026-09-29T19:54:13.535Z', 'adminsCount': 1, 'admins': [], 'rafflesCount': 0, 'raffles': [], 'advisorsCount': 0, 'advisors': [],
  },
];
final _raffle = {
  'id': 'raf-1', 'companyId': 'comp-1', 'title': 'Gran rifa de una pizza italiana', 'description': 'se entrega con dos cocacolas',
  'mainDrawDate': '2026-12-28T00:00:00.000', 'weeklyPrizesStartDate': '2026-09-29T00:00:00.000', 'digits': 2, 'totalTickets': 25,
  'totalNumbers': 100, 'opportunitiesPerTicket': 4, 'ticketPrice': 5000, 'status': 'ACTIVA', 'commissionType': 'PORCENTAJE',
  'commissionValue': 10, 'lotteryName': 'Lotería de Medellín', 'hasWeeklyDraws': true, 'weeklyDrawDay': 'Viernes',
  'weeklyPrizes': [], 'assignedAdvisorIds': ['adv-1'], 'createdAt': '2026-09-29T19:54:13.535Z',
};
final _advisor = {
  'id': 'adv-1', 'companyId': 'comp-1', 'name': 'Carlos Andrés Mendoza Rodríguez', 'phone': '1121837405', 'code': '1121837405',
  'username': 'carlos', 'email': 'carlos.mendoza@correo.com', 'password': '1234', 'mode': 'ASSIGNED',
  'assignedTicketRanges': ['1-15'], 'status': 'ACTIVO', 'createdAt': '2026-09-29T19:54:13.535Z',
  'totalSold': 3, 'totalCollected': 15000, 'totalConfirmed': 5000, 'pendingTurnIn': 10000, 'totalTicketsCount': 15,
};
List<Map<String, dynamic>> _tickets() => List.generate(25, (i) {
      final n = i + 1;
      final status = n == 1 ? 'PAGADA' : (n == 2 ? 'ABONO_PARCIAL' : (n == 3 ? 'RESERVADA' : 'DISPONIBLE'));
      return {
        'id': 'tk-$n', 'raffleId': 'raf-1', 'ticketNumber': n,
        'numbers': List.generate(4, (k) => ((n - 1) + k * 25).toString().padLeft(2, '0')),
        'status': status, 'buyerName': status == 'DISPONIBLE' ? '' : 'María Fernanda Gómez', 'buyerPhone': status == 'DISPONIBLE' ? '' : '3114445566',
        'advisorId': status == 'DISPONIBLE' ? '' : 'adv-1', 'advisorName': status == 'DISPONIBLE' ? '' : 'Carlos Andrés Mendoza Rodríguez',
        'totalPaid': n == 1 ? 5000 : (n == 2 ? 2000 : 0), 'price': 5000, 'confirmedByAdmin': n == 1,
        'verificationCode': n <= 3 ? 'M22L8-EAQ${n}B' : null,
        'saleChannel': n == 1 ? 'WhatsApp' : (n == 2 ? 'Voz a voz' : (n == 3 ? 'Facebook' : '')),
        'abonos': n <= 2 ? [{'id': 'ab-$n', 'amount': n == 1 ? 5000 : 2000, 'date': '2026-09-28T10:00:00.000', 'sellerId': 'adv-1', 'sellerName': 'Carlos'}] : [],
        'auditLogs': [],
      };
    });
final _winner = {
  'id': 'win-1', 'raffleId': 'raf-1', 'drawName': 'Sorteo semanal #1', 'drawDate': '2026-09-26T00:00:00.000', 'lotteryName': 'Lotería de Medellín',
  'winningNumber': '26', 'ticketNumber': 2, 'buyerName': 'María Fernanda Gómez', 'buyerPhone': '3114445566', 'advisorName': 'Carlos Mendoza',
  'isWinner': true, 'prizeAmount': 100000, 'basePrizeAmount': 100000, 'totalPrizePaid': 100000, 'status': 'PAGADO', 'accumulated': false,
  'createdAt': '2026-09-26T00:00:00.000',
};

final mockClient = MockClient((req) async {
  final path = req.url.path.replaceFirst('/api', '');
  Object body;
  if (path == '/auth/login') {
    // Server-side login: role derived from the user name used by each test
    final creds = jsonDecode(req.body) as Map<String, dynamic>;
    final username = creds['username'];
    final role = username == 'superadmin' ? 'superadmin' : (creds['role'] == 'asesor' ? 'asesor' : 'admin');
    body = {
      'token': 'test-token',
      'expiresAt': '2099-01-01T00:00:00.000Z',
      'user': {
        'role': role,
        'id': role == 'asesor' ? 'adv-1' : 'comp-1',
        'name': role == 'asesor' ? _advisor['name'] : 'WILLIAM SANTAMARIA',
        'email': 'test@rifamaster.com',
        'username': username,
        'companyId': role == 'superadmin' ? null : 'comp-1',
        'companyName': role == 'superadmin' ? '' : 'contruexito',
        'mustChangePassword': false,
        if (role == 'asesor') 'advisor': _advisor,
      },
    };
  } else if (req.method != 'GET') {
    body = {};
  } else if (path == '/companies') {
    body = _companies;
  } else if (path == '/raffles') {
    body = [_raffle];
  } else if (path == '/tickets') {
    body = _tickets();
  } else if (path == '/advisors') {
    body = [_advisor];
  } else if (path == '/winners') {
    body = [_winner];
  } else if (path == '/audit/voids') {
    body = [
      {'type': 'VENTA', 'date': '2026-09-30T10:00:00Z', 'by': 'WILLIAM SANTAMARIA', 'reason': 'Venta registrada en el número equivocado por el asesor',
        'raffleTitle': 'Gran rifa', 'numbers': ['66'], 'buyerName': 'María Fernanda Gómez', 'buyerPhone': '3114445566',
        'advisorName': 'Carlos Andrés Mendoza Rodríguez', 'saleChannel': 'WhatsApp', 'amount': 50000},
      {'type': 'ABONO', 'date': '2026-09-30T09:00:00Z', 'by': 'WILLIAM SANTAMARIA', 'reason': 'Abono registrado dos veces',
        'raffleTitle': 'Gran rifa', 'numbers': ['48'], 'buyerName': 'Julio Arvey Amaya', 'buyerPhone': '3229484689',
        'advisorName': 'edgar santamaria', 'saleChannel': '', 'amount': 50000},
    ];
  } else if (path == '/terms') {
    body = {'template': '1. La rifa {rifa} es organizada por {empresa}.', 'isDefault': true, 'defaultTemplate': '',
      'placeholders': [{'key': 'rifa', 'description': 'Nombre'}, {'key': 'empresa', 'description': 'Empresa'}, {'key': 'cifras_ganadoras', 'description': 'Cifras'}],
      'preview': '1. La rifa Gran rifa de una pizza italiana es organizada por contruexito.', 'previewRaffle': 'Gran rifa'};
  } else if (path == '/commissions') {
    body = {'advisors': [], 'totals': {}};
  } else {
    body = {};
  }
  return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
});


Future<void> loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    if (File(p).existsSync()) {
      loader.addFont(Future.value(ByteData.view(File(p).readAsBytesSync().buffer)));
    }
  }
  await loader.load();
}

Future<void> settle(WidgetTester tester, [int ms = 2500]) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump(Duration(milliseconds: ms ~/ 20));
  }
}

Future<void> login(WidgetTester tester, {required bool asesor, required String user, required String pass}) async {
  await tester.pumpWidget(const RifaApp());
  await settle(tester, 500);
  if (asesor) {
    await tester.tap(find.text('Asesor / Vendedor'));
    await tester.pump();
  }
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), user);
  await tester.enterText(fields.at(1), pass);
  await tester.tap(find.byType(ElevatedButton).last);
  await settle(tester);
}

Future<void> visitTabs(WidgetTester tester, String role) async {
  final nav = find.byType(BottomNavigationBar);
  expect(nav, findsOneWidget, reason: '$role: bottom nav missing (login failed?)');
  final items = tester.widget<BottomNavigationBar>(nav).items;
  for (final item in items) {
    overflows.add('--- $role / ${item.label}');
    await tester.tap(find.descendant(of: nav, matching: find.text(item.label!)));
    await settle(tester);
    // Scroll the main content to render everything
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isNotEmpty) {
      for (int i = 0; i < 6; i++) {
        await tester.drag(scrollables.first, const Offset(0, -500), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
  }
}


Future<void> goTab(WidgetTester tester, String label) async {
  final nav = find.byType(BottomNavigationBar);
  await tester.tap(find.descendant(of: nav, matching: find.text(label)));
  await settle(tester, 600);
}

/// Taps [target], records overflows under [label], then closes whatever route opened.
Future<void> openAndClose(WidgetTester tester, String label, Finder target) async {
  overflows.add('    [dialog] $label');
  if (target.evaluate().isEmpty) {
    overflows.add('      !! target not found');
    return;
  }
  await tester.ensureVisible(target.first);
  await tester.pump();
  await tester.tap(target.first, warnIfMissed: false);
  await settle(tester, 600);
  // Scroll inside the dialog to lay out everything
  final dialogScroll = find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable));
  if (dialogScroll.evaluate().isNotEmpty) {
    for (int i = 0; i < 4; i++) {
      await tester.drag(dialogScroll.first, const Offset(0, -400), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  final routeCtx = find.byType(Dialog).evaluate().isNotEmpty ? find.byType(Dialog).last : find.byType(BottomSheet);
  if (routeCtx.evaluate().isNotEmpty) {
    Navigator.of(tester.element(routeCtx.last)).pop();
    await settle(tester, 400);
  }
}

Future<void> openDialogs(WidgetTester tester, String role) async {
  overflows.add('--- $role / dialogs');
  if (role == 'superadmin') {
    await goTab(tester, 'Empresas');
    await openAndClose(tester, 'Nueva Empresa', find.text('Nueva Empresa'));
    await openAndClose(tester, 'Editar Empresa', find.byIcon(Icons.edit_note_rounded));
    await openAndClose(tester, 'Resumen Empresa', find.byIcon(Icons.analytics_rounded));
    return;
  }
  await goTab(tester, 'Inicio');
  if (role == 'admin') {
    await openAndClose(tester, 'Crear Sorteo (AppBar +)', find.byIcon(Icons.add_circle_outline));
    await openAndClose(tester, 'Perfil Admin', find.byIcon(Icons.admin_panel_settings));
    await openAndClose(tester, 'Gestionar Sorteo', find.text('Gestionar Sorteo'));
  }
  await goTab(tester, 'Boletas');
  await openAndClose(tester, 'Detalle Boleta', find.textContaining('N° 00 -'));
  await openAndClose(tester, 'Detalle Boleta disponible', find.textContaining('N° 03 -'));
  await openAndClose(tester, 'Imprimir Boleta', find.byIcon(Icons.print_outlined));
  await openAndClose(tester, 'Afiche 2D', find.byIcon(Icons.grid_on_rounded));
  if (role == 'admin') {
    await openAndClose(tester, 'Importar Excel', find.byIcon(Icons.file_upload_outlined));
    await goTab(tester, 'Asesores');
    await openAndClose(tester, 'Menu Nuevo', find.text('Nuevo'));
    await tester.tap(find.text('Nuevo'));
    await settle(tester, 400);
    await openAndClose(tester, 'Nuevo Asesor', find.text('Nuevo Asesor'));
    await tester.tap(find.text('Nuevo'));
    await settle(tester, 400);
    await openAndClose(tester, 'Nuevo Administrador', find.text('Nuevo Administrador'));
  }
}

List<String> _problemsSince(int start) =>
    overflows.sublist(start).where((l) => !l.startsWith('---') && !l.trimLeft().startsWith('[dialog]')).toList();

void main() {
  // Each test starts logged out (the app persists the session).
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    await loadFont('Roboto', ['/usr/share/fonts/google-noto/NotoSans-Regular.ttf', '/usr/share/fonts/google-noto/NotoSans-Bold.ttf']);
  });

  void setup(WidgetTester tester) {
    tester.view.physicalSize = const Size(360 * 3, 760 * 3);
    tester.view.devicePixelRatio = 3;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      final lines = details.toString().split('\n');
      final where = lines.firstWhere((l) => l.contains('file://') || l.contains('.dart:'), orElse: () => '');
      overflows.add('${msg.split('\n').first}  @ ${where.trim()}');
    };
  }

  for (final role in [('superadmin', 'superadmin'), ('admin', 'william')]) {
    testWidgets('desktop layout ${role.$1}', (tester) async {
      final original = FlutterError.onError;
      final start = overflows.length;
      setup(tester);
      tester.view.physicalSize = const Size(1280 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2;
      try {
        await http.runWithClient(() async {
          overflows.add('--- DESKTOP ${role.$1} / login');
          await login(tester, asesor: false, user: role.$2, pass: '1234');
          final rail = find.byType(NavigationRail);
          final count = tester.widget<NavigationRail>(rail).destinations.length;
          for (int i = 0; i < count; i++) {
            overflows.add('--- DESKTOP ${role.$1} / tab $i');
            await tester.tap(find.descendant(of: rail, matching: find.byType(Icon)).at(i));
            await settle(tester, 600);
          }
        }, () => mockClient);
      } finally {
        FlutterError.onError = original;
      }
      expect(_problemsSince(start), isEmpty);
    });
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('\n===== LAYOUT REPORT =====\n${overflows.join('\n')}\n=========================');
  });

  for (final role in [
    ('superadmin', false, 'superadmin', '1234'),
    ('admin', false, 'william', '1234'),
    ('asesor', true, '1121837405', '1234'),
  ]) {
    testWidgets('mobile layout ${role.$1}', (tester) async {
      final original = FlutterError.onError;
      final start = overflows.length;
      setup(tester);
      try {
        await http.runWithClient(() async {
          overflows.add('--- ${role.$1} / login');
          await login(tester, asesor: role.$2, user: role.$3, pass: role.$4);
          await visitTabs(tester, role.$1);
          await openDialogs(tester, role.$1);
        }, () => mockClient);
      } finally {
        FlutterError.onError = original;
      }
      expect(_problemsSince(start), isEmpty);
    });
  }
}
