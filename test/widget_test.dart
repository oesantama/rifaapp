import 'package:flutter_test/flutter_test.dart';
import 'package:rifaapp/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RifaApp());
    expect(find.byType(RifaApp), findsOneWidget);
  });
}
