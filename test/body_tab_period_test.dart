import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/muscle_targets.dart';

void main() {
  testWidgets(
    'all five periods recalculate counts and normalized model scores',
    (tester) async {
      final now = DateTime.now();
      final history = [
        for (final day in [15, 60, 120, 240])
          WorkoutRecord(
            date: now.subtract(Duration(days: day)),
            sets: [
              for (var i = 0; i < day; i++)
                RecordedSet(
                  exerciseName: 'QA',
                  bodyPart: '胸',
                  weight: 20,
                  reps: 10,
                  completed: true,
                ),
              for (var i = 0; i < day ~/ 3; i++)
                RecordedSet(
                  exerciseName: 'QA',
                  bodyPart: '脚',
                  weight: 20,
                  reps: 10,
                  completed: true,
                ),
              RecordedSet(
                exerciseName: 'ignored',
                bodyPart: '腕',
                weight: 20,
                reps: 10,
                completed: false,
              ),
            ],
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BodyMapPage(history: history)),
        ),
      );
      for (final period in MuscleMapPeriod.values) {
        final chip = find.byKey(Key('musclePeriod${period.name}'));
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        final model = tester.widget<MuscleMannequinView>(
          find.byType(MuscleMannequinView),
        );
        final counts = bodyPartSetCounts(history, period, now: now);
        expect(model.fallbackBodyPartCounts, counts);
        expect(
          model.scores[MuscleRegion.pectoralisMajor],
          period == MuscleMapPeriod.week ? 0 : 1,
        );
        expect(
          model.scores[MuscleRegion.quadriceps],
          period == MuscleMapPeriod.week ? 0 : 1 / 3,
        );
        expect(model.scores[MuscleRegion.triceps], 0);
      }
    },
  );
}
