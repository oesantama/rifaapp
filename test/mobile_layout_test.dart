// Temporary layout check: renders every screen at 360x760 (Galaxy S10 in DevTools)
// against the live backend and reports RenderFlex overflows.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rifaapp/main.dart';

final overflows = <String>[];

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
  await tester.runAsync(() => Future.delayed(Duration(milliseconds: ms)));
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
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

void main() {
  setUpAll(() async {
    HttpOverrides.global = null;
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

  tearDownAll(() {
    // ignore: avoid_print
    print('\n===== LAYOUT REPORT =====\n${overflows.join('\n')}\n=========================');
  });

  for (final role in [
    ('superadmin', false, 'superadmin', '1234'),
    ('admin', false, 'william', '1234'),
    ('asesor', true, const String.fromEnvironment('ADV', defaultValue: 'ADV01'), '1234'),
  ]) {
    testWidgets('mobile layout ${role.$1}', (tester) async {
      setup(tester);
      overflows.add('--- ${role.$1} / login');
      await login(tester, asesor: role.$2, user: role.$3, pass: role.$4);
      await visitTabs(tester, role.$1);
      FlutterError.onError = FlutterError.presentError;
    });
  }
}
