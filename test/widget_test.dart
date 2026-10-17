import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  testWidgets('customer home renders in Arabic', (tester) async {
    await tester.pumpWidget(const MaaCustomerApp(firebaseReady: false));
    await tester.pumpAndSettle();
    expect(find.text('التوصيل إلى'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
  });
}
