import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:samirnet_videos/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SamirNet app shows the home screen and navigation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SamirNetApp());
    await tester.pumpAndSettle();
    expect(find.text('كل فيديوهاتك في مكان واحد'), findsOneWidget);
    expect(find.text('إرسال رابط'), findsWidgets);
    expect(find.text('البحث'), findsNWidgets(2));
  });
}
