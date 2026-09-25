import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

RecordedSet assisted(
  String id,
  double weight, {
  ExerciseRecordType type = ExerciseRecordType.assistedReps,
}) => RecordedSet(
  exerciseId: id,
  exerciseName: id == 'assisted_dips' ? 'アシストディップス' : 'アシストチンニング',
  bodyPart: '背中',
  equipment: 'マシン',
  recordType: type,
  weight: weight,
  reps: 10,
  completed: true,
);
WorkoutRecord record(RecordedSet set) => WorkoutRecord(
  date: DateTime(2026, 9, 23),
  sets: [set],
  durationSeconds: 60,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('assistance round trips, accepts zero and is not lifted volume or a weight PR', () {
    for (final id in ['assisted_chin_up', 'assisted_dips']) {
      final set = assisted(id, 22.5);
      final restored = WorkoutRecord.fromJson(
        jsonDecode(jsonEncode(record(set).toJson())),
      );
      expect(restored.sets.single.displaySummary, '補助 22.5 kg × 10 回');
      expect(restored.toJson(), record(set).toJson());
      expect(restored.volume, 0);
      expect(
        countPersonalBests([
          restored,
          record(assisted(id, 50)),
        ], DateTime(2026)),
        0,
      );
      expect(assisted(id, 0).hasRequiredValues, isTrue);
      expect(assisted(id, -1).hasRequiredValues, isFalse);
      final old = assisted(id, 0, type: ExerciseRecordType.bodyweightReps);
      expect(RecordedSet.fromJson(old.toJson()).displaySummary, '10 回');
      final legacy = old.toJson()..remove('recordType');
      expect(
        RecordedSet.fromJson(legacy).recordType,
        ExerciseRecordType.bodyweightReps,
      );
    }
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final id in ['assisted_chin_up', 'assisted_dips']) {
      testWidgets('$platform $id edits and saves assistance', (t) async {
        WorkoutRecord? saved;
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: WorkoutPage(
              initialWorkout: record(assisted(id, 20)),
              isEditing: true,
              onSave: (value) async {
                saved = value;
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('補助 KG'), findsWidgets);
        final field = find.descendant(
          of: find.byKey(const Key('weightField0_1')),
          matching: find.byType(TextField),
        );
        await t.enterText(field, '12.5');
        FocusManager.instance.primaryFocus?.unfocus();
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('completeWorkoutButton')));
        await t.pumpAndSettle();
        expect(saved!.sets.single.weight, 12.5);
        expect(saved!.sets.single.recordType, ExerciseRecordType.assistedReps);
        expect(saved!.sets.single.displaySummary, '補助 12.5 kg × 10 回');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpAndSettle();
      });
    }
  }
  testWidgets(
    'legacy reps stay unchanged unless assistance is explicitly added',
    (t) async {
      WorkoutRecord? saved;
      final old = record(
        assisted(
          'assisted_chin_up',
          0,
          type: ExerciseRecordType.bodyweightReps,
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          home: WorkoutPage(
            initialWorkout: old,
            isEditing: true,
            onSave: (value) async {
              saved = value;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('weightField0_1')), findsNothing);
      await t.ensureVisible(find.byKey(const Key('addAssistanceWeight0')));
      await t.tap(find.byKey(const Key('addAssistanceWeight0')));
      await t.pumpAndSettle();
      final field = find.descendant(
        of: find.byKey(const Key('weightField0_1')),
        matching: find.byType(TextField),
      );
      await t.enterText(field, '30');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('completeWorkoutButton')));
      await t.pumpAndSettle();
      expect(saved!.sets.single.displaySummary, '補助 30 kg × 10 回');
      expect(old.sets.single.recordType, ExerciseRecordType.bodyweightReps);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'assistance progress shows recorded values without a misleading 1RM',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: ExerciseProgressPage(
            history: [record(assisted('assisted_dips', 25))],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('補助 25 kg × 10 回'), findsOneWidget);
      expect(find.text('最高重量'), findsNothing);
      expect(find.text('推定1RM'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
