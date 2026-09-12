import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('custom exercises persist between sessions', () async {
    SharedPreferences.setMockInitialValues({});
    await CustomExercisePreference.load();
    await CustomExercisePreference.add(
      const ExerciseTemplate(
        name: 'テスト種目',
        bodyPart: '背中',
        equipment: 'カスタム',
        startWeight: 15,
      ),
    );

    CustomExercisePreference.exercises = [];
    await CustomExercisePreference.load();
    expect(CustomExercisePreference.exercises, hasLength(1));
    expect(CustomExercisePreference.exercises.single.name, 'テスト種目');
    expect(CustomExercisePreference.exercises.single.bodyPart, '背中');
  });

  test('saved menus and custom exercises skip only broken items', () async {
    const validMenu = SavedWorkoutTemplate(
      name: '脚の日',
      sets: [
        RecordedSet(
          exerciseName: 'スクワット',
          bodyPart: '脚',
          weight: 80,
          reps: 5,
          completed: true,
        ),
      ],
    );
    const validExercise = ExerciseTemplate(
      name: 'ケーブルフライ',
      bodyPart: '胸',
      equipment: 'カスタム',
      startWeight: 12.5,
    );
    SharedPreferences.setMockInitialValues({
      'workout_templates': jsonEncode([
        validMenu.toJson(),
        {'name': '', 'sets': []},
        {'name': '壊れたメニュー'},
        'unexpected',
      ]),
      'custom_exercises': jsonEncode([
        validExercise.toJson(),
        {'name': '', 'bodyPart': '胸'},
        {'name': '壊れた種目'},
        42,
      ]),
    });

    final menus = await WorkoutTemplatePreference.load();
    await CustomExercisePreference.load();

    expect(menus, hasLength(1));
    expect(menus.single.name, '脚の日');
    expect(CustomExercisePreference.exercises, hasLength(1));
    expect(CustomExercisePreference.exercises.single.name, 'ケーブルフライ');
  });

  test('personal bests are counted in date order', () {
    WorkoutRecord workout(DateTime date, String exercise, int weight) =>
        WorkoutRecord(
          date: date,
          sets: [
            RecordedSet(
              exerciseName: exercise,
              bodyPart: exercise == 'スクワット' ? '脚' : '胸',
              weight: weight.toDouble(),
              reps: 5,
              completed: true,
            ),
          ],
        );

    final history = [
      workout(DateTime(2026, 1, 4), 'ベンチプレス', 50),
      workout(DateTime(2026, 1, 3), 'ベンチプレス', 60),
      workout(DateTime(2026, 1, 1), 'ベンチプレス', 50),
      workout(DateTime(2026, 1, 2), 'スクワット', 80),
      workout(DateTime(2026, 1, 2), 'ベンチプレス', 55),
    ];

    expect(countPersonalBests(history, DateTime(2026, 1, 2)), 3);
  });

  test('weekly streak counts only weeks that reached the target', () {
    WorkoutRecord workout(DateTime date) => WorkoutRecord(
      date: date,
      sets: const [
        RecordedSet(
          exerciseName: 'スクワット',
          bodyPart: '脚',
          weight: 80,
          reps: 5,
          completed: true,
        ),
      ],
    );
    final now = DateTime(2026, 9, 16, 12);
    final currentWeek = startOfWeek(now);
    final history = [
      workout(currentWeek.add(const Duration(days: 1))),
      workout(currentWeek.add(const Duration(days: 8))),
      for (final day in [1, 2, 4])
        workout(currentWeek.subtract(Duration(days: 7 - day))),
      for (final day in [1, 3, 5])
        workout(currentWeek.subtract(Duration(days: 14 - day))),
      for (final day in [1, 2])
        workout(currentWeek.subtract(Duration(days: 21 - day))),
    ];

    expect(workoutCountInWeek(history, currentWeek), 1);
    expect(weeklyGoalStreak(history, 3, now: now), 2);

    final reachedThisWeek = [
      ...history,
      workout(currentWeek.add(const Duration(days: 2))),
      workout(currentWeek.add(const Duration(days: 3))),
    ];
    expect(weeklyGoalStreak(reachedThisWeek, 3, now: now), 3);
  });

  test('changing the calendar day preserves the recorded time', () {
    final original = DateTime(2026, 9, 12, 18, 42, 31, 120, 45);
    final changed = preserveWorkoutTime(original, DateTime(2026, 8, 3));

    expect(changed, DateTime(2026, 8, 3, 18, 42, 31, 120, 45));
  });

  test('decimal weights support old integer data and compact display', () {
    final oldData = RecordedSet.fromJson({
      'exerciseName': 'ベンチプレス',
      'bodyPart': '胸',
      'weight': 50,
      'reps': 8,
      'completed': true,
    });
    final decimalData = RecordedSet.fromJson({
      'exerciseName': 'ベンチプレス',
      'bodyPart': '胸',
      'weight': 52.5,
      'reps': 8,
      'completed': true,
    });

    expect(oldData.weight, 50.0);
    expect(decimalData.weight, 52.5);
    expect(formatWeight(oldData.weight), '50');
    expect(formatWeight(decimalData.weight), '52.5');
    expect(parseWeight('52,5'), 52.5);
  });

  test('history decoding keeps valid records and skips broken items', () {
    final valid = WorkoutRecord(
      date: DateTime(2026, 9, 12, 18, 30),
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 52.5,
          reps: 8,
          completed: true,
        ),
      ],
    );
    final decoded = decodeWorkoutHistory(
      jsonEncode([
        valid.toJson(),
        {'date': '壊れた日付', 'sets': []},
        {'date': '2026-09-11T18:30:00.000', 'sets': []},
        'unexpected',
      ]),
    );

    expect(decoded, hasLength(1));
    expect(decoded.single.exerciseNames, ['ベンチプレス']);
    expect(decodeWorkoutHistory('broken json'), isEmpty);
    expect(decodeWorkoutHistory('{"workouts":[]}'), isEmpty);
  });

  testWidgets('app opens when saved history is corrupted', (tester) async {
    SharedPreferences.setMockInitialValues({'workout_history': 'broken json'});

    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    expect(find.text('今日も積み上げよう'), findsOneWidget);
    expect(find.byKey(const Key('startWorkoutButton')), findsOneWidget);
  });

  test('version 2 backup preserves workouts menus exercises and settings', () {
    final backup = MuscleMemoryBackup(
      workouts: [
        WorkoutRecord(
          date: DateTime(2026, 9, 12, 18, 30),
          sets: const [
            RecordedSet(
              exerciseName: 'ベンチプレス',
              bodyPart: '胸',
              weight: 52.5,
              reps: 8,
              completed: true,
            ),
          ],
        ),
      ],
      workoutTemplates: const [
        SavedWorkoutTemplate(
          name: '胸の日',
          sets: [
            RecordedSet(
              exerciseName: 'ベンチプレス',
              bodyPart: '胸',
              weight: 52.5,
              reps: 8,
              completed: true,
            ),
          ],
        ),
      ],
      customExercises: const [
        ExerciseTemplate(
          name: 'テストプレス',
          bodyPart: '胸',
          equipment: 'カスタム',
          startWeight: 12.5,
        ),
      ],
      selectedGym: 'テストジム',
      weeklyTarget: 4,
      restTimerEnabled: true,
      restTimerSeconds: 120,
    );

    final restored = MuscleMemoryBackup.fromJson(backup.toJson());

    expect(restored.workouts.single.sets.single.weight, 52.5);
    expect(restored.workoutTemplates.single.name, '胸の日');
    expect(restored.customExercises.single.startWeight, 12.5);
    expect(restored.selectedGym, 'テストジム');
    expect(restored.weeklyTarget, 4);
    expect(restored.restTimerEnabled, isTrue);
    expect(restored.restTimerSeconds, 120);

    final partiallyBroken = backup.toJson();
    (partiallyBroken['workoutTemplates'] as List<dynamic>).add({
      'name': '壊れたメニュー',
    });
    (partiallyBroken['customExercises'] as List<dynamic>).add({
      'name': '壊れた種目',
    });
    final safelyRestored = MuscleMemoryBackup.fromJson(partiallyBroken);
    expect(safelyRestored.workoutTemplates, hasLength(1));
    expect(safelyRestored.customExercises, hasLength(1));
  });

  test('old history-only backups remain readable', () {
    final restored = MuscleMemoryBackup.fromJson({
      'app': 'MuscleMemory',
      'version': 1,
      'workouts': <dynamic>[],
    });

    expect(restored.workouts, isEmpty);
    expect(restored.workoutTemplates, isEmpty);
    expect(restored.weeklyTarget, isNull);
  });

  test('workout draft summary reads exercises date and set count', () {
    final summary = WorkoutDraftSummary.tryParse(
      jsonEncode({
        'date': '2026-09-12T18:30:00.000',
        'exercises': [
          {
            'name': 'ベンチプレス',
            'sets': [{}, {}, {}],
          },
          {
            'name': 'ラットプルダウン',
            'sets': [{}, {}],
          },
        ],
      }),
    );

    expect(summary, isNotNull);
    expect(summary!.exerciseNames, ['ベンチプレス', 'ラットプルダウン']);
    expect(summary.setCount, 5);
    expect(summary.date, DateTime(2026, 9, 12, 18, 30));
    expect(WorkoutDraftSummary.tryParse('broken'), isNull);
  });

  test('workouts are sorted newest first without changing the input list', () {
    WorkoutRecord workout(DateTime date) => WorkoutRecord(
      date: date,
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    final old = workout(DateTime(2026, 1, 1));
    final newest = workout(DateTime(2026, 1, 3));
    final middle = workout(DateTime(2026, 1, 2));
    final input = [old, newest, middle];

    final sorted = sortWorkoutsNewestFirst(input);

    expect(sorted, [newest, middle, old]);
    expect(input, [old, newest, middle]);
  });

  testWidgets('history cards show the saved location and memo', (tester) async {
    final workout = WorkoutRecord(
      date: DateTime(2026, 9, 12),
      gymName: 'テストジム',
      note: 'フォームを丁寧に',
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryCard(
            workout: workout,
            selectedGym: null,
            onWorkoutCompleted: (_) {},
            onWorkoutUpdated: (_, _) async {},
            onWorkoutDeleted: (_) async => true,
          ),
        ),
      ),
    );

    expect(find.text('テストジム'), findsOneWidget);
    expect(find.text('フォームを丁寧に'), findsOneWidget);
  });

  testWidgets('last workout card opens its history detail', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workout = WorkoutRecord(
      date: DateTime.now(),
      gymName: 'テストジム',
      note: '肩を下げる',
      durationSeconds: 600,
      sets: const [
        RecordedSet(
          exerciseName: 'ラットプルダウン',
          bodyPart: '背中',
          weight: 45,
          reps: 10,
          completed: true,
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'workout_history': jsonEncode([workout.toJson()]),
    });
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('lastWorkoutCard')));
    await tester.tap(find.byKey(const Key('lastWorkoutCard')));
    await tester.pumpAndSettle();

    expect(find.text('トレーニング詳細'), findsOneWidget);
    expect(find.text('ラットプルダウン'), findsOneWidget);
    expect(find.text('肩を下げる'), findsOneWidget);
    expect(find.text('この内容でもう一度'), findsOneWidget);
  });

  testWidgets('an existing workout date can be changed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final workout = WorkoutRecord(
      date: DateTime(2025, 3, 15, 19, 30),
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: WorkoutPage(initialWorkout: workout, isEditing: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('2025年3月15日'), findsOneWidget);
    await tester.tap(find.byKey(const Key('workoutDateButton')));
    await tester.pumpAndSettle();
    expect(find.text('トレーニング日'), findsWidgets);
    await tester.tap(find.text('14'));
    await tester.tap(find.text('決定'));
    await tester.pumpAndSettle();

    expect(find.text('2025年3月14日'), findsOneWidget);
  });

  testWidgets('editing history does not remove an active workout draft', (
    tester,
  ) async {
    const draftNote = 'あとで続けるトレーニング';
    final encodedDraft = jsonEncode({
      'date': DateTime.now().toIso8601String(),
      'note': draftNote,
      'exercises': [
        {
          'name': 'スクワット',
          'bodyPart': '脚',
          'equipment': 'フリーウェイト',
          'sets': [
            {'weight': 80, 'reps': 5, 'completed': false},
          ],
        },
      ],
    });
    SharedPreferences.setMockInitialValues({
      activeWorkoutDraftStorageKey: encodedDraft,
    });
    final workout = WorkoutRecord(
      date: DateTime(2025, 3, 15, 19, 30),
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: WorkoutPage(initialWorkout: workout, isEditing: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.text('修正を保存'), findsOneWidget);
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(activeWorkoutDraftStorageKey), encodedDraft);
  });

  test('saved workout templates persist', () async {
    SharedPreferences.setMockInitialValues({});
    await WorkoutTemplatePreference.save([
      const SavedWorkoutTemplate(
        name: '胸の日',
        sets: [
          RecordedSet(
            exerciseName: 'ベンチプレス',
            bodyPart: '胸',
            weight: 50,
            reps: 8,
            completed: true,
          ),
        ],
      ),
    ]);

    final templates = await WorkoutTemplatePreference.load();
    expect(templates, hasLength(1));
    expect(templates.single.name, '胸の日');
    expect(templates.single.sets.single.weight, 50);
  });

  testWidgets('starts a workout and adds a set', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    expect(find.text('今日も積み上げよう'), findsOneWidget);
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();

    expect(find.text('ベンチプレス'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('weightField0_1')), '42.5');
    expect(find.text('42.5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('addSetButton')));
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('active_workout_draft'),
      contains('"weight":42.5'),
    );

    await tester.tap(find.byTooltip('最後のセットを削除'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weightField0_4')), findsNothing);
    expect(find.text('最後のセットを削除しました'), findsOneWidget);
    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weightField0_4')), findsOneWidget);
  });

  testWidgets('any exercise can be removed while one always remains', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('スクワット'));
    await tester.tap(find.text('スクワット'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('種目を削除'), findsNWidgets(2));
    await tester.tap(find.byTooltip('種目を削除').first);
    await tester.pumpAndSettle();

    expect(find.text('ベンチプレス'), findsNothing);
    expect(find.text('スクワット'), findsOneWidget);
    expect(find.byTooltip('種目を削除'), findsNothing);
    final preferences = await SharedPreferences.getInstance();
    var savedDraft = preferences.getString(activeWorkoutDraftStorageKey);
    expect(savedDraft, contains('スクワット'));
    expect(savedDraft, isNot(contains('ベンチプレス')));

    expect(find.text('ベンチプレスを削除しました'), findsOneWidget);
    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.text('ベンチプレス'), findsOneWidget);
    expect(find.text('スクワット'), findsOneWidget);
    expect(find.byTooltip('種目を削除'), findsNWidgets(2));
    savedDraft = preferences.getString(activeWorkoutDraftStorageKey);
    expect(savedDraft, contains('ベンチプレス'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('completed workout appears in history', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pump();
    expect(find.text('完了したセットを1つ以上チェックしてください'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('自己ベスト更新'), findsOneWidget);
    await tester.tap(find.text('ホームへ戻る'));
    await tester.pumpAndSettle();

    expect(find.text('クイックスタート'), findsOneWidget);

    await tester.tap(find.byTooltip('マイメニューに保存'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('templateNameField')), '胸の日');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('マイメニュー'), findsOneWidget);
    expect(find.text('胸の日'), findsOneWidget);

    await tester.tap(find.text('履歴'));
    await tester.pumpAndSettle();
    expect(find.text('月間カレンダー'), findsOneWidget);
    expect(find.byKey(const Key('monthlyCalendar')), findsOneWidget);
    expect(find.text('トレーニング履歴'), findsNothing);
    expect(find.byTooltip('カレンダーで見る'), findsNothing);
    expect(find.byTooltip('履歴を検索'), findsOneWidget);
    expect(find.byTooltip('種目ごとの成長を見る'), findsOneWidget);

    final today = DateTime.now();
    await tester.tap(find.byKey(Key('calendarDay${today.day}')));
    await tester.pumpAndSettle();
    expect(find.text('${today.month}月${today.day}日の記録'), findsOneWidget);
    expect(find.text('ベンチプレス'), findsOneWidget);
  });

  testWidgets('deleted saved menu can be restored', (tester) async {
    const template = SavedWorkoutTemplate(
      name: '胸の日',
      sets: [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 60,
          reps: 8,
          completed: true,
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'workout_templates': jsonEncode([template.toJson()]),
    });
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('savedMenu0')), findsOneWidget);
    await tester.tap(find.byTooltip('胸の日を削除'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('savedMenu0')), findsNothing);
    expect(find.text('「胸の日」を削除しました'), findsOneWidget);

    var preferences = await SharedPreferences.getInstance();
    var savedMenus = jsonDecode(
      preferences.getString('workout_templates')!,
    ) as List<dynamic>;
    expect(savedMenus, isEmpty);

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('savedMenu0')), findsOneWidget);
    expect(find.text('「胸の日」を元に戻しました'), findsOneWidget);

    preferences = await SharedPreferences.getInstance();
    savedMenus = jsonDecode(
      preferences.getString('workout_templates')!,
    ) as List<dynamic>;
    expect(savedMenus, hasLength(1));
    expect((savedMenus.single as Map<String, dynamic>)['name'], '胸の日');
  });

  testWidgets('rest timer only starts when enabled', (tester) async {
    SharedPreferences.setMockInitialValues({
      'rest_timer_enabled': false,
      'rest_timer_seconds': 60,
    });
    await RestTimerPreference.load();
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.pump();
    expect(find.byKey(const Key('restTimerBanner')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    SharedPreferences.setMockInitialValues({
      'rest_timer_enabled': true,
      'rest_timer_seconds': 60,
    });
    await RestTimerPreference.load();
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.pump();

    expect(find.byKey(const Key('restTimerBanner')), findsOneWidget);
    expect(find.textContaining('休憩  01:'), findsOneWidget);
  });

  testWidgets('workout draft is saved and leaving asks for confirmation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await RestTimerPreference.load();
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '55');
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('active_workout_draft'),
      contains('"weight":55'),
    );
    expect(preferences.getString('active_workout_draft'), contains('"date":'));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('ホームに戻りますか？'), findsOneWidget);
    await tester.tap(find.text('入力を続ける'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('completeWorkoutButton')), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('ホームに戻りますか？'), findsOneWidget);
    expect(find.textContaining('入力内容は自動保存'), findsOneWidget);

    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activeWorkoutDraftCard')), findsOneWidget);
    expect(find.text('入力途中のトレーニング'), findsOneWidget);
    expect(find.text('新しいトレーニングを始める'), findsOneWidget);

    await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await tester.pumpAndSettle();
    expect(find.text('入力途中のトレーニングを再開しました'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);
  });

  testWidgets('quick start protects a draft and starts with today', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      activeWorkoutDraftStorageKey: jsonEncode({
        'date': DateTime.now().toIso8601String(),
        'note': '',
        'exercises': [
          {
            'name': 'ベンチプレス',
            'bodyPart': '胸',
            'equipment': 'フリーウェイト',
            'sets': [
              {'weight': 55, 'reps': 8, 'completed': false},
            ],
          },
        ],
      }),
    });
    var discarded = false;
    final oldWorkout = WorkoutRecord(
      date: DateTime(2024, 1, 2, 18, 30),
      sets: const [
        RecordedSet(
          exerciseName: 'ラットプルダウン',
          bodyPart: '背中',
          weight: 45,
          reps: 10,
          completed: true,
        ),
      ],
    );
    final draft = WorkoutDraftSummary(
      date: DateTime.now(),
      exerciseNames: const ['ベンチプレス'],
      setCount: 3,
    );
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardPage(
            history: [oldWorkout],
            selectedGym: null,
            onGymChanged: (_) {},
            weeklyTarget: 3,
            onWorkoutCompleted: (_) async {},
            onWorkoutUpdated: (_, _) async {},
            onWorkoutDeleted: (_) async => true,
            workoutTemplates: const [],
            onTemplateSaved: (_) async {},
            onTemplateDeleted: (_) async {},
            workoutDraft: draft,
            onDraftChanged: () async {},
            onDraftDiscarded: () async => discarded = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('recentMenu0')));
    await tester.tap(find.byKey(const Key('recentMenu0')));
    await tester.pumpAndSettle();
    expect(find.text('新しく始めますか？'), findsOneWidget);
    expect(find.text('入力途中の内容は破棄されます。'), findsOneWidget);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(discarded, isFalse);
    expect(find.byKey(const Key('activeWorkoutDraftCard')), findsOneWidget);
    var preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(activeWorkoutDraftStorageKey), isNotNull);

    await tester.tap(find.byKey(const Key('recentMenu0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('破棄して始める'));
    await tester.pumpAndSettle();
    expect(discarded, isTrue);
    preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(activeWorkoutDraftStorageKey), isNull);
    expect(find.text('ラットプルダウン'), findsOneWidget);
    expect(find.text(workoutDateLabel(DateTime.now())), findsOneWidget);
    expect(find.text('2024年1月2日'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('repeating from history protects the active draft', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      activeWorkoutDraftStorageKey: jsonEncode({
        'date': DateTime.now().toIso8601String(),
        'note': '残したいメモ',
        'exercises': [
          {
            'name': 'ベンチプレス',
            'bodyPart': '胸',
            'equipment': 'フリーウェイト',
            'sets': [
              {'weight': 60, 'reps': 8, 'completed': false},
            ],
          },
        ],
      }),
    });
    final workout = WorkoutRecord(
      date: DateTime(2025, 3, 15, 18),
      sets: const [
        RecordedSet(
          exerciseName: 'スクワット',
          bodyPart: '脚',
          weight: 80,
          reps: 5,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutDetailPage(
          workout: workout,
          selectedGym: null,
          onWorkoutCompleted: (_) {},
          onWorkoutUpdated: (_, _) async {},
          onWorkoutDeleted: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('repeatWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.text('入力途中の内容は破棄されます。'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    var preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(activeWorkoutDraftStorageKey),
      contains('残したいメモ'),
    );

    await tester.tap(find.byKey(const Key('repeatWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('破棄して始める'));
    await tester.pumpAndSettle();
    preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(activeWorkoutDraftStorageKey), isNull);
    expect(find.text('スクワット'), findsOneWidget);
    expect(find.text(workoutDateLabel(DateTime.now())), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resumed draft keeps its elapsed time', (tester) async {
    final startedAt = DateTime.now().subtract(const Duration(minutes: 5));
    SharedPreferences.setMockInitialValues({
      activeWorkoutDraftStorageKey: jsonEncode({
        'startedAt': startedAt.toIso8601String(),
        'date': DateTime.now().toIso8601String(),
        'note': '再開テスト',
        'exercises': [
          {
            'name': 'ベンチプレス',
            'bodyPart': '胸',
            'equipment': 'フリーウェイト',
            'sets': [
              {'weight': 55, 'reps': 8, 'completed': false},
            ],
          },
        ],
      }),
    });
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await tester.pumpAndSettle();
    expect(find.textContaining('05:0'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
