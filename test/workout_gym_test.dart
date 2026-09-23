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
    await tester.scrollUntilVisible(find.text('ゴールドジム'), 150,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
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

  testWidgets('workout information, gym addition and compact rest controls', (tester) async {
    CustomGymPreference.gyms = [];
    WorkoutUiPreference.completionCheckEnabled = true;
    RestTimerPreference.enabled = true;
    RestTimerPreference.seconds = 60;
    final original = WorkoutRecord(date: DateTime(2026, 9, 1), sets: sets);
    await tester.pumpWidget(MaterialApp(home: WorkoutPage(
      gymName: '自宅', initialWorkout: original,
    )));
    await tester.pumpAndSettle();
    final card = find.byKey(const Key('workoutInfoCard'));
    expect(find.descendant(of: card, matching: find.byKey(const Key('workoutDateButton'))), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byKey(const Key('workoutGymButton'))), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('自宅')), findsNothing);
    expect(find.descendant(of: find.byType(AppBar), matching: find.byKey(const Key('workoutElapsedLabel'))), findsNothing);
    await tester.tap(find.byKey(const Key('workoutGymButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addWorkoutGymButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('customGymNameField')), '今回のジム');
    await tester.tap(find.byKey(const Key('saveCustomGymButton')));
    await tester.pumpAndSettle();
    expect(gymLabel('今回のジム'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('selected_gym'), '自宅');
    await CustomGymPreference.load();
    expect(CustomGymPreference.gyms, contains('今回のジム'));
    expect(jsonDecode(preferences.getString(activeWorkoutDraftStorageKey)!)['gymName'], '今回のジム');
    expect(find.byKey(const Key('editExerciseEquipment0')), findsNothing);
    expect(find.byTooltip('種目を削除'), findsOneWidget);
    final rest = find.byKey(const Key('restTimerBanner'));
    expect(find.descendant(of: rest, matching: find.byType(IconButton)), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.byKey(const Key('startRestTimerButton')));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await tester.tap(find.byKey(const Key('stopRestTimerButton')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('01:00'), findsOneWidget);
    await tester.tap(find.text('+30秒'));
    await tester.pump();
    expect(find.text('01:30'), findsOneWidget);
    await tester.tap(find.byKey(const Key('startRestTimerButton')));
    await tester.pump();
    expect(find.text('01:30'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: StartWorkoutCard(onPressed: _noop),
    )));
    await tester.pumpAndSettle();
    expect(find.text('トレーニングを始める'), findsOneWidget);
    expect(find.byIcon(Icons.location_on_outlined), findsNothing);
    expect(find.text('店舗を選択'), findsNothing);
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

void _noop() {}
