import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/main.dart';

void main() {
  testWidgets('app shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const LgMobileApp());

    expect(find.text('LG 가전 진단 챗봇'), findsOneWidget);
    expect(find.text('어떤 증상을 진단해볼까요?'), findsOneWidget);
  });
}
