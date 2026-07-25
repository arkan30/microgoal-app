import 'package:flutter_test/flutter_test.dart';
import 'package:microgoal_app/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MicroGoalApp());
    expect(find.text('میکروهدف'), findsWidgets);
  });
}
