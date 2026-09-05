import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ui/services/api_service.dart';
import 'package:ui/theme/accent_color_controller.dart';
import 'package:ui/theme/app_theme.dart';
import 'package:ui/widgets/task_card.dart';
import 'package:ui/widgets/top_bar.dart';

/// Exercises the interactive paths flutter test drives through the widget
/// tree directly, rather than through OS-level synthetic input.
void main() {
  group('Accent colour picker', () {
    testWidgets('opens on tap and shows every swatch', (tester) async {
      final controller = AccentColorController();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(controller.accent),
          home: Scaffold(
            body: TopBar(
              isVaultLoading: false,
              showDebugConsole: false,
              accentController: controller,
              onScrape: () {},
              onOpenVault: () {},
              onToggleDebugConsole: () {},
            ),
          ),
        ),
      );

      expect(find.byType(AlertDialog), findsNothing);

      // The swatch button carries no text, so find it by its tooltip.
      await tester.tap(find.byTooltip('Accent colour'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Accent Colour'), findsOneWidget);
      // Every configured swatch should render as a tappable circle.
      expect(find.byWidgetPredicate((w) => w is GestureDetector), findsWidgets);
    });

    testWidgets('picking a swatch updates and persists the controller', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AccentColorController();
      final initial = controller.accent;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(controller.accent),
          home: Scaffold(
            body: TopBar(
              isVaultLoading: false,
              showDebugConsole: false,
              accentController: controller,
              onScrape: () {},
              onOpenVault: () {},
              onToggleDebugConsole: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Accent colour'));
      await tester.pumpAndSettle();

      // Pick whichever swatch is not the current accent, so the test proves
      // an actual change rather than tapping a no-op.
      final targetColor = kAccentSwatches.firstWhere((c) => c != initial);
      final targetFinder = find.byTooltip(
        '#${targetColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      );
      expect(targetFinder, findsOneWidget);

      await tester.tap(targetFinder);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.accent, targetColor);

      // A fresh controller loading from storage should see the same choice -
      // this is the point of the setting: it survives a relaunch.
      final reloaded = AccentColorController();
      await reloaded.load();
      expect(reloaded.accent, targetColor);
    });
  });

  group('TaskCard identity colouring', () {
    TaskSummary task(String className) => TaskSummary(
      id: '1',
      title: 'A Task',
      className: className,
      dueDate: null,
      description: '',
    );

    testWidgets('the selected card borrows the accent colour', (tester) async {
      const accent = Color(0xFFEF4444);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(accent),
          home: Scaffold(
            body: TaskCard(
              task: task('IB MYP Mathematics (Grade 10)'),
              isActive: true,
              isSelected: true,
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(TaskCard),
          matching: find.byIcon(subjectIconFor('IB MYP Mathematics (Grade 10)')),
        ),
      );
      expect(icon.color, accent);
    });

    testWidgets('an unselected card keeps its subject colour regardless of accent', (
      tester,
    ) async {
      const className = 'IB MYP Mathematics (Grade 10)';
      final expected = subjectColorFor(className);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(const Color(0xFFEF4444)),
          home: Scaffold(
            body: TaskCard(task: task(className), isActive: true, isSelected: false),
          ),
        ),
      );

      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(TaskCard),
          matching: find.byIcon(subjectIconFor(className)),
        ),
      );
      expect(icon.color, expected);
      expect(icon.color, isNot(const Color(0xFFEF4444)));
    });
  });
}
