import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const sets = [
    RecordedSet(
      exerciseName: 'ベンチプレス', bodyPart: '胸',
      weight: 50, reps: 8, completed: true,
    ),
  ];

  Future<void> chooseGym(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('workoutGymButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ゴールドジム'));
    await tester.pumpAndSettle();
  }

  Finder gymLabel(String name) => find.descendant(
    of: find.byKey(const Key('workoutGymButton')),
    matching: find.text(name),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({'selected_gym': '自宅'});
    WorkoutUiPreference.completionCheckEnabled = false;
    WorkoutUiPreference.workoutTimerEnabled = false;
    WorkoutUiPreference.workoutDurationEnabled = false;
    RestTimerPreference.enabled = false;
  });
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    await WorkoutUiPreference.load();
    await RestTimerPreference.load();
  });

  for (final editing in [false, true]) {
    testWidgets('workout gym saves independently of usual gym editing=$editing', (tester) async {
      final original = WorkoutRecord(
        date: DateTime(2026, 9, 1), sets: sets,
        gymName: '元のジム', durationSeconds: 120, note: 'メモ',
      );
      WorkoutRecord? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('開く'),
            onPressed: () async {
              saved = await Navigator.of(context).push<WorkoutRecord>(
                MaterialPageRoute(builder: (_) => WorkoutPage(
                  gymName: '自宅', initialWorkout: original, isEditing: editing,
                )),
              );
            },
          ),
        )),
      ));
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(gymLabel(editing ? '元のジム' : '自宅'), findsOneWidget);
      await chooseGym(tester);
      expect(gymLabel('ゴールドジム'), findsOneWidget);
      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(editing
          ? 'completeAndPreviewShareButton' : 'completeWithoutSharingButton')));
      await tester.pumpAndSettle();
      expect(saved?.gymName, 'ゴールドジム');
      expect(saved?.sets.single.weight, 50);
      expect(saved?.sets.single.reps, 8);
      if (editing) {
        expect(saved?.date, original.date);
        expect(saved?.durationSeconds, original.durationSeconds);
        expect(saved?.note, original.note);
      }
      expect(WorkoutRecord.fromJson(saved!.toJson()).gymName, 'ゴールドジム');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('selected_gym'), '自宅');
    });
  }

  testWidgets('workout gym legacy draft falls back then preserves changed gym', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(activeWorkoutDraftStorageKey, jsonEncode({
      'date': DateTime(2026, 9, 1).toIso8601String(),
      'elapsedSeconds': 100,
      'timerStopped': true,
      'exercises': [
        {'name': 'ベンチプレス', 'bodyPart': '胸', 'equipment': 'フリーウェイト',
          'sets': [{'weight': 50, 'reps': 8, 'completed': false}]},
      ],
    }));
    await tester.pumpWidget(const MaterialApp(home: WorkoutPage(gymName: '自宅')));
    await tester.pumpAndSettle();
    expect(gymLabel('自宅'), findsOneWidget);
    await chooseGym(tester);
    final draft = jsonDecode(preferences.getString(activeWorkoutDraftStorageKey)!);
    expect(draft['gymName'], 'ゴールドジム');
    expect(draft['date'], DateTime(2026, 9, 1).toIso8601String());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MaterialApp(home: WorkoutPage(gymName: '自宅')));
    await tester.pumpAndSettle();
    expect(gymLabel('ゴールドジム'), findsOneWidget);
    expect(preferences.getString('selected_gym'), '自宅');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('workout gym null in an edited record stays unselected', (tester) async {
    await tester.pumpWidget(MaterialApp(home: WorkoutPage(
      gymName: '自宅', isEditing: true,
      initialWorkout: WorkoutRecord(date: DateTime(2026, 9, 1), sets: sets),
    )));
    await tester.pumpAndSettle();
    expect(gymLabel('未選択'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
