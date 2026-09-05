import 'package:flutter_test/flutter_test.dart';

import 'package:ui/main.dart';
import 'package:ui/theme/accent_color_controller.dart';

void main() {
  testWidgets('MB2AI app shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      Mb2AiApp(accentController: AccentColorController()),
    );
    expect(find.text('Tasks'), findsOneWidget);
  });
}
