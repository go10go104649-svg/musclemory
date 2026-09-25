// Simulator-only fixture. No preferences, storage or network access.
import 'package:flutter/material.dart';
import 'package:setkeep/main.dart';

void main() {
  final now = DateTime.now();
  const batches = {
    15: [2, 1, 1, 1, 1, 1],
    60: [18, 17, 7, 5, 4, 2],
    120: [60, 54, 24, 18, 15, 9],
    240: [120, 108, 48, 36, 30, 18],
  };
  const parts = ['胸', '背中', '脚', '肩', '腕', '腹'];
  runApp(
    MaterialApp(
      home: Scaffold(
        body: BodyMapPage(
          history: [
            for (final batch in batches.entries)
              WorkoutRecord(
                date: now.subtract(Duration(days: batch.key)),
                sets: [
                  for (var p = 0; p < parts.length; p++)
                    for (var i = 0; i < batch.value[p]; i++)
                      RecordedSet(
                        exerciseName: 'QA ${parts[p]}',
                        bodyPart: parts[p],
                        weight: 20,
                        reps: 10,
                        completed: true,
                      ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}
