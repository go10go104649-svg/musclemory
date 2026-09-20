import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exercise_form_expansion_test.dart' as captures;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native numeric input, traversal and saved workout', (t) async {
    SharedPreferences.setMockInitialValues({
      'completion_check_enabled': true,
      'rest_timer_enabled': false,
    });
    await WorkoutUiPreference.load();
    await RestTimerPreference.load();
    WorkoutRecord? saved;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('QA開始'),
              onPressed: () async {
                saved = await Navigator.of(context).push<WorkoutRecord>(
                  MaterialPageRoute(
                    builder: (_) => WorkoutPage(
                      history: const [],
                      initialWorkout: WorkoutRecord(
                        date: DateTime.now(),
                        sets: const [
                          RecordedSet(weight: 20, reps: 10, completed: true),
                          RecordedSet(weight: 20, reps: 10, completed: true),
                          RecordedSet(
                            exerciseName: 'クランチ',
                            bodyPart: '腹筋',
                            recordType: ExerciseRecordType.bodyweightReps,
                            weight: 0,
                            reps: 12,
                            completed: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('QA開始'));
    await t.pumpAndSettle();
    Finder input(String key) => find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(EditableText),
    );
    await t.ensureVisible(input('weightField0_1'));
    await t.pumpAndSettle();
    await t.tap(input('weightField0_1'));
    await t.pumpAndSettle();
    await t.enterText(input('weightField0_1'), '020');
    await t.pumpAndSettle();
    expect(
      t.widget<EditableText>(input('weightField0_1')).controller.text,
      '20',
    );
    await captures.capture(binding, 'numeric_weight_keyboard');
    for (final key in [
      'weightField0_1',
      'repsField0_1',
      'weightField0_2',
      'repsField0_2',
    ]) {
      t
          .state<EditableTextState>(input(key))
          .performAction(TextInputAction.next);
      await t.pumpAndSettle();
    }
    final last = t.widget<EditableText>(input('repsField1_1'));
    expect(last.focusNode.hasFocus, true);
    expect(last.textInputAction, TextInputAction.done);
    await captures.capture(binding, 'numeric_last_keyboard');
    t
        .state<EditableTextState>(input('repsField1_1'))
        .performAction(TextInputAction.done);
    await t.pumpAndSettle();
    final plus = find.descendant(
      of: find.byKey(const Key('weightField0_1')),
      matching: find.text('+5'),
    );
    await t.ensureVisible(plus);
    await t.pumpAndSettle();
    await t.tap(plus);
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final draft =
        jsonDecode(prefs.getString(activeWorkoutDraftStorageKey)!) as Map;
    expect(draft['exercises'][0]['sets'][0]['weight'], 25);
    for (final key in ['toggleAllSets0', 'toggleAllSets1']) {
      final target = find.byKey(Key(key));
      await t.ensureVisible(target);
      await t.pumpAndSettle();
      await t.tap(target);
      await t.pumpAndSettle();
    }
    await t.tap(find.text('完了').first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('completeWithoutSharingButton')));
    await t.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.sets.length, 3);
    expect(saved!.sets.first.weight, 25);
    expect(prefs.getString(activeWorkoutDraftStorageKey), isNull);
    expect(t.takeException(), isNull);
  });
}
