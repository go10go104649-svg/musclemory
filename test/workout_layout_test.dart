import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/app_colors.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkoutRecord layoutFixture({int exercises = 2, int sets = 3}) => WorkoutRecord(
  date: DateTime(2026, 9, 23),
  sets: [
    for (var e = 0; e < exercises; e++)
      for (var s = 0; s < sets; s++)
        RecordedSet(
          exerciseName: e == 0 ? 'インクラインダンベルプレス' : 'テスト種目$e',
          bodyPart: '胸',
          equipment: 'ダンベル',
          weight: 20,
          reps: 10,
          completed: true,
        ),
  ],
);

Future<void> prepareLayoutPreferences() async {
  SharedPreferences.setMockInitialValues({});
  WorkoutUiPreference.completionCheckEnabled = true;
  WorkoutUiPreference.workoutTimerEnabled = false;
  WorkoutUiPreference.workoutDurationEnabled = false;
  RestTimerPreference.enabled = true;
  RestTimerPreference.seconds = 60;
}

Widget layoutApp({WorkoutRecord? record, ThemeData? theme}) => MaterialApp(
  theme:
      theme ??
      ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryGreen,
          primary: const Color(0xFF101820),
          secondary: AppColors.primaryGreen,
          surface: const Color(0xFFF4F5F0),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F5F0),
        cardTheme: const CardThemeData(
          color: Colors.white,
          margin: EdgeInsets.zero,
          elevation: 0,
        ),
      ),
  home: WorkoutPage(
    gymName: 'FIT PLACE24 松戸店',
    initialWorkout: record ?? layoutFixture(),
  ),
);

void main() {
  setUp(prepareLayoutPreferences);
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    await WorkoutUiPreference.load();
    await RestTimerPreference.load();
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('workout hierarchy, aligned inputs and targets at $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(layoutApp());
      await t.pumpAndSettle();
      expect(find.text('2026年'), findsOneWidget);
      expect(find.text('2種目'), findsOneWidget);
      final keys = [
        'workoutDateButton',
        'workoutGymButton',
        'restTimerBanner',
        'workoutExercisesHeading',
        'exerciseInputHeader0',
      ];
      final tops = [
        for (final key in keys) t.getTopLeft(find.byKey(Key(key))).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(
        find.ancestor(
          of: find.byKey(const Key('workoutDateButton')),
          matching: find.byType(Card),
        ),
        findsNothing,
      );
      final title = t.widget<Text>(
        find.byKey(const Key('exerciseInputTitle0')),
      );
      expect(title.maxLines, 1);
      expect(title.softWrap, false);
      for (final key in ['weightField0_1', 'repsField0_1']) {
        expect(
          t.getSize(find.byKey(Key(key))).height,
          greaterThanOrEqualTo(48),
        );
      }
      expect(t.getSize(find.byKey(const Key('toggleSet0_1'))).width, 44);
      final card = find.byType(ExerciseInputCard).first;
      for (final pair in [('KG', 'weightField0_1'), ('REPS', 'repsField0_1')]) {
        final label = find.descendant(of: card, matching: find.text(pair.$1));
        expect(
          t.getCenter(label).dx,
          closeTo(t.getCenter(find.byKey(Key(pair.$2))).dx, 0.1),
        );
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'eleven exercises and sets preserve position and reveal keypad input',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        layoutApp(record: layoutFixture(exercises: 11, sets: 11)),
      );
      await t.pumpAndSettle();
      for (final key in ['toggleSet0_1', 'toggleSet5_6', 'toggleSet10_11']) {
        final check = find.byKey(Key(key));
        await t.ensureVisible(check);
        await t.pumpAndSettle();
        final position = t.getCenter(check);
        await t.tap(check);
        await t.pump();
        expect(t.getCenter(check), position);
        await t.tap(check);
        await t.pump();
        expect(t.getCenter(check), position);
      }
      final input = find.byKey(const Key('weightField10_11'));
      await t.ensureVisible(input);
      await t.pumpAndSettle();
      await t.tap(input);
      await t.pumpAndSettle();
      final pad = find.byKey(const Key('workoutNumericKeypad'));
      expect(pad, findsOneWidget);
      expect(t.getRect(input).bottom, lessThanOrEqualTo(t.getRect(pad).top));
      await t.enterText(
        find.descendant(of: input, matching: find.byType(TextFormField)),
        '25',
      );
      await t.tap(find.byKey(const Key('closeNumericKeypad')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
