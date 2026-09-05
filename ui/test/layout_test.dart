import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/theme/accent_color_controller.dart';
import 'package:ui/theme/app_theme.dart';
import 'package:ui/widgets/generation_controls.dart';
import 'package:ui/widgets/top_bar.dart';

/// The toolbar and the generation bar lay out fixed-width children in a Row,
/// so a narrow window silently overflowed them. Both now collapse to a compact
/// form; these pin that behaviour at the widths where it matters.
Widget _host(Widget child, double width) {
  return MaterialApp(
    theme: buildAppTheme(kDefaultAccent),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  // 360 is below both compact breakpoints, 470 sits exactly on the generation
  // bar's, and 1200 is a normal maximised window.
  const widths = <double>[360, 420, 470, 800, 1200];

  group('TopBar does not overflow', () {
    for (final width in widths) {
      testWidgets('at ${width}px', (WidgetTester tester) async {
        await tester.pumpWidget(
          _host(
            TopBar(
              isVaultLoading: false,
              showDebugConsole: false,
              accentController: AccentColorController(),
              onScrape: () {},
              onOpenVault: () {},
              onToggleDebugConsole: () {},
            ),
            width,
          ),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('GenerationControls does not overflow', () {
    for (final width in widths) {
      testWidgets('at ${width}px collapsed', (WidgetTester tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _host(
            GenerationControls(
              instructionsController: controller,
              mode: 'tutor',
              modePulseToken: 0,
              isGenerating: false,
              isExpanded: false,
              attachedFileName: null,
              onModeChanged: (_) {},
              onGenerate: () {},
              onToggleExpanded: () {},
              onPickAttachment: () {},
              onClearAttachment: () {},
            ),
            width,
          ),
        );

        expect(tester.takeException(), isNull);
      });

      testWidgets('at ${width}px expanded', (WidgetTester tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _host(
            GenerationControls(
              instructionsController: controller,
              mode: 'ghostwriter',
              modePulseToken: 1,
              isGenerating: true,
              isExpanded: true,
              attachedFileName: 'a-fairly-long-attachment-name.pdf',
              onModeChanged: (_) {},
              onGenerate: () {},
              onToggleExpanded: () {},
              onPickAttachment: () {},
              onClearAttachment: () {},
            ),
            width,
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
      });
    }
  });
}
