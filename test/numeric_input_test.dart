import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/main.dart';
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
  testWidgets('weight and reps steps use typed value, clamp, and save', (
    t,
  ) async {
    num value = 0;
    final form = GlobalKey<FormState>();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: form,
            child: ValueBox(
              value: 0,
              allowDecimal: true,
              normalizeZeros: true,
              stepLabel: 'KG',
              onChanged: (v) => value = v,
            ),
          ),
        ),
      ),
    );
    await t.enterText(find.byType(TextFormField), '020');
    expect(
      t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '20',
    );
    await t.enterText(find.byType(TextFormField), '2.5');
    await t.tap(find.text('+5'));
    await t.pump();
    expect(value, 7.5);
    await t.tap(find.text('−5'));
    await t.pump();
    expect(value, 2.5);
    await t.tap(find.text('−5'));
    await t.pump();
    expect(value, 0);
    form.currentState!.save();
    expect(value, 0);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueBox(
            key: const Key('reps'),
            value: 10,
            stepLabel: 'REPS',
            onChanged: (v) => value = v,
          ),
        ),
      ),
    );
    await t.tap(find.text('+5'));
    await t.pump();
    expect(value, 15);
    await t.tap(find.text('−5'));
    await t.pump();
    expect(value, 10);
    await t.enterText(find.byType(TextFormField), '2');
    await t.tap(find.text('−5'));
    await t.pump();
    expect(value, 0);
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
