import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bluechat/main.dart';

void main() {
  testWidgets('BlueChat App Smoke Test', (WidgetTester tester) async {
    // Initialize mock SharedPreferences values
    SharedPreferences.setMockInitialValues({});
    
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BlueChatApp());
    await tester.pumpAndSettle();

    // Verify that the setup screen text is found.
    expect(find.text('Welcome to BlueChat'), findsOneWidget);
  });
}
