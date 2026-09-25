import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder input(String key) => find.descendant(
  of: find.byKey(Key(key)),
  matching: find.byType(TextFormField),
);
TextField field(WidgetTester t, String key) => t.widget<TextField>(
  find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField)),
);
void main() {
  test('integer prefix normalization preserves decimals and caret', () {
    const formatter = NumericLeadingZeroFormatter();
    for (final pair in {
      '020': '20',
      '005': '5',
      '00050': '50',
      '0': '0',
      '0.5': '0.5',
      '00.50': '0.50',
      '0,5': '0,5',
    }.entries) {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: pair.key,
          selection: TextSelection.collapsed(offset: pair.key.length),
        ),
      );
      expect(result.text, pair.value);
      expect(result.selection.baseOffset, pair.value.length);
    }
    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '0050',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    expect(result.selection.baseOffset, 1);
  });
  testWidgets('keypad digits, decimal, steps, selection and navigation', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({
      'completion_check_enabled': true,
      'rest_timer_enabled': false,
    });
    await WorkoutUiPreference.load();
    await RestTimerPreference.load();
    await t.pumpWidget(
      MaterialApp(
        home: WorkoutPage(
          history: const [],
          initialWorkout: WorkoutRecord(
            date: DateTime.now(),
            sets: const [RecordedSet(weight: 0, reps: 10, completed: true)],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('+5'), findsNothing);
    await t.tap(input('weightField0_1'));
    await t.pumpAndSettle();
    expect(field(t, 'weightField0_1').keyboardType, TextInputType.none);
    expect(field(t, 'weightField0_1').decoration!.focusedBorder, isNotNull);
    Future<void> press(String key) async {
      await t.tap(find.byKey(Key('numericKey$key')));
      await t.pumpAndSettle();
    }

    for (final key in ['0', '2', '.', '5']) {
      await press(key);
    }
    expect(field(t, 'weightField0_1').controller!.text, '2.5');
    await press('plus1');
    expect(field(t, 'weightField0_1').controller!.text, '3.5');
    await press('plus5');
    expect(field(t, 'weightField0_1').controller!.text, '8.5');
    await press('minus1');
    expect(field(t, 'weightField0_1').controller!.text, '7.5');
    await press('minus5');
    expect(field(t, 'weightField0_1').controller!.text, '2.5');
    await press('minus5');
    expect(field(t, 'weightField0_1').controller!.text, '0');
    await press('next');
    expect(field(t, 'repsField0_1').focusNode!.hasFocus, true);
    expect(
      t.widget<TextButton>(find.byKey(const Key('numericKey.'))).onPressed,
      isNull,
    );
    await press('plus1');
    expect(field(t, 'repsField0_1').controller!.text, '11');
    await press('plus5');
    expect(field(t, 'repsField0_1').controller!.text, '16');
    await press('minus1');
    expect(field(t, 'repsField0_1').controller!.text, '15');
    await press('minus5');
    expect(field(t, 'repsField0_1').controller!.text, '10');
    await t.enterText(input('repsField0_1'), '2');
    await press('minus5');
    expect(field(t, 'repsField0_1').controller!.text, '0');
    await press('previous');
    expect(field(t, 'weightField0_1').focusNode!.hasFocus, true);
    await t.enterText(input('weightField0_1'), '25');
    field(t, 'weightField0_1').controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 2,
    );
    await press('5');
    expect(field(t, 'weightField0_1').controller!.text, '5');
    await press('delete');
    expect(field(t, 'weightField0_1').controller!.text, '');
    await press('.');
    await press('5');
    expect(field(t, 'weightField0_1').controller!.text, '0.5');
    await press('next');
    await press('next');
    expect(find.byKey(const Key('workoutNumericKeypad')), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    '320px workout traversal, edits, deletion, draft and completion',
    (t) async {
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'completion_check_enabled': true,
        'rest_timer_enabled': false,
      });
      await WorkoutUiPreference.load();
      await RestTimerPreference.load();
      await t.pumpWidget(
        MaterialApp(
          home: WorkoutPage(
            history: const [],
            initialWorkout: WorkoutRecord(
              date: DateTime.now(),
              sets: [
                for (var i = 0; i < 2; i++)
                  const RecordedSet(weight: 20, reps: 10, completed: true),
                const RecordedSet(
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
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
        t.element(input('weightField0_1')),
        alignment: 0.4,
      );
      await t.pumpAndSettle();
      await t.tap(input('weightField0_1'));
      await t.pump();
      await t.enterText(input('weightField0_1'), '005');
      expect(field(t, 'weightField0_1').controller!.text, '5');
      for (final key in [
        'repsField0_1',
        'weightField0_2',
        'repsField0_2',
        'repsField1_1',
      ]) {
        await t.testTextInput.receiveAction(TextInputAction.next);
        await t.pumpAndSettle();
        expect(field(t, key).focusNode!.hasFocus, true, reason: key);
      }
      expect(field(t, 'repsField1_1').textInputAction, TextInputAction.done);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(field(t, 'repsField1_1').focusNode!.hasFocus, false);
      final add = find.byKey(const Key('addSetButton')).first;
      await t.ensureVisible(add);
      await t.tap(add);
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
        t.element(input('repsField0_2')),
        alignment: 0.4,
      );
      await t.pumpAndSettle();
      await t.tap(input('repsField0_2'));
      await t.pump();
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pumpAndSettle();
      expect(field(t, 'weightField0_3').focusNode!.hasFocus, true);
      final del = find.byKey(const Key('deleteSet0_2'));
      await t.ensureVisible(del);
      await t.tap(del);
      await t.pumpAndSettle();
      expect(input('weightField0_3'), findsNothing);
      await Scrollable.ensureVisible(
        t.element(input('repsField0_1')),
        alignment: 0.4,
      );
      await t.pumpAndSettle();
      await t.tap(input('repsField0_1'));
      await t.pump();
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pumpAndSettle();
      expect(field(t, 'weightField0_2').focusNode!.hasFocus, true);
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      final all = find.byKey(const Key('toggleAllSets0'));
      await t.ensureVisible(all);
      await t.tap(all);
      await t.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final draft = jsonDecode(prefs.getString(activeWorkoutDraftStorageKey)!);
      expect(draft['exercises'][0]['sets'][0]['weight'], 5);
      final remove = find.byTooltip('種目を削除').last;
      await t.ensureVisible(remove);
      await t.pumpAndSettle();
      await t.tap(remove);
      await t.pumpAndSettle();
      expect(field(t, 'repsField0_2').textInputAction, TextInputAction.done);
      await t.tap(find.text('元に戻す'));
      await t.pumpAndSettle();
      expect(field(t, 'repsField0_2').textInputAction, TextInputAction.next);
      expect(field(t, 'repsField1_1').textInputAction, TextInputAction.done);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
