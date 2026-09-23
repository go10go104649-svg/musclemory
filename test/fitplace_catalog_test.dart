import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/exercise_form_catalog.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bulk_exercise_flow.dart';

const addedIds = [
  'assisted_dips',
  'standing_machine_fly',
  'seated_dip_machine',
  'rotary_torso',
  'back_extension_machine',
  'recumbent_bike',
  'v_squat',
  'viking_press',
  'standing_hip_abduction',
  'multi_hip_abduction',
  'multi_hip_adduction',
  'multi_hip_extension',
  'dual_power_smith_shoulder_press',
  'kneeling_leg_curl',
  'deadlift_machine',
  'selectorized_decline_chest_press',
  'selectorized_high_row',
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomExercisePreference.exercises = [];
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('FIT PLACE entries can be searched and selected on $platform', (
      t,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: const Scaffold(body: ExercisePickerSheet()),
        ),
      );
      await t.pumpAndSettle();
      for (final id in addedIds) {
        await selectPickerExercise(t, id);
        final form = ExerciseFormCatalog.byId[id]!;
        expect(form.available, isFalse);
        expect(form.primaryMuscleLabels, isNotEmpty);
        expect(form.secondaryMuscleLabels.length, form.secondaryMuscles.length);
        expect(
          exerciseDisplayName('', exerciseId: id, languageCode: 'en'),
          isNotEmpty,
        );
      }
      expect(find.text('17種目選択中'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  test(
    'new equipment retains distinct identities through record round trips',
    () {
      final ids = [
        'high_row',
        'selectorized_high_row',
        'decline_press_machine',
        'selectorized_decline_chest_press',
        'back_extension',
        'back_extension_machine',
      ];
      final original = WorkoutRecord(
        date: DateTime(2026, 9, 23),
        sets: [
          for (final id in ids)
            RecordedSet(
              exerciseId: id,
              exerciseName: ExerciseFormCatalog.byId[id]!.exerciseName,
              bodyPart: ExerciseFormCatalog.byId[id]!.category,
              equipment: ExerciseFormCatalog.byId[id]!.equipmentLabel,
              weight: 30,
              reps: 10,
              completed: true,
            ),
        ],
        durationSeconds: 600,
      );
      final restored = WorkoutRecord.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(restored.toJson(), original.toJson());
      expect(restored.exerciseGroups, hasLength(ids.length));
      final bike = exerciseTemplates.firstWhere(
        (e) => e.exerciseId == 'recumbent_bike',
      );
      expect(bike.recordType, ExerciseRecordType.cardio);
      final assisted = exerciseTemplates.firstWhere(
        (e) => e.exerciseId == 'assisted_dips',
      );
      expect(assisted.recordType, ExerciseRecordType.assistedReps);
      expect(assisted.startWeight, 0);
      expect(
        exerciseTemplates
            .where((e) => e.matchesQuery('ハイロウ（デュアルスタック）'))
            .map((e) => e.exerciseId),
        contains('selectorized_high_row'),
      );
    },
  );
}
