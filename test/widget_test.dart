import 'support/legal_consent_fixture.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:muscle_memory/body_weight.dart';
import 'package:muscle_memory/muscle_targets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _setExistingUserPreferences(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues({
    'onboarding_completed': true,
    'legal_consent': acceptedLegalConsentJson,
    ...values,
  });
}

void main() {
  test('legal consent validates confirmations and document versions', () async {
    SharedPreferences.setMockInitialValues({});
    await expectLater(
      LegalConsentPreference.accept(over16: false, terms: true, privacy: true),
      throwsStateError,
    );
    expect(await LegalConsentPreference.load(), isFalse);
    await LegalConsentPreference.accept(over16: true, terms: true, privacy: true);
    expect(await LegalConsentPreference.load(), isTrue);
    final preferences = await SharedPreferences.getInstance();
    final data = jsonDecode(preferences.getString('legal_consent')!) as Map<String, dynamic>;
    expect(data['over16'], isTrue);
    expect(data['accepted'], isTrue);
    expect(DateTime.tryParse(data['acceptedAt'] as String), isNotNull);
    expect(data['termsVersion'], LegalDocuments.termsVersion);
    expect(data['privacyVersion'], LegalDocuments.privacyVersion);
    for (final field in ['termsVersion', 'privacyVersion']) {
      await preferences.setString('legal_consent', jsonEncode({...data, field: 'old'}));
      expect(await LegalConsentPreference.load(), isFalse);
    }
    await preferences.setString('legal_consent', 'invalid');
    expect(await LegalConsentPreference.load(), isFalse);
  });

  testWidgets('legal consent requires all checks and fits a small screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legalConsent')), findsOneWidget);
    expect(find.byKey(const Key('onboarding')), findsNothing);
    final scrollable = find.descendant(
      of: find.byKey(const Key('legalConsent')),
      matching: find.byType(Scrollable),
    );
    Future<void> scrollTo(Finder target) async {
      // Start at the top so lazy children can be found in either direction.
      final position = tester.state<ScrollableState>(scrollable).position;
      while (position.pixels > position.minScrollExtent) {
        await tester.drag(scrollable, const Offset(0, 400));
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(target, 150, scrollable: scrollable);
      await tester.pumpAndSettle();
    }

    final button = find.byKey(const Key('acceptLegalConsent'));
    await scrollTo(button);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    for (final key in ['openTerms', 'openPrivacy']) {
      await scrollTo(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      expect(find.textContaining('正式版公開前の暫定内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    for (final key in ['confirmOver16', 'confirmTerms', 'confirmPrivacy']) {
      await scrollTo(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await scrollTo(button);
      if (key != 'confirmPrivacy') {
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
      }
      expect(tester.takeException(), isNull);
    }
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(await LegalConsentPreference.load(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byKey(const Key('legalConsent')), findsNothing);
  });

  testWidgets('onboarding completes only at the last page and stays completed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'selected_gym': '自宅'});
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding')), findsOneWidget);
    expect(find.text('ジムと一緒にトレーニングを記録'), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('onboarding_completed'), isNull);
    await tester.tap(find.byKey(const Key('onboardingNext')));
    await tester.pumpAndSettle();
    expect(find.text('成長を可視化'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboardingBack')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 4'), findsOneWidget);

    // Closing before completion must not persist the flag.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    expect(find.text('1 / 4'), findsOneWidget);
    for (var page = 2; page <= 4; page++) {
      await tester.tap(find.byKey(const Key('onboardingNext')));
      await tester.pumpAndSettle();
      expect(find.text('$page / 4'), findsOneWidget);
      expect(preferences.getBool('onboarding_completed'), isNull);
    }
    expect(find.text('はじめる'), findsOneWidget);
    await tester.tap(find.text('はじめる'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legalConsent')), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
    for (final key in ['confirmOver16', 'confirmTerms', 'confirmPrivacy']) {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byKey(const Key('acceptLegalConsent')));
    await tester.tap(find.byKey(const Key('acceptLegalConsent')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(preferences.getBool('onboarding_completed'), isTrue);
    expect(preferences.getString('selected_gym'), '自宅');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byKey(const Key('onboarding')), findsNothing);
  });

  testWidgets('onboarding completed preference opens HomeShell directly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true, 'legal_consent': acceptedLegalConsentJson});
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byKey(const Key('onboarding')), findsNothing);
  });

  testWidgets('onboarding fits a small screen and supports swiping', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    for (var page = 1; page <= 4; page++) {
      expect(find.text('$page / 4'), findsOneWidget);
      if (page == 1) {
        expect(find.text('ジムと一緒にトレーニングを記録'), findsOneWidget);
        expect(
          find.textContaining('今後は店舗のマシン情報と連動し、そのジムで使えるマシンや種目を探しやすくする予定です。'),
          findsOneWidget,
        );
      } else if (page == 3) {
        expect(find.textContaining('招待QRコードをMUSCLEMORYで読み取れます。'), findsOneWidget);
        expect(find.textContaining('共有は今後対応予定です。'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      if (page < 4) {
        await tester.drag(find.byType(PageView), const Offset(-300, 0));
        await tester.pumpAndSettle();
      }
    }
    expect(await OnboardingPreference.load(), isFalse);
  });

  testWidgets(
    'hidden body model is released while its selected angle survives',
    (tester) async {
      Future<void> show(bool active) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MuscleMannequinView(scores: const {}, active: active),
          ),
        ),
      );
      await show(false);
      expect(find.byKey(const Key('muscleMannequinAngle')), findsNothing);
      await show(true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('背面'));
      await tester.pumpAndSettle();
      await show(false);
      expect(find.byKey(const Key('muscleMannequinAngle')), findsNothing);
      await show(true);
      await tester.pumpAndSettle();
      final control = tester.widget<SegmentedButton<MuscleMannequinAngle>>(
        find.byKey(const Key('muscleMannequinAngle')),
      );
      expect(control.selected, {MuscleMannequinAngle.back});
    },
  );

  test('rest countdown does not finish before its absolute deadline', () {
    final end = DateTime(2026, 9, 14, 12);
    expect(
      remainingRestSeconds(end, end.subtract(const Duration(microseconds: 1))),
      1,
    );
    expect(
      remainingRestSeconds(
        end,
        end.subtract(const Duration(milliseconds: 1001)),
      ),
      2,
    );
    expect(remainingRestSeconds(end, end), 0);
    expect(remainingRestSeconds(end, end.add(const Duration(seconds: 10))), 0);
  });

  test('training volume is formatted in kilograms', () {
    expect(formatVolumeKg(12500), '12,500');
    expect(formatVolumeKg(987.5), '987.5');
  });

  test('cardio exercises are available without adding weight volume', () {
    final cardioNames = exerciseTemplates
        .where((exercise) => exercise.bodyPart == '有酸素')
        .map((exercise) => exercise.name)
        .toSet();
    expect(cardioNames, {
      'トレッドミル',
      'エアロバイク',
      'クロストレーナー',
      'ステアクライマー',
      'ローイングマシン',
      'ランニング',
      'ウォーキング',
      'サイクリング',
    });
    final workout = WorkoutRecord(
      date: DateTime(2026, 9, 13),
      sets: const [
        RecordedSet(
          exerciseName: 'トレッドミル',
          bodyPart: '有酸素',
          weight: 1,
          reps: 30,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 10,
          completed: true,
        ),
      ],
    );
    expect(workout.volume, 500);
  });

  test('record types preserve metrics and only weights add volume', () {
    final workout = WorkoutRecord(
      date: DateTime(2026, 9, 14),
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          recordType: ExerciseRecordType.weightReps,
          weight: 60,
          reps: 10,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'クランチ',
          bodyPart: '腹',
          recordType: ExerciseRecordType.bodyweightReps,
          weight: 0,
          reps: 20,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'トレッドミル',
          bodyPart: '有酸素',
          recordType: ExerciseRecordType.cardio,
          weight: 0,
          reps: 0,
          durationSeconds: 1800,
          distanceKm: 4.2,
          speedKmh: 8.4,
          inclinePercent: 2,
          completed: true,
        ),
      ],
    );

    final restored = WorkoutRecord.fromJson(workout.toJson());
    expect(restored.volume, 600);
    expect(restored.sets[1].displaySummary, '20 回');
    expect(restored.sets[2].durationSeconds, 1800);
    expect(restored.sets[2].distanceKm, 4.2);
    expect(restored.sets[2].displaySummary, contains('4.2 km'));
  });

  testWidgets('record type selects natural workout fields', (tester) async {
    WorkoutUiPreference.completionCheckEnabled = true;
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workout = WorkoutRecord(
      date: DateTime(2026, 9, 14),
      sets: const [
        RecordedSet(
          exerciseName: 'クランチ',
          bodyPart: '腹',
          recordType: ExerciseRecordType.bodyweightReps,
          weight: 0,
          reps: 15,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'プランク',
          bodyPart: '腹',
          recordType: ExerciseRecordType.timed,
          weight: 0,
          reps: 0,
          durationSeconds: 60,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'トレッドミル',
          bodyPart: '有酸素',
          recordType: ExerciseRecordType.cardio,
          weight: 0,
          reps: 0,
          durationSeconds: 1200,
          distanceKm: 3,
          speedKmh: 9,
          inclinePercent: 1,
          completed: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: WorkoutPage(initialWorkout: workout)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('repsField0_1')), findsOneWidget);
    expect(find.byKey(const Key('weightField0_1')), findsNothing);
    expect(find.byKey(const Key('durationField1_1')), findsOneWidget);
    expect(find.byKey(const Key('repsField1_1')), findsNothing);
    expect(find.byKey(const Key('durationField2_')), findsOneWidget);
    expect(find.byKey(const Key('distanceField2_')), findsOneWidget);
    expect(find.byKey(const Key('speedField2_')), findsOneWidget);
    expect(find.byKey(const Key('inclineField2_')), findsOneWidget);
    expect(find.byKey(const Key('weightField2_1')), findsNothing);
    expect(find.byKey(const Key('addSetButton2')), findsNothing);
  });

  testWidgets('exercise picker selects a category before searching exercises', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ExercisePickerSheet(existingNames: <String>{})),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('部位・カテゴリを選択'), findsOneWidget);
    expect(find.text('トレッドミル'), findsNothing);
    for (final category in ['胸', '背中', '肩', '腕', '脚', '腹', '有酸素', 'HYROX']) {
      expect(find.byKey(Key('bodyPartIllustration$category')), findsOneWidget);
    }
    const assets = {
      '胸': 'chest', '背中': 'back', '肩': 'shoulders',
      '腕': 'arms', '脚': 'legs', '腹': 'abs',
    };
    for (final entry in assets.entries) {
      final image = tester.widget<Image>(find.descendant(
        of: find.byKey(Key('bodyPartIllustration${entry.key}')),
        matching: find.byType(Image),
      ));
      expect((image.image as AssetImage).assetName,
          'assets/category_muscles/${entry.value}.png');
    }
    for (final category in ['有酸素', 'HYROX']) {
      final mark = find.byKey(Key('bodyPartIllustration$category'));
      expect(find.descendant(of: mark, matching: find.byIcon(Icons.directions_run_rounded)), findsOneWidget);
      expect(find.descendant(of: mark, matching: find.byIcon(category == '有酸素'
          ? Icons.monitor_heart_outlined : Icons.fitness_center_rounded)), findsOneWidget);
      expect(find.descendant(of: mark, matching: find.byType(Image)), findsNothing);
    }
    await tester.tap(find.byKey(const Key('exerciseCategory有酸素')));
    await tester.pumpAndSettle();
    expect(find.text('有酸素の種目'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('exerciseSearchField')), 'トレッドミル');
    await tester.pumpAndSettle();
    expect(find.text('トレッドミル'), findsOneWidget);
    expect(find.byKey(const Key('exerciseSearchField')), findsOneWidget);

    tester.view.physicalSize = const Size(320, 480);
    for (final category in ['有酸素', 'HYROX']) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ExercisePickerSheet(existingNames: <String>{})),
      ));
      await tester.pumpAndSettle();
      final card = find.byKey(Key('exerciseCategory$category'));
      await tester.scrollUntilVisible(card, 180, scrollable: find.byType(Scrollable));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('bodyPartIllustration$category')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('$categoryの種目'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('exercise muscle detail explains main and supporting targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final exercise = exerciseTemplates.firstWhere(
      (item) => item.name == 'チェストプレス',
    );
    await tester.pumpWidget(
      MaterialApp(home: ExerciseMuscleDetailPage(exercise: exercise)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exerciseMuscleModel3D')), findsOneWidget);
    expect(find.text('主に使う筋肉'), findsOneWidget);
    expect(find.text('大胸筋'), findsOneWidget);
    expect(find.text('三角筋前部'), findsOneWidget);
    expect(find.text('上腕三頭筋'), findsOneWidget);
  });

  testWidgets('exercise list opens 3D detail for multiple exercises', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExercisePickerSheet(existingNames: {}, menus: []),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('exerciseCategory胸')));
    await tester.pumpAndSettle();

    for (final name in ['ベンチプレス', 'インクラインダンベルプレス']) {
      await tester.tap(find.byKey(Key('exerciseMuscles$name')));
      await tester.pumpAndSettle();
      expect(find.text(name), findsWidgets);
      expect(find.byKey(const Key('exerciseMuscleModel3D')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('custom exercise is created from and inherits its category', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    await CustomExercisePreference.load();
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExercisePickerSheet(existingNames: {}, menus: []),
        ),
      ),
    );
    expect(find.text('自分で種目を作る'), findsNothing);
    await tester.tap(find.byKey(const Key('exerciseCategory背中')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addCustomExerciseForCategory')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customExerciseBodyPartField')), findsNothing);
    expect(
      find.byKey(const Key('inheritedCustomExerciseBodyPart')),
      findsOneWidget,
    );
    expect(find.text('背中'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('customExerciseNameField')),
      'テスト背中種目',
    );
    await tester.tap(find.byKey(const Key('saveCustomExerciseButton')));
    await tester.pumpAndSettle();
    expect(find.text('テスト背中種目'), findsOneWidget);
    expect(CustomExercisePreference.exercises.single.bodyPart, '背中');
  });

  test('workout UI preferences persist', () async {
    _setExistingUserPreferences({});
    await WorkoutUiPreference.load();
    expect(WorkoutUiPreference.completionCheckEnabled, isTrue);
    expect(WorkoutUiPreference.workoutTimerEnabled, isTrue);
    expect(WorkoutUiPreference.workoutDurationEnabled, isTrue);

    await WorkoutUiPreference.setCompletionCheckEnabled(false);
    await WorkoutUiPreference.setWorkoutTimerEnabled(false);
    await WorkoutUiPreference.setWorkoutDurationEnabled(false);
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = true;
    WorkoutUiPreference.workoutDurationEnabled = true;
    await WorkoutUiPreference.load();

    expect(WorkoutUiPreference.completionCheckEnabled, isFalse);
    expect(WorkoutUiPreference.workoutTimerEnabled, isFalse);
    expect(WorkoutUiPreference.workoutDurationEnabled, isFalse);
    await WorkoutUiPreference.setCompletionCheckEnabled(true);
    await WorkoutUiPreference.setWorkoutTimerEnabled(true);
    await WorkoutUiPreference.setWorkoutDurationEnabled(true);
  });

  test(
    'legacy timer settings migrate to one training duration value',
    () async {
      _setExistingUserPreferences({
        'workout_timer_enabled': false,
        'workout_duration_enabled': true,
      });

      await WorkoutUiPreference.load();

      expect(WorkoutUiPreference.workoutTimerEnabled, isFalse);
      expect(WorkoutUiPreference.workoutDurationEnabled, isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('workout_timer_enabled'), isFalse);
      expect(preferences.getBool('workout_duration_enabled'), isFalse);
    },
  );

  test('custom exercises persist between sessions', () async {
    _setExistingUserPreferences({});
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

  test(
    'custom exercises reject duplicates and support update and removal',
    () async {
      _setExistingUserPreferences({});
      await CustomExercisePreference.load();
      const exercise = ExerciseTemplate(
        name: 'ケーブルプレス',
        bodyPart: '胸',
        equipment: 'ケーブル',
        startWeight: 15,
      );

      expect(await CustomExercisePreference.add(exercise), isTrue);
      expect(
        await CustomExercisePreference.add(
          const ExerciseTemplate(
            name: 'ケーブルプレス',
            bodyPart: '肩',
            equipment: 'ケーブル',
            startWeight: 10,
          ),
        ),
        isFalse,
      );
      expect(
        await CustomExercisePreference.add(
          const ExerciseTemplate(
            name: 'ベンチプレス',
            bodyPart: '胸',
            equipment: 'その他',
            startWeight: 10,
          ),
        ),
        isTrue,
      );

      await CustomExercisePreference.remove(
        CustomExercisePreference.exercises.firstWhere(
          (e) => e.name == 'ベンチプレス',
        ),
      );
      final originalId = CustomExercisePreference.exercises.single.exerciseId;
      const updated = ExerciseTemplate(
        name: 'ケーブルプレス改',
        bodyPart: '肩',
        equipment: 'ケーブル',
        startWeight: 17.5,
        startReps: 12,
      );
      expect(await CustomExercisePreference.update('ケーブルプレス', updated), isTrue);
      expect(CustomExercisePreference.exercises.single.name, 'ケーブルプレス改');
      expect(CustomExercisePreference.exercises.single.startWeight, 17.5);

      expect(CustomExercisePreference.exercises.single.exerciseId, originalId);
      await CustomExercisePreference.remove(
        CustomExercisePreference.exercises.single,
      );
      CustomExercisePreference.exercises = [];
      await CustomExercisePreference.load();
      expect(CustomExercisePreference.exercises, isEmpty);
    },
  );

  test('custom gyms persist without standard or duplicate names', () async {
    _setExistingUserPreferences({});
    await CustomGymPreference.load();

    expect(await CustomGymPreference.add('中央体育館'), isTrue);
    expect(await CustomGymPreference.add('中央体育館'), isFalse);
    expect(await CustomGymPreference.add('自宅'), isFalse);
    expect(await CustomGymPreference.update('中央体育館', '市民スポーツセンター'), isTrue);

    CustomGymPreference.gyms = [];
    await CustomGymPreference.load();
    expect(CustomGymPreference.gyms, ['市民スポーツセンター']);

    await CustomGymPreference.remove('市民スポーツセンター');
    expect(CustomGymPreference.gyms, isEmpty);
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
    _setExistingUserPreferences({
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

  test('muscle map periods count completed sets by body part', () {
    final now = DateTime(2026, 9, 12, 12);
    WorkoutRecord workout(DateTime date, String part, int sets) =>
        WorkoutRecord(
          date: date,
          sets: List.generate(
            sets,
            (_) => RecordedSet(
              exerciseName: part,
              bodyPart: part,
              weight: 10,
              reps: 10,
              completed: true,
            ),
          ),
        );
    final history = [
      workout(now.subtract(const Duration(days: 2)), '胸', 2),
      workout(now.subtract(const Duration(days: 20)), '背中', 3),
      workout(now.subtract(const Duration(days: 100)), '脚', 4),
    ];

    expect(bodyPartSetCounts(history, MuscleMapPeriod.week, now: now), {
      '胸': 2,
    });
    expect(bodyPartSetCounts(history, MuscleMapPeriod.month, now: now), {
      '胸': 2,
      '背中': 3,
    });
    expect(
      bodyPartSetCounts(history, MuscleMapPeriod.sixMonths, now: now)['脚'],
      4,
    );
  });

  test('chest press maps primary and secondary muscles independently', () {
    final profile = muscleProfileForExercise('チェストプレス', '胸');
    expect(profile.primary, [MuscleRegion.pectoralisMajor]);
    expect(profile.secondary, contains(MuscleRegion.anteriorDeltoid));
    expect(profile.secondary, contains(MuscleRegion.triceps));

    final scores = muscleScoresForSets(const [
      MuscleSetUsage('チェストプレス', '胸'),
      MuscleSetUsage('チェストプレス', '胸'),
    ]);
    expect(scores[MuscleRegion.pectoralisMajor], 2);
    expect(scores[MuscleRegion.anteriorDeltoid], closeTo(0.7, 0.001));
  });

  testWidgets('3D muscle mannequin switches history periods', (tester) async {
    final workout = WorkoutRecord(
      date: DateTime.now().subtract(const Duration(days: 15)),
      sets: const [
        RecordedSet(
          exerciseName: 'ラットプルダウン',
          bodyPart: '背中',
          weight: 40,
          reps: 10,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BodyMapPage(history: [workout])),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3D筋肉マネキン'), findsOneWidget);
    expect(find.byKey(const Key('muscleModel3D')), findsOneWidget);

    await tester.tap(find.byKey(const Key('musclePeriodmonth')));
    await tester.pumpAndSettle();
    expect(find.text('1ヶ月 ・ 1セット'), findsOneWidget);
    expect(find.text('3方向表示'), findsOneWidget);
    expect(find.text('側面'), findsOneWidget);
    await tester.tap(find.text('背面'));
    await tester.pumpAndSettle();
    final angleControl = tester.widget<SegmentedButton<MuscleMannequinAngle>>(
      find.byKey(const Key('muscleMannequinAngle')),
    );
    expect(angleControl.selected, {MuscleMannequinAngle.back});
    await tester.tap(find.byKey(const Key('musclePeriodweek')));
    await tester.pumpAndSettle();
    expect(find.text('1週間 ・ 0セット'), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<MuscleMannequinAngle>>(
            find.byKey(const Key('muscleMannequinAngle')),
          )
          .selected,
      {MuscleMannequinAngle.back},
    );
    await tester.tap(find.byKey(const Key('musclePeriodmonth')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('muscleCount背中')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('muscleCount背中')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('muscleCount背中'))).data,
      '1セット',
    );
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
    _setExistingUserPreferences({'workout_history': 'broken json'});

    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    expect(find.text('今日も積み上げよう'), findsNothing);
    expect(find.byKey(const Key('startWorkoutButton')), findsOneWidget);
  });

  testWidgets('custom exercises can be created edited deleted and restored', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    await CustomExercisePreference.load();
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: CustomExerciseManagementPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('カスタム種目はまだありません'), findsOneWidget);

    await tester.tap(find.text('種目を作る'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('customExerciseBodyPartField')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('customExerciseEquipmentField')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('customExerciseNameField')),
      'テストプレス',
    );
    await tester.enterText(
      find.byKey(const Key('customExerciseWeightField')),
      '17.5',
    );
    await tester.enterText(
      find.byKey(const Key('customExerciseRepsField')),
      '12',
    );
    await tester.tap(find.byKey(const Key('saveCustomExerciseButton')));
    await tester.pumpAndSettle();

    expect(find.text('テストプレス'), findsOneWidget);
    expect(find.text('胸 ・ マシン ・ 17.5kg × 12回'), findsOneWidget);
    expect(CustomExercisePreference.exercises, hasLength(1));

    await tester.tap(find.byTooltip('テストプレスを編集'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('customExerciseNameField')),
      'テストプレス改',
    );
    await tester.enterText(
      find.byKey(const Key('customExerciseWeightField')),
      '20',
    );
    await tester.tap(find.byKey(const Key('saveCustomExerciseButton')));
    await tester.pumpAndSettle();
    expect(find.text('テストプレス改'), findsOneWidget);
    expect(find.text('胸 ・ マシン ・ 20kg × 12回'), findsOneWidget);

    await tester.tap(find.byTooltip('テストプレス改を削除'));
    await tester.pumpAndSettle();
    expect(find.text('カスタム種目はまだありません'), findsOneWidget);
    expect(find.text('「テストプレス改」を削除しました'), findsOneWidget);

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.text('テストプレス改'), findsOneWidget);
    expect(find.text('「テストプレス改」を元に戻しました'), findsOneWidget);

    CustomExercisePreference.exercises = [];
    await CustomExercisePreference.load();
    expect(CustomExercisePreference.exercises.single.name, 'テストプレス改');
    expect(CustomExercisePreference.exercises.single.startWeight, 20);
    expect(CustomExercisePreference.exercises.single.startReps, 12);
  });

  testWidgets('custom gyms can be created edited deleted and restored', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    await CustomGymPreference.load();
    String? selectedGym = '中央体育館';
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: CustomGymManagementPage(
          selectedGym: selectedGym,
          onSelectedGymChanged: (gym) async => selectedGym = gym,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addCustomGymButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('customGymNameField')),
      '中央体育館',
    );
    await tester.tap(find.byKey(const Key('saveCustomGymButton')));
    await tester.pumpAndSettle();
    expect(find.text('中央体育館'), findsOneWidget);
    expect(CustomGymPreference.gyms, ['中央体育館']);

    await tester.tap(find.byKey(const Key('gymActions中央体育館')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('名前を変更'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('customGymNameField')),
      '市民スポーツセンター',
    );
    await tester.tap(find.byKey(const Key('saveCustomGymButton')));
    await tester.pumpAndSettle();
    expect(find.text('市民スポーツセンター'), findsOneWidget);
    expect(selectedGym, '市民スポーツセンター');

    await tester.tap(find.byKey(const Key('gymActions市民スポーツセンター')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();
    expect(find.text('市民スポーツセンター'), findsNothing);
    expect(find.text('「市民スポーツセンター」を削除しました'), findsOneWidget);
    expect(selectedGym, isNull);

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.text('市民スポーツセンター'), findsOneWidget);
    expect(find.text('「市民スポーツセンター」を元に戻しました'), findsOneWidget);
    expect(selectedGym, '市民スポーツセンター');

    CustomGymPreference.gyms = [];
    await CustomGymPreference.load();
    expect(CustomGymPreference.gyms, ['市民スポーツセンター']);
  });

  testWidgets('profile display name persists and empty values reset it', (
    tester,
  ) async {
    _setExistingUserPreferences({});

    Future<void> openProfile() async {
      await tester.pumpWidget(const MuscleMemoryApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();
    }

    Future<void> saveName(String name) async {
      await tester.tap(find.byKey(const Key('editProfileDisplayName')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profileDisplayNameField')),
        name,
      );
      await tester.tap(find.byKey(const Key('saveProfileDisplayName')));
      await tester.pumpAndSettle();
    }

    String? shownName() => tester
        .widget<Text>(find.byKey(const Key('profileDisplayName')))
        .data;

    await openProfile();
    expect(shownName(), 'MUSCLEMORYユーザー');
    await saveName('  トレーニング太郎  ');
    expect(shownName(), 'トレーニング太郎');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('profile_display_name'), 'トレーニング太郎');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await openProfile();
    expect(shownName(), 'トレーニング太郎');
    await tester.tap(find.byKey(const Key('editProfileDisplayName')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(
        find.byKey(const Key('profileDisplayNameField')),
      ).initialValue,
      'トレーニング太郎',
    );
    await tester.enterText(
      find.byKey(const Key('profileDisplayNameField')),
      '保存しない名前',
    );
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(shownName(), 'トレーニング太郎');
    expect(preferences.getString('profile_display_name'), 'トレーニング太郎');

    await saveName('');
    expect(shownName(), 'MUSCLEMORYユーザー');
    expect(preferences.getString('profile_display_name'), '');
    await saveName('別の名前');
    await saveName('  　 ');
    expect(shownName(), 'MUSCLEMORYユーザー');
    expect(preferences.getString('profile_display_name'), '');

    await saveName(List.filled(30, '長い表示名').join());
    expect(tester.takeException(), isNull);
    final nameText = tester.widget<Text>(
      find.byKey(const Key('profileDisplayName')),
    );
    expect(nameText.maxLines, 2);
    expect(nameText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('profile sections are ordered and backup tools open separately', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    await WorkoutUiPreference.load();
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('MUSCLEMORYユーザー'), findsOneWidget);
    expect(find.byKey(const Key('editProfileDisplayName')), findsOneWidget);
    expect(find.byKey(const Key('trainingSettingsButton')), findsOneWidget);
    expect(find.byKey(const Key('trainerQrButton')), findsOneWidget);
    expect(find.byKey(const Key('contactButton')), findsOneWidget);
    expect(find.byKey(const Key('appAboutButton')), findsOneWidget);
    expect(find.byKey(const Key('locationSettingsButton')), findsOneWidget);
    expect(find.text('いつもの場所'), findsOneWidget);
    expect(find.text('カスタム場所'), findsNothing);
    expect(find.text('重量の単位'), findsNothing);
    expect(find.byKey(const Key('savedMenuManagementButton')), findsNothing);
    expect(
      find.byKey(const Key('customExerciseManagementButton')),
      findsNothing,
    );

    final trainingY = tester.getTopLeft(find.text('トレーニング設定').first).dy;
    expect(find.text('アカウント関連'), findsNothing);
    expect(find.text('Supabaseクラウド'), findsNothing);
    final otherY = tester.getTopLeft(find.text('その他設定')).dy;
    final backupY = tester.getTopLeft(find.text('バックアップ・データ管理').first).dy;
    expect(trainingY, lessThan(otherY));
    expect(otherY, lessThan(backupY));

    await tester.tap(find.byKey(const Key('trainerQrButton')));
    // The native camera remains initializing in a widget-test environment.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('trainerQrPage')), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();


    await tester.ensureVisible(
      find.byKey(const Key('backupDataManagementButton')),
    );
    await tester.tap(find.byKey(const Key('backupDataManagementButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exportBackupFile')), findsOneWidget);
    expect(find.byKey(const Key('importBackupFile')), findsOneWidget);
    expect(find.text('バックアップをコピー'), findsNothing);
    expect(find.text('バックアップを読み込む'), findsNothing);
  });

  testWidgets(
    'training settings are grouped and rest timer depends on checks',
    (tester) async {
      _setExistingUserPreferences({
        'completion_check_enabled': false,
        'workout_timer_enabled': true,
        'workout_duration_enabled': true,
        'rest_timer_enabled': true,
        'rest_timer_seconds': 90,
      });
      await RestTimerPreference.load();
      await WorkoutUiPreference.load();
      await tester.pumpWidget(const MuscleMemoryApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('completionCheckSwitch')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('trainingSettingsButton')),
      );
      await tester.tap(find.byKey(const Key('trainingSettingsButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('completionCheckSwitch')), findsOneWidget);
      expect(find.byKey(const Key('trainingDurationSwitch')), findsOneWidget);
      expect(find.byKey(const Key('workoutTimerSwitch')), findsNothing);
      expect(find.byKey(const Key('workoutDurationSwitch')), findsNothing);
      expect(find.text('トレーニング時間'), findsOneWidget);
      expect(find.text('トレーニングタイマー'), findsNothing);
      expect(find.text('筋トレ時間'), findsNothing);
      expect(find.byKey(const Key('restTimerSwitch')), findsNothing);
      expect(
        find.byKey(const Key('savedMenuManagementButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('customExerciseManagementButton')),
        findsOneWidget,
      );
      final completionY = tester
          .getTopLeft(find.byKey(const Key('completionCheckSwitch')))
          .dy;
      final timerY = tester
          .getTopLeft(find.byKey(const Key('trainingDurationSwitch')))
          .dy;
      final menuY = tester
          .getTopLeft(find.byKey(const Key('savedMenuManagementButton')))
          .dy;
      final customExerciseY = tester
          .getTopLeft(find.byKey(const Key('customExerciseManagementButton')))
          .dy;
      expect(completionY, lessThan(timerY));
      expect(timerY, lessThan(menuY));
      expect(menuY, lessThan(customExerciseY));
      expect(find.byKey(const Key('restTimerDurationButton')), findsNothing);
      await tester.tap(find.byKey(const Key('completionCheckSwitch')));
      await tester.pumpAndSettle();
      expect(RestTimerPreference.enabled, isFalse);
      expect(find.byKey(const Key('restTimerSwitch')), findsOneWidget);
      final restY = tester
          .getTopLeft(find.byKey(const Key('restTimerSwitch')))
          .dy;
      final timerAfterRestY = tester
          .getTopLeft(find.byKey(const Key('trainingDurationSwitch')))
          .dy;
      expect(completionY, lessThan(restY));
      expect(restY, lessThan(timerAfterRestY));
      await tester.tap(find.byKey(const Key('restTimerSwitch')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('restTimerDurationButton')), findsOneWidget);

      await tester.tap(find.byKey(const Key('trainingDurationSwitch')));
      await tester.pumpAndSettle();
      expect(WorkoutUiPreference.workoutTimerEnabled, isFalse);
      expect(WorkoutUiPreference.workoutDurationEnabled, isFalse);
      await WorkoutUiPreference.setTrainingDurationEnabled(true);
    },
  );

  testWidgets('previously selected custom gym is migrated for reuse', (
    tester,
  ) async {
    _setExistingUserPreferences({'selected_gym': '以前の体育館'});
    CustomGymPreference.gyms = [];

    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    expect(CustomGymPreference.gyms, ['以前の体育館']);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('custom_gyms'), contains('以前の体育館'));
  });

  testWidgets('saved custom gyms appear in the location picker', (
    tester,
  ) async {
    _setExistingUserPreferences({
      'custom_gyms': jsonEncode(['中央体育館', '会社のジム']),
    });
    await CustomGymPreference.load();
    String? selected;
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                selected = await showGymPicker(context, null);
              },
              child: const Text('場所を選ぶ'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('場所を選ぶ'));
    await tester.pumpAndSettle();
    expect(find.text('中央体育館'), findsOneWidget);
    expect(find.text('会社のジム'), findsOneWidget);
    expect(find.text('場所を追加'), findsNothing);

    await tester.tap(find.text('会社のジム'));
    await tester.pumpAndSettle();
    expect(selected, '会社のジム');
  });

  testWidgets('location settings chooses a usual place without adding there', (
    tester,
  ) async {
    _setExistingUserPreferences({
      'custom_gyms': jsonEncode(['中央体育館']),
    });
    await CustomGymPreference.load();
    String? selectedGym;
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: CustomGymManagementPage(
          selectedGym: selectedGym,
          onSelectedGymChanged: (gym) async => selectedGym = gym,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('いつもの場所'), findsOneWidget);
    expect(find.text('カスタム場所'), findsNothing);
    expect(find.byKey(const Key('addCustomGymButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('preferredGym自宅')));
    await tester.pumpAndSettle();
    expect(selectedGym, '自宅');
    expect(CustomGymPreference.gyms, ['中央体育館']);
  });

  test('version 3 backup preserves workouts body weights and settings', () {
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
      bodyWeights: [
        BodyWeightEntry(
          id: 'weight-1',
          recordedAt: DateTime(2026, 9, 12, 7),
          weightKg: 82.5,
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
      customGyms: const ['中央体育館'],
      selectedGym: 'テストジム',
      restTimerEnabled: true,
      restTimerSeconds: 120,
    );

    final restored = MuscleMemoryBackup.fromJson(backup.toJson());

    expect(backup.toJson()['app'], 'MUSCLEMORY');
    expect(backup.toJson()['version'], 3);
    expect(restored.workouts.single.sets.single.weight, 52.5);
    expect(restored.workoutTemplates.single.name, '胸の日');
    expect(restored.bodyWeights.single.weightKg, 82.5);
    expect(restored.customExercises.single.startWeight, 12.5);
    expect(restored.customGyms, ['中央体育館']);
    expect(restored.selectedGym, 'テストジム');
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
    expect(restored.customGyms, isEmpty);
  });

  test('invalid and unsupported backups are rejected before import', () {
    expect(
      () => MuscleMemoryBackup.fromJson({
        'app': 'MUSCLEMORY',
        'version': 3,
        'workouts': 'invalid',
      }),
      throwsFormatException,
    );
    expect(
      () => MuscleMemoryBackup.fromJson({
        'app': 'MUSCLEMORY',
        'version': 99,
        'workouts': <dynamic>[],
      }),
      throwsFormatException,
    );
  });

  testWidgets('about page uses the official MUSCLEMORY name', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppAboutPage()));
    await tester.pumpAndSettle();

    expect(find.text('MUSCLEMORY'), findsOneWidget);
    expect(find.text('バージョン 1.0.0'), findsOneWidget);
    expect(find.text('端末内への保存'), findsOneWidget);
    expect(find.text('クラウド同期'), findsOneWidget);
    expect(find.text('バックアップ'), findsOneWidget);
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

  test('latest exercise sets are selected independently of history order', () {
    WorkoutRecord workout(DateTime date, double weight, String exercise) =>
        WorkoutRecord(
          date: date,
          sets: [
            RecordedSet(
              exerciseName: exercise,
              bodyPart: '胸',
              weight: weight,
              reps: 8,
              completed: true,
            ),
          ],
        );
    final older = workout(DateTime(2026, 1, 1), 50, 'ベンチプレス');
    final unrelated = workout(DateTime(2026, 1, 5), 80, 'スクワット');
    final newest = workout(DateTime(2026, 1, 3), 60, 'ベンチプレス');

    final sets = latestSetsForExercise([older, unrelated, newest], 'ベンチプレス');

    expect(sets, hasLength(1));
    expect(sets.single.weight, 60);
    expect(latestSetsForExercise([older], 'スクワット'), isEmpty);
  });

  test('history search matches dates as well as workout details', () {
    final workout = WorkoutRecord(
      date: DateTime(2026, 9, 12, 18, 30),
      gymName: '中央体育館',
      note: 'フォーム確認',
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

    expect(workoutMatchesQuery(workout, '2026年9月12日'), isTrue);
    expect(workoutMatchesQuery(workout, '2026-09-12'), isTrue);
    expect(workoutMatchesQuery(workout, '9/12'), isTrue);
    expect(workoutMatchesQuery(workout, '９・１２'), isTrue);
    expect(workoutMatchesQuery(workout, '体育館'), isTrue);
    expect(workoutMatchesQuery(workout, 'ベンチプレス'), isFalse);
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
            onWorkoutCompleted: (_) async {},
            onWorkoutUpdated: (_, _) async {},
            onWorkoutDeleted: (_) async => true,
          ),
        ),
      ),
    );

    expect(find.text('テストジム'), findsOneWidget);
    expect(find.text('フォームを丁寧に'), findsOneWidget);
  });

  testWidgets('history search shows result counts and can be cleared', (
    tester,
  ) async {
    WorkoutRecord workout(DateTime date, String exercise) => WorkoutRecord(
      date: date,
      sets: [
        RecordedSet(
          exerciseName: exercise,
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HistorySearchPage(
          history: [
            workout(DateTime(2026, 9, 12), 'ベンチプレス'),
            workout(DateTime(2026, 8, 3), 'ダンベルフライ'),
          ],
          selectedGym: null,
          onWorkoutCompleted: (_) async {},
          onWorkoutUpdated: (_, _) async {},
          onWorkoutDeleted: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全2件'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('historySearchField')), '9/12');
    await tester.pumpAndSettle();
    expect(find.text('1件の記録'), findsOneWidget);
    expect(find.text('ベンチプレス'), findsOneWidget);
    expect(find.text('ダンベルフライ'), findsNothing);

    await tester.tap(find.byTooltip('検索をクリア'));
    await tester.pumpAndSettle();
    expect(find.text('全2件'), findsOneWidget);
    expect(find.byType(HistoryCard), findsNWidgets(2));
  });

  testWidgets('removing home summaries preserves history detail', (
    tester,
  ) async {
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
    _setExistingUserPreferences({
      'workout_history': jsonEncode([workout.toJson()]),
    });
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lastWorkoutCard')), findsNothing);
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('calendarDay${DateTime.now().day}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(HistoryCard));
    await tester.pumpAndSettle();

    expect(find.text('トレーニング詳細'), findsOneWidget);
    expect(find.text('ラットプルダウン'), findsOneWidget);
    expect(find.text('肩を下げる'), findsOneWidget);
    expect(find.text('この内容でもう一度'), findsOneWidget);
  });

  testWidgets('history can return to the current month in one tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MonthlyHistoryPage(
          history: const [],
          selectedGym: null,
          onWorkoutCompleted: (_) async {},
          onWorkoutUpdated: (_, _) async {},
          onWorkoutDeleted: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(find.text('${now.year}年 ${now.month}月'), findsOneWidget);
    expect(find.byKey(const Key('historyCurrentMonthButton')), findsNothing);

    await tester.tap(find.byTooltip('前の月'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('historyCurrentMonthButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('historyCurrentMonthButton')));
    await tester.pumpAndSettle();
    expect(find.text('${now.year}年 ${now.month}月'), findsOneWidget);
    expect(find.byKey(const Key('historyCurrentMonthButton')), findsNothing);
  });

  testWidgets('an existing workout date can be changed', (tester) async {
    _setExistingUserPreferences({});
    final workout = WorkoutRecord(
      date: DateTime(2025, 3, 15, 19, 30),
      durationSeconds: 120,
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
    expect(find.text('2分'), findsOneWidget);
    final recordedTimer = tester
        .widget<Text>(find.byKey(const Key('workoutElapsedLabel')))
        .data;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.widget<Text>(find.byKey(const Key('workoutElapsedLabel'))).data,
      recordedTimer,
    );
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
    _setExistingUserPreferences({
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
    _setExistingUserPreferences({});
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

  testWidgets('saved menus can be renamed reordered deleted and restored', (
    tester,
  ) async {
    const chest = SavedWorkoutTemplate(
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
    );
    const legs = SavedWorkoutTemplate(
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
    _setExistingUserPreferences({});
    var saved = <SavedWorkoutTemplate>[chest, legs];
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SavedMenuManagementPage(
          initialTemplates: saved,
          onChanged: (templates) async {
            saved = List<SavedWorkoutTemplate>.from(templates);
            await WorkoutTemplatePreference.save(saved);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ベンチプレス ・ 1セット'), findsOneWidget);

    await tester.tap(find.byTooltip('胸の日の名前を変更'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('renameTemplateField')),
      '胸メイン',
    );
    await tester.tap(find.byKey(const Key('saveTemplateNameButton')));
    await tester.pumpAndSettle();
    expect(find.text('胸メイン'), findsOneWidget);
    expect(saved.first.name, '胸メイン');

    await tester.tap(find.byTooltip('胸メインの名前を変更'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('renameTemplateField')), '脚の日');
    await tester.tap(find.byKey(const Key('saveTemplateNameButton')));
    await tester.pumpAndSettle();
    expect(find.text('同じ名前のメニューがあります'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('reorderMenu1')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(saved.first.name, '脚の日');

    await tester.tap(find.byTooltip('胸メインを削除'));
    await tester.pumpAndSettle();
    expect(saved.map((item) => item.name), ['脚の日']);
    expect(find.text('「胸メイン」を削除しました'), findsOneWidget);

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(saved.map((item) => item.name), ['脚の日', '胸メイン']);
    final persisted = await WorkoutTemplatePreference.load();
    expect(persisted.map((item) => item.name), ['脚の日', '胸メイン']);
  });

  testWidgets('a menu is created directly with multiple ordered exercises', (
    tester,
  ) async {
    List<SavedWorkoutTemplate> saved = [];
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SavedMenuManagementPage(
          initialTemplates: const [],
          onChanged: (templates) async => saved = templates,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('createSavedMenuButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('templateNameField')), '胸の日');
    await tester.tap(find.byKey(const Key('saveNewTemplateNameButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exerciseCategory胸')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('selectExercisebench_press')));
    await tester.enterText(
      find.byKey(const Key('exerciseSearchField')),
      'ダンベルフライ',
    );
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('selectExercisedumbbell_fly')),
    );
    await tester.tap(find.byKey(const Key('selectExercisedumbbell_fly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menuExerciseOrderList')), findsOneWidget);
    await tester.tap(find.byKey(const Key('saveCreatedMenuButton')));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.name, '胸の日');
    expect(saved.single.exerciseNames, ['ベンチプレス', 'ダンベルフライ']);
    expect(saved.single.sets, hasLength(2));
  });

  testWidgets('previous sets can be applied and completed together', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    final initial = WorkoutRecord(
      date: DateTime(2025, 1, 1),
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 40,
          reps: 10,
          completed: true,
        ),
      ],
    );
    final latest = WorkoutRecord(
      date: DateTime(2026, 2, 2),
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 60,
          reps: 8,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 62.5,
          reps: 6,
          completed: true,
        ),
      ],
    );
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutPage(history: [latest], initialWorkout: initial),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.descendant(
              of: find.byKey(const Key('weightField0_1')),
              matching: find.byType(TextFormField),
            ),
          )
          .initialValue,
      '40',
    );
    expect(find.text('完了 0 / 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('applyPrevious0')));
    await tester.pumpAndSettle();
    expect(find.text('ベンチプレスに前回の記録を反映しました'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.descendant(
              of: find.byKey(const Key('weightField0_1')),
              matching: find.byType(TextFormField),
            ),
          )
          .initialValue,
      '60',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.descendant(
              of: find.byKey(const Key('weightField0_2')),
              matching: find.byType(TextFormField),
            ),
          )
          .initialValue,
      '62.5',
    );
    expect(find.text('完了 0 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggleAllSets0')));
    await tester.pumpAndSettle();
    expect(find.text('完了 2 / 2'), findsOneWidget);
    expect(find.text('すべて解除'), findsOneWidget);
    var preferences = await SharedPreferences.getInstance();
    var draft = jsonDecode(
      preferences.getString(activeWorkoutDraftStorageKey)!,
    ) as Map<String, dynamic>;
    var sets =
        (draft['exercises'] as List<dynamic>).first['sets'] as List<dynamic>;
    expect(sets.every((set) => set['completed'] == true), isTrue);

    await tester.tap(find.byKey(const Key('toggleAllSets0')));
    await tester.pumpAndSettle();
    expect(find.text('完了 0 / 2'), findsOneWidget);
    preferences = await SharedPreferences.getInstance();
    draft = jsonDecode(
      preferences.getString(activeWorkoutDraftStorageKey)!,
    ) as Map<String, dynamic>;
    sets = (draft['exercises'] as List<dynamic>).first['sets'] as List<dynamic>;
    expect(sets.every((set) => set['completed'] == false), isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new workout starts empty and supports adding sets', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    expect(find.text('今日も積み上げよう'), findsNothing);
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emptyWorkoutExercises')), findsOneWidget);
    expect(find.text('種目はまだありません'), findsOneWidget);
    expect(find.text('ベンチプレス'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exerciseCategory胸')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ベンチプレス'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emptyWorkoutExercises')), findsNothing);
    expect(find.text('ベンチプレス'), findsOneWidget);
    expect(find.byKey(const Key('weightField0_1')), findsOneWidget);
    expect(find.byKey(const Key('weightField0_2')), findsNothing);

    await tester.enterText(find.byKey(const Key('weightField0_1')), '42.5');
    expect(find.text('42.5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('addSetButton')));
    await tester.pump();
    expect(find.byKey(const Key('weightField0_2')), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('active_workout_draft'),
      contains('"weight":42.5'),
    );

    await tester.ensureVisible(find.byKey(const Key('deleteSet0_2')));
    await tester.tap(find.byKey(const Key('deleteSet0_2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weightField0_2')), findsNothing);
  });

  testWidgets('an empty draft from any app version becomes a fresh workout', (
    tester,
  ) async {
    _setExistingUserPreferences({
      activeWorkoutDraftStorageKey: jsonEncode({
        'startedAt': DateTime.now()
            .subtract(const Duration(minutes: 10))
            .toIso8601String(),
        'elapsedSeconds': 600,
        'date': DateTime.now().toIso8601String(),
        'note': '',
        'exercises': <dynamic>[],
      }),
    });

    await tester.pumpWidget(const MaterialApp(home: WorkoutPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emptyWorkoutExercises')), findsOneWidget);
    expect(find.textContaining('00:00 ・'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(activeWorkoutDraftStorageKey), isNull);
  });

  testWidgets('disabled workout UI hides checks and timer but still saves', (
    tester,
  ) async {
    _setExistingUserPreferences({
      'completion_check_enabled': false,
      'workout_timer_enabled': false,
      'workout_duration_enabled': false,
    });
    await WorkoutUiPreference.load();
    addTearDown(() async {
      WorkoutUiPreference.completionCheckEnabled = true;
      WorkoutUiPreference.workoutTimerEnabled = true;
    });
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('workoutElapsedLabel'))).data,
      '店舗未選択',
    );
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exerciseCategory胸')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ベンチプレス'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.circle_outlined), findsNothing);
    expect(find.byKey(const Key('toggleAllSets0')), findsNothing);
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.text('1セットを記録します。'), findsOneWidget);
  });

  testWidgets('active workout can be deleted without leaving a draft', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = true;
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('exerciseCategory脚')),
      180,
      scrollable: find
          .descendant(
            of: find.byType(ExercisePickerSheet),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exerciseCategory脚')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('スクワット'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('deleteWorkoutDraftButton')));
    await tester.pumpAndSettle();
    expect(find.text('記録をすべて削除しますか？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDeleteWorkoutDraftButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('startWorkoutButton')), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(activeWorkoutDraftStorageKey), isNull);
  });

  testWidgets('last exercise can be removed and empty state stays stable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _setExistingUserPreferences({});
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exerciseCategory脚')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('スクワット'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('種目を削除'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('種目を削除'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emptyWorkoutExercises')), findsOneWidget);
    expect(find.text('スクワット'), findsNothing);
    expect(find.text('ベンチプレス'), findsNothing);
    expect(find.byTooltip('種目を削除'), findsNothing);
    final preferences = await SharedPreferences.getInstance();
    var savedDraft = preferences.getString(activeWorkoutDraftStorageKey);
    expect(savedDraft, contains('"exercises":[]'));
    expect(savedDraft, isNot(contains('ベンチプレス')));
    final savedDraftJson = jsonDecode(savedDraft!) as Map<String, dynamic>;
    expect(savedDraftJson['timerStopped'], isTrue);
    expect(savedDraftJson['elapsedSeconds'], isA<int>());

    expect(find.text('スクワットを削除しました'), findsOneWidget);

    final stoppedTimer = tester
        .widget<Text>(find.byKey(const Key('workoutElapsedLabel')))
        .data;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.widget<Text>(find.byKey(const Key('workoutElapsedLabel'))).data,
      stoppedTimer,
    );

    await tester.pump();
    expect(find.byKey(const Key('emptyWorkoutExercises')), findsOneWidget);
    expect(find.text('ベンチプレス'), findsNothing);

    await tester.tap(find.byKey(const Key('workoutDateButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('emptyWorkoutExercises')), findsOneWidget);
    expect(find.text('ベンチプレス'), findsNothing);

    savedDraft = preferences.getString(activeWorkoutDraftStorageKey);
    expect(savedDraft, contains('"exercises":[]'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('completed workout appears in history', (tester) async {
    _setExistingUserPreferences({});
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pump();
    expect(find.text('完了したセットを1つ以上チェックしてください'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exerciseCategory胸')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ベンチプレス'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('自己ベスト更新'), findsOneWidget);
    expect(find.text('共有画像を確認'), findsOneWidget);
    expect(find.text('ホームへ戻る'), findsOneWidget);
    final stoppedTimer = tester
        .widget<Text>(find.byKey(const Key('workoutElapsedLabel')))
        .data;
    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.widget<Text>(find.byKey(const Key('workoutElapsedLabel'))).data,
      stoppedTimer,
    );
    await tester.tap(find.text('ホームへ戻る'));
    await tester.pumpAndSettle();

    expect(find.text('クイックスタート'), findsNothing);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
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

  testWidgets('deleted workout can be restored from history', (tester) async {
    final workout = WorkoutRecord(
      date: DateTime.now(),
      note: '削除復元テスト',
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
    _setExistingUserPreferences({
      'workout_history': jsonEncode([workout.toJson()]),
    });
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('calendarDay${DateTime.now().day}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(HistoryCard));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('記録を削除'));
    await tester.pumpAndSettle();
    expect(find.text('削除後も直後なら元に戻せます。'), findsOneWidget);
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();

    expect(find.text('トレーニング記録を削除しました'), findsOneWidget);
    expect(find.byType(HistoryCard), findsNothing);
    var preferences = await SharedPreferences.getInstance();
    expect(
      jsonDecode(preferences.getString('workout_history')!) as List<dynamic>,
      isEmpty,
    );

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.text('トレーニング記録を元に戻しました'), findsOneWidget);
    expect(find.byType(HistoryCard), findsOneWidget);
    preferences = await SharedPreferences.getInstance();
    final restored =
        jsonDecode(preferences.getString('workout_history')!) as List<dynamic>;
    expect(restored, hasLength(1));
    expect(jsonEncode(restored.single), contains('削除復元テスト'));
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
    _setExistingUserPreferences({
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
    final platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    _setExistingUserPreferences({
      'rest_timer_enabled': false,
      'rest_timer_seconds': 60,
    });
    await RestTimerPreference.load();
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exerciseCategory胸')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ベンチプレス'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.pump();
    expect(find.byKey(const Key('restTimerBanner')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    _setExistingUserPreferences({
      'rest_timer_enabled': true,
      'rest_timer_seconds': 1,
    });
    await RestTimerPreference.load();
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exerciseCategory胸')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ベンチプレス'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.pump();

    expect(find.byKey(const Key('restTimerBanner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('startRestTimerButton')));
    await tester.pump();
    expect(find.text('休憩  00:01'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(
      platformCalls.any((call) => call.method == 'SystemSound.play'),
      isTrue,
    );
  });

  testWidgets('workout draft is saved and leaving asks for confirmation', (
    tester,
  ) async {
    _setExistingUserPreferences({});
    await RestTimerPreference.load();
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exerciseCategory胸')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ベンチプレス'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
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
    expect(find.text('トレーニングを中断しますか？'), findsOneWidget);
    await tester.tap(find.text('入力を続ける'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('completeWorkoutButton')), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('トレーニングを中断しますか？'), findsOneWidget);
    expect(find.textContaining('入力内容は自動保存'), findsOneWidget);

    await tester.tap(find.text('中断する'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activeWorkoutDraftCard')), findsOneWidget);
    expect(find.text('入力途中のトレーニング'), findsOneWidget);
    expect(find.text('新しいトレーニングを始める'), findsOneWidget);

    var pausedDraft = jsonDecode(
      preferences.getString(activeWorkoutDraftStorageKey)!,
    ) as Map<String, dynamic>;
    final pausedElapsed = pausedDraft['elapsedSeconds'];
    expect(pausedElapsed, isA<int>());
    await tester.pump(const Duration(seconds: 3));
    pausedDraft = jsonDecode(
      preferences.getString(activeWorkoutDraftStorageKey)!,
    ) as Map<String, dynamic>;
    expect(pausedDraft['elapsedSeconds'], pausedElapsed);

    await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await tester.pumpAndSettle();
    expect(find.text('入力途中のトレーニングを再開しました'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);
  });

  testWidgets('saved menu start protects a draft and starts with today', (
    tester,
  ) async {
    _setExistingUserPreferences({
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
            onWorkoutCompleted: (_) async {},
            onWorkoutUpdated: (_, _) async {},
            onWorkoutDeleted: (_) async => true,
            workoutTemplates: [
              SavedWorkoutTemplate(name: '背中メニュー', sets: oldWorkout.sets),
            ],
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

    await tester.ensureVisible(find.byKey(const Key('savedMenu0')));
    await tester.tap(find.byKey(const Key('savedMenu0')));
    await tester.pumpAndSettle();
    expect(find.text('新しく始めますか？'), findsOneWidget);
    expect(find.text('入力途中の内容は破棄されます。'), findsOneWidget);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(discarded, isFalse);
    expect(find.byKey(const Key('activeWorkoutDraftCard')), findsOneWidget);
    var preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(activeWorkoutDraftStorageKey), isNotNull);

    await tester.tap(find.byKey(const Key('savedMenu0')));
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
    _setExistingUserPreferences({
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
          onWorkoutCompleted: (_) async {},
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

  testWidgets(
    'frozen draft restores exact duration without rewriting its date',
    (tester) async {
      final draft = jsonEncode({
        'startedAt': DateTime(2025, 1, 1).toIso8601String(),
        'elapsedSeconds': 543,
        'timerStopped': true,
        'date': DateTime(2026, 8, 1).toIso8601String(),
        'note': '確定したメモ',
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
      });
      _setExistingUserPreferences({
        activeWorkoutDraftStorageKey: draft,
      });
      await tester.pumpWidget(const MuscleMemoryApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
      await tester.pumpAndSettle();
      final label = find.byKey(const Key('workoutElapsedLabel'));
      expect(tester.widget<Text>(label).data, contains('09:03'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 10));
      expect(tester.widget<Text>(label).data, contains('09:03'));
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(activeWorkoutDraftStorageKey), draft);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('removing the final set freezes time including after undo', (
    tester,
  ) async {
    _setExistingUserPreferences({
      activeWorkoutDraftStorageKey: jsonEncode({
        'elapsedSeconds': 123,
        'timerStopped': false,
        'date': DateTime.now().toIso8601String(),
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
    await tester.tap(find.byTooltip('セットを削除'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    final frozen = jsonDecode(
      preferences.getString(activeWorkoutDraftStorageKey)!,
    ) as Map<String, dynamic>;
    expect(frozen['timerStopped'], true);
    final label = find.byKey(const Key('workoutElapsedLabel'));
    final elapsed = tester.widget<Text>(label).data;
    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(tester.widget<Text>(label).data, elapsed);
    expect(find.byTooltip('セットを削除'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resumed draft keeps its elapsed time', (tester) async {
    final startedAt = DateTime.now().subtract(const Duration(minutes: 5));
    _setExistingUserPreferences({
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

  test(
    'body weights keep multiple entries on the same date and skip missing days',
    () {
      final now = DateTime(2026, 9, 13, 12);
      final entries = [
        BodyWeightEntry(
          id: 'old',
          recordedAt: DateTime(2026, 5, 1),
          weightKg: 84,
        ),
        BodyWeightEntry(
          id: 'morning',
          recordedAt: DateTime(2026, 9, 12, 8),
          weightKg: 82.5,
        ),
        BodyWeightEntry(
          id: 'night',
          recordedAt: DateTime(2026, 9, 12, 21),
          weightKg: 82.1,
        ),
      ];

      final shown = bodyWeightsForPeriod(
        entries,
        BodyWeightPeriod.oneMonth,
        now: now,
      );

      expect(shown.map((entry) => entry.id), ['morning', 'night']);
      expect(shown.map((entry) => entry.weightKg), [82.5, 82.1]);
    },
  );

  testWidgets('body weight can be saved and appears in the history chart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final entries = ValueNotifier<List<BodyWeightEntry>>([]);
    addTearDown(entries.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<List<BodyWeightEntry>>(
              valueListenable: entries,
              builder: (context, value, _) => BodyWeightTrendSection(
                entries: value,
                onSaved: (entry) async {
                  entries.value = [entry];
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('addBodyWeightButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deleteBodyWeightButton')), findsNothing);
    await tester.enterText(find.byKey(const Key('bodyWeightField')), '82.5');
    await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
    await tester.pumpAndSettle();

    expect(entries.value.single.weightKg, 82.5);
    expect(find.byKey(const Key('bodyWeightChart')), findsOneWidget);
    expect(find.text('82.5 kg'), findsOneWidget);

    final originalId = entries.value.single.id;
    await tester.tap(find.byTooltip('体重を編集'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bodyWeightField')), '81.9');
    await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
    await tester.pumpAndSettle();
    expect(entries.value, hasLength(1));
    expect(entries.value.single.id, originalId);
    expect(entries.value.single.weightKg, 81.9);
  });

  testWidgets('SNS preview contains exercise data without workout totals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workout = WorkoutRecord(
      date: DateTime(2026, 9, 13),
      durationSeconds: 1800,
      sets: const [
        RecordedSet(
          exerciseName: 'チェストプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 10,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'インクラインダンベルプレス（スローテンポ・ワイドグリップ）',
          bodyPart: '胸',
          weight: 12.5,
          reps: 12,
          completed: true,
        ),
        RecordedSet(
          exerciseName: 'チェストプレス',
          bodyPart: '胸',
          weight: 55,
          reps: 8,
          completed: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: WorkoutSharePage(workout: workout)),
    );
    await tester.pumpAndSettle();

    expect(find.text('チェストプレス'), findsOneWidget);
    expect(find.text('55 kg × 8 回  /  2 セット'), findsOneWidget);
    expect(find.text('インクラインダンベルプレス（スローテンポ・ワイドグリップ）'), findsOneWidget);
    expect(find.text('総ボリューム'), findsNothing);
    expect(find.text('トレーニング時間'), findsNothing);
    expect(find.byKey(const Key('chooseSharePhotoButton')), findsOneWidget);
    expect(find.byKey(const Key('shareWorkoutImageButton')), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(tester.takeException(), isNull);

    expect(find.byKey(const Key('shareVolumeToggle')), findsNothing);
    expect(find.byKey(const Key('shareDurationToggle')), findsNothing);
  });

  testWidgets('body weight deletion persists without changing workout history', (tester) async {
    final history = jsonEncode([
      WorkoutRecord(date: DateTime(2026, 9, 1), sets: const [
        RecordedSet(weight: 50, reps: 8, completed: true),
      ]).toJson(),
    ]);
    _setExistingUserPreferences({'workout_history': history});
    await BodyWeightPreference.save([
      BodyWeightEntry(id: 'delete-me', recordedAt: DateTime.now(), weightKg: 80),
    ]);
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    final edit = find.byKey(const Key('editBodyWeightdelete-me'));
    await tester.scrollUntilVisible(edit, 200);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteBodyWeightButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeleteBodyWeightButton')));
    await tester.pumpAndSettle();
    expect(await BodyWeightPreference.load(), isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('workout_history'), history);
    expect(find.text('体重を記録するとグラフが表示されます'), findsOneWidget);
  });

  testWidgets('body weight trend appears on home but not history', (
    tester,
  ) async {
    _setExistingUserPreferences({
      'body_weight_entries': jsonEncode([
        BodyWeightEntry(
          id: 'home-weight',
          recordedAt: DateTime(2026, 9, 15),
          weightKg: 82.5,
        ).toJson(),
      ]),
    });
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bodyWeightTrendSection')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bodyWeightTrendSection')), findsNothing);
    expect(find.byKey(const Key('monthlyCalendar')), findsOneWidget);
  });

  testWidgets('contact form is available from profile', (tester) async {
    _setExistingUserPreferences(const {});
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('contactButton')));
    await tester.tap(find.byKey(const Key('contactButton')));
    await tester.pumpAndSettle();

    expect(find.text('不具合報告'), findsOneWidget);
    expect(find.text('機能要望'), findsNothing);
    expect(find.byKey(const Key('contactSubjectField')), findsOneWidget);
    expect(find.byKey(const Key('contactMessageField')), findsOneWidget);
    expect(find.byKey(const Key('contactImageButton')), findsOneWidget);
    expect(find.byKey(const Key('sendContactButton')), findsOneWidget);
  });

  testWidgets('weekly goal UI is removed', (tester) async {
    _setExistingUserPreferences(const {});
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    expect(find.text('1週間の目標'), findsNothing);
  });
}
