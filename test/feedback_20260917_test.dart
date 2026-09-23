import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:muscle_memory/exercise_form_catalog.dart';
import 'package:muscle_memory/muscle_targets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'incline machine has stable identity, translations, load and targets',
    () {
      final form = ExerciseFormCatalog.byId['incline_fly_machine']!;
      expect(form.exerciseName, 'インクラインフライマシン');
      expect(
        exerciseDisplayName(form.exerciseName, languageCode: 'en'),
        'Incline Fly Machine',
      );
      expect(form.available, isFalse);
      final template = exerciseTemplates.singleWhere(
        (e) => e.name == form.exerciseName,
      );
      expect(template.bodyPart, '胸');
      expect(template.recordType, ExerciseRecordType.weightReps);
      final recorded = RecordedSet(
        exerciseName: template.name,
        bodyPart: '胸',
        weight: 30,
        reps: 12,
        completed: true,
      );
      expect(
        RecordedSet.fromJson(recorded.toJson()).displaySummary,
        contains('30 kg'),
      );
      expect(muscleProfileForExercise(template.name, '胸').primary, [
        MuscleRegion.pectoralisMajor,
      ]);
      final dumbbellFly = exerciseTemplates.singleWhere(
        (e) => e.name == 'インクラインダンベルフライ',
      );
      expect(template.equipment, 'マシン');
      expect(dumbbellFly.equipment, 'ダンベル');
      expect(dumbbellFly.identity, isNot(template.identity));
    },
  );
  testWidgets('incline fly English search and sharing use the same master', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ExercisePickerSheet(existingNames: {})),
      ),
    );
    await tester.tap(find.byKey(const Key('exerciseCategory胸')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('exerciseSearchField')),
      'Incline Fly Machine',
    );
    await tester.pumpAndSettle();
    // Match the result label, not the search field's EditableText.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'Incline Fly Machine',
      ),
      findsOneWidget,
    );
    final workout = WorkoutRecord(
      date: DateTime.now(),
      sets: const [
        RecordedSet(
          exerciseName: 'インクラインフライマシン',
          bodyPart: '胸',
          weight: 30,
          reps: 12,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutSharePage(
          workout: WorkoutRecord.fromJson(workout.toJson()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('インクラインフライマシン'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('stable set positions, pause/resume and dynamic final set', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'rest_timer_enabled': true,
      'rest_timer_seconds': 34,
      'completion_check_enabled': true,
    });
    await RestTimerPreference.load();
    await WorkoutUiPreference.load();
    final record = WorkoutRecord(
      date: DateTime.now(),
      durationSeconds: 0,
      sets: List.generate(
        3,
        (_) => const RecordedSet(weight: 40, reps: 10, completed: true),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutPage(history: const [], initialWorkout: record),
      ),
    );
    await tester.pumpAndSettle();
    final first = find.byKey(const Key('toggleSet0_1'));
    final original = tester.getCenter(first);
    await tester.tap(first);
    await tester.pump();
    expect(tester.getCenter(first), original);
    expect(find.byKey(const Key('stopRestTimerButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('stopRestTimerButton')));
    await tester.pump();
    expect(tester.getCenter(first), original);
    expect(find.text('00:34'), findsOneWidget);
    await tester.pump(const Duration(seconds: 40));
    expect(find.text('00:34'), findsOneWidget);
    expect(find.byKey(const Key('restTimerFinishedMessage')), findsNothing);
    await tester.tap(find.byKey(const Key('startRestTimerButton')));
    await tester.pump();
    expect(find.text('00:34'), findsOneWidget);
    await tester.tap(find.byKey(const Key('toggleSet0_3')));
    await tester.pump();
    expect(find.byKey(const Key('stopRestTimerButton')), findsNothing);
    expect(tester.getCenter(first), original);
    await tester.tap(first);
    await tester.pump();
    expect(tester.getCenter(first), original);
    await tester.tap(find.byKey(const Key('addSetButton')));
    await tester.pump();
    // Former last set is now followed by another set and auto-starts again.
    await tester.tap(find.byKey(const Key('toggleSet0_3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('toggleSet0_3')));
    await tester.pump();
    expect(find.byKey(const Key('stopRestTimerButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('toggleSet0_4')));
    await tester.pump();
    expect(find.byKey(const Key('startRestTimerButton')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
