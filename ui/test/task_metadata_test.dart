import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/services/api_service.dart';
import 'package:ui/theme/app_theme.dart';
import 'package:ui/widgets/draft_view.dart';
import 'package:ui/widgets/meta_badge.dart';
import 'package:ui/widgets/task_card.dart';

TaskSummary _task({
  String? taskType,
  String? weight,
  String? status,
  List<RubricCriterion> criteria = const <RubricCriterion>[],
}) {
  return TaskSummary(
    id: '47949059',
    title: 'Homework 1 unit-4',
    className: 'IB MYP I&S (Grade 10)',
    dueDate: 'Apr 29, 11:40 AM',
    description: 'Formative, Homework /10%, Pending',
    taskType: taskType,
    weight: weight,
    status: status,
    rubricCriteria: criteria,
  );
}

Future<void> _pumpCard(WidgetTester tester, TaskSummary task) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 330,
          child: TaskCard(task: task, isActive: true, isSelected: false),
        ),
      ),
    ),
  );
}

void main() {
  group('TaskSummary.fromJson', () {
    test('reads the metadata the API now returns', () {
      final task = TaskSummary.fromJson(<String, dynamic>{
        'id': '47949059',
        'title': 'Summative unit-3',
        'class_name': 'IB MYP Design (Grade 10)',
        'due_date': 'Apr 29',
        'description': 'Summative, Project /25%, Pending',
        'task_type': 'Summative',
        'category': 'Project',
        'weight': '25%',
        'status': 'Pending',
        'rubric_criteria': <dynamic>[
          <String, dynamic>{'letter': 'B', 'name': 'Investigating'},
          <String, dynamic>{'letter': 'C', 'name': 'Communicating'},
        ],
      });

      expect(task.taskType, 'Summative');
      expect(task.weight, '25%');
      expect(task.isSummative, isTrue);
      expect(task.rubricCriteria.map((c) => c.letter).toList(), <String>['B', 'C']);
      expect(task.rubricCriteria.first.label, 'B — Investigating');
    });

    test('tolerates a payload with none of the new fields', () {
      // A vault row written before the metadata existed.
      final task = TaskSummary.fromJson(<String, dynamic>{
        'id': '1',
        'title': 'Old Task',
        'class_name': 'Maths',
      });

      expect(task.taskType, isNull);
      expect(task.weight, isNull);
      expect(task.rubricCriteria, isEmpty);
      expect(task.isSummative, isFalse);
    });

    test('treats empty strings as absent', () {
      final task = TaskSummary.fromJson(<String, dynamic>{
        'id': '1',
        'title': 'T',
        'class_name': 'C',
        'task_type': '',
        'weight': '   ',
      });

      expect(task.taskType, isNull);
      expect(task.weight, isNull);
    });

    test('ignores malformed criteria entries', () {
      final task = TaskSummary.fromJson(<String, dynamic>{
        'id': '1',
        'title': 'T',
        'class_name': 'C',
        'rubric_criteria': <dynamic>[
          'garbage',
          <String, dynamic>{'letter': ''},
          <String, dynamic>{'letter': 'B'},
        ],
      });

      expect(task.rubricCriteria.length, 1);
      expect(task.rubricCriteria.single.letter, 'B');
      expect(task.rubricCriteria.single.label, 'B');
    });

    test('survives rubric_criteria arriving as a non-list', () {
      final task = TaskSummary.fromJson(<String, dynamic>{
        'id': '1',
        'title': 'T',
        'class_name': 'C',
        'rubric_criteria': 'unexpected',
      });

      expect(task.rubricCriteria, isEmpty);
    });
  });

  group('TaskCard badges', () {
    testWidgets('shows type, weight and criteria letters', (tester) async {
      await _pumpCard(
        tester,
        _task(
          taskType: 'Summative',
          weight: '25%',
          criteria: const <RubricCriterion>[
            RubricCriterion(letter: 'B', name: 'Investigating'),
            RubricCriterion(letter: 'C', name: 'Communicating'),
          ],
        ),
      );

      expect(find.text('Summative'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('B C'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing extra when metadata is absent', (tester) async {
      await _pumpCard(tester, _task());

      expect(find.text('Homework 1 unit-4'), findsOneWidget);
      expect(find.byType(Wrap), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('emphasises summative over formative', (tester) async {
      await _pumpCard(tester, _task(taskType: 'Summative'));
      final summative = tester.widget<MetaBadge>(find.byType(MetaBadge));
      expect(summative.emphasised, isTrue);

      await _pumpCard(tester, _task(taskType: 'Formative'));
      final formative = tester.widget<MetaBadge>(find.byType(MetaBadge));
      expect(formative.emphasised, isFalse);
    });

    testWidgets('does not overflow a narrow card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: TaskCard(
                task: _task(
                  taskType: 'Summative',
                  weight: '25%',
                  criteria: const <RubricCriterion>[
                    RubricCriterion(letter: 'A'),
                    RubricCriterion(letter: 'B'),
                    RubricCriterion(letter: 'C'),
                    RubricCriterion(letter: 'D'),
                  ],
                ),
                isActive: true,
                isSelected: false,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('DraftView header metadata', () {
    Future<void> pumpDraft(WidgetTester tester, TaskSummary? task) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: DraftView(
              selectedTaskId: '47949059',
              selectedTaskTitle: 'Summative unit-3',
              selectedTaskClassName: 'IB MYP Design (Grade 10)',
              selectedTask: task,
              isLoading: false,
              markdown: '# A draft',
              error: null,
              onExport: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('names criteria in full, unlike the card', (tester) async {
      await pumpDraft(
        tester,
        _task(
          taskType: 'Summative',
          weight: '25%',
          status: 'Pending',
          criteria: const <RubricCriterion>[
            RubricCriterion(letter: 'B', name: 'Investigating'),
            RubricCriterion(letter: 'C', name: 'Communicating'),
          ],
        ),
      );

      expect(find.text('B — Investigating'), findsOneWidget);
      expect(find.text('C — Communicating'), findsOneWidget);
      expect(find.text('Summative'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a vault draft has no task, so shows no badges', (tester) async {
      await pumpDraft(tester, null);

      expect(find.byType(MetaBadge), findsNothing);
      expect(find.text('Summative unit-3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
