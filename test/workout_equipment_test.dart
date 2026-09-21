import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('equipment replacement preserves identity and the exact sets list', () {
    final set = WorkoutSet(
      weight: 12.5, reps: 8, durationSeconds: 90, distanceKm: 0.5,
      speedKmh: 6, inclinePercent: 3, resistanceLevel: 4, paceSecondsPerKm: 240,
    )..completed = true;
    final original = WorkoutExercise(
      name: 'ショルダープレス', exerciseId: 'shoulder_press',
      bodyPart: '肩', equipment: 'ダンベル',
      recordType: ExerciseRecordType.weightReps, sets: [set],
    );
    final changed = original.withEquipment('プレートロード');
    expect(identical(changed.sets, original.sets), isTrue);
    expect(identical(changed.sets.single, set), isTrue);
    expect(changed.identity, original.identity);
    expect(changed.name, original.name);
    expect(changed.bodyPart, original.bodyPart);
    expect(changed.recordType, original.recordType);
    expect(changed.equipment, 'プレートロード');
    expect(original.equipment, 'ダンベル');
  });

  test('equipment form requires an exact compatible catalog match', () {
    const template = ExerciseTemplate(
      name: 'ショルダープレス', exerciseId: 'shoulder_press', bodyPart: '肩',
      equipment: 'プレートロード', startWeight: 20,
    );
    expect(template.equipmentForm?.exerciseId, 'plate_loaded_shoulder_press');
    expect(template.exerciseId, 'shoulder_press');
    const unknown = ExerciseTemplate(
      name: 'ベンチプレス', exerciseId: 'bench_press', bodyPart: '胸',
      equipment: 'その他', startWeight: 20,
    );
    expect(unknown.equipmentForm, isNull);
  });

  for (final editing in [false, true]) {
    testWidgets('equipment changes retain workout values editing=$editing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await WorkoutUiPreference.load();
      await RestTimerPreference.load();
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = WorkoutRecord(
        date: DateTime(2026, 9, 1), gymName: '自宅', note: 'メモ',
        durationSeconds: 123,
        sets: const [
          RecordedSet(exerciseName: 'ショルダープレス', exerciseId: 'shoulder_press',
            bodyPart: '肩', equipment: 'ダンベル', weight: 20, reps: 8, completed: true),
          RecordedSet(exerciseName: 'ショルダープレス', exerciseId: 'shoulder_press',
            bodyPart: '肩', equipment: 'ダンベル', weight: 25, reps: 6, completed: true),
        ],
      );
      WorkoutRecord? saved;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
        body: TextButton(child: const Text('開く'), onPressed: () async {
          saved = await Navigator.of(context).push<WorkoutRecord>(MaterialPageRoute(
            builder: (_) => WorkoutPage(initialWorkout: original, isEditing: editing, gymName: '自宅'),
          ));
        }),
      ))));
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      final edit = find.byKey(const Key('editExerciseEquipment0'));
      Future<void> selectEquipment() async {
        await tester.tap(edit);
        await tester.pumpAndSettle();
        expect(find.text('現在の器具：ダンベル'), findsOneWidget);
        final field = find.byKey(const Key('exerciseEquipmentField'));
        expect(tester.widget<DropdownButtonFormField<String>>(field).initialValue, 'ダンベル');
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text('プレートロード').last);
        await tester.pumpAndSettle();
      }
      await selectEquipment();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(find.text('肩 ・ ダンベル'), findsOneWidget);
      final before = tester.widget<ExerciseInputCard>(find.byType(ExerciseInputCard)).exercise;
      await selectEquipment();
      await tester.tap(find.byKey(const Key('saveExerciseEquipment')));
      await tester.pumpAndSettle();
      final after = tester.widget<ExerciseInputCard>(find.byType(ExerciseInputCard)).exercise;
      expect(identical(before.sets, after.sets), isTrue);
      expect(after.sets.map((s) => s.weight), [20, 25]);
      expect(after.sets.map((s) => s.reps), [8, 6]);
      expect(after.sets.map((s) => s.completed), [editing, editing]);
      expect(find.text('肩 ・ プレートロード'), findsOneWidget);
      expect(find.byTooltip('種目を削除'), findsOneWidget);
      expect(find.byTooltip('セットを削除'), findsNWidgets(2));
      final preferences = await SharedPreferences.getInstance();
      if (!editing) {
        final draft = jsonDecode(preferences.getString(activeWorkoutDraftStorageKey)!);
        expect(draft['exercises'][0]['equipment'], 'プレートロード');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
          body: TextButton(child: const Text('再開'), onPressed: () async {
            saved = await Navigator.of(context).push<WorkoutRecord>(MaterialPageRoute(
              builder: (_) => const WorkoutPage(),
            ));
          }),
        ))));
        await tester.tap(find.text('再開'));
        await tester.pumpAndSettle();
        final resumed = tester.widget<ExerciseInputCard>(find.byType(ExerciseInputCard)).exercise;
        expect(resumed.equipment, 'プレートロード');
        expect(resumed.sets.map((s) => s.weight), [20, 25]);
        expect(resumed.sets.map((s) => s.completed), [false, false]);
        tester.widget<ExerciseInputCard>(find.byType(ExerciseInputCard)).onSetAllCompleted(true);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('completeWorkoutButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('completeWithoutSharingButton')));
        await tester.pumpAndSettle();
        expect(saved!.sets.map((s) => s.equipment), ['プレートロード', 'プレートロード']);
        expect(saved!.gymName, '自宅');
      } else {
        await tester.tap(find.byKey(const Key('completeWorkoutButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('completeAndPreviewShareButton')));
        await tester.pumpAndSettle();
        expect(saved!.sets.map((s) => s.equipment), ['プレートロード', 'プレートロード']);
        expect(saved!.gymName, original.gymName);
        expect(saved!.date, original.date);
        expect(saved!.note, original.note);
        expect(saved!.durationSeconds, original.durationSeconds);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
