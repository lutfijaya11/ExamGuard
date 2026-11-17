import 'package:flutter_test/flutter_test.dart';
import 'package:exambroku_android/main.dart';

void main() {
  testWidgets('ExamBroKuApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ExamBroKuApp());
    expect(find.byType(ExamBroKuApp), findsOneWidget);
  });
}
