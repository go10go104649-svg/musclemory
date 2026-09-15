import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  var surfaceConverted = false;
  setUp(() => surfaceConverted = false);

  Future<void> screenshot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    if (Platform.isAndroid && !surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
      await tester.pumpAndSettle();
    }
    await binding.takeScreenshot(name);
  }

  testWidgets('real device workout timer stops and history retains duration', (
    tester,
  ) async {
    // Fixtures only. Device isolation and --keep-app-running are still required.
    SharedPreferences.setMockInitialValues({});
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = true;
    WorkoutUiPreference.workoutDurationEnabled = true;
    RestTimerPreference.enabled = false;
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    final label = find.byKey(const Key('workoutElapsedLabel'));
    final start = tester.widget<Text>(label).data;
    await Future<void>.delayed(const Duration(seconds: 3));
    await tester.pump();
    expect(tester.widget<Text>(label).data, isNot(start));
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exerciseCategory胸')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ベンチプレス'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.pumpAndSettle();
    await screenshot(tester, 'workout_running');
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    final stopped = tester.widget<Text>(label).data;
    await Future<void>.delayed(const Duration(seconds: 4));
    await tester.pump();
    expect(tester.widget<Text>(label).data, stopped);
    final preferences = await SharedPreferences.getInstance();
    final draft = jsonDecode(
      preferences.getString(activeWorkoutDraftStorageKey)!,
    ) as Map<String, dynamic>;
    expect(draft['timerStopped'], true);
    final seconds = draft['elapsedSeconds'] as int;
    expect(seconds, greaterThanOrEqualTo(3));
    await screenshot(tester, 'workout_completed_timer_stopped');
    await tester.tap(find.byKey(const Key('completeWithoutSharingButton')));
    await tester.pumpAndSettle();
    expect(preferences.getString(activeWorkoutDraftStorageKey), isNull);
    final records =
        jsonDecode(preferences.getString('workout_history')!) as List<dynamic>;
    expect(records.single['durationSeconds'], seconds);
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('calendarDay${DateTime.now().day}')));
    await tester.pumpAndSettle();
    await screenshot(tester, 'history_saved_workout');
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(
      (jsonDecode(
        preferences.getString('workout_history')!,
      ) as List<dynamic>).single['durationSeconds'],
      seconds,
    );
    await tester.pumpWidget(const SizedBox());
  }, skip: const bool.fromEnvironment('ONLY_REST_CHECK'));
  testWidgets('interrupt resume final set removal and clear stay consistent', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      activeWorkoutDraftStorageKey: jsonEncode({
        'elapsedSeconds': 123,
        'timerStopped': false,
        'date': DateTime.now().toIso8601String(),
        'note': '中断確認',
        'exercises': [
          {
            'name': 'ベンチプレス',
            'bodyPart': '胸',
            'equipment': 'フリーウェイト',
            'sets': [
              {'weight': 40, 'reps': 10, 'completed': false},
            ],
          },
        ],
      }),
    });
    RestTimerPreference.enabled = false;
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中断する'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    final paused = preferences.getString(activeWorkoutDraftStorageKey);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(preferences.getString(activeWorkoutDraftStorageKey), paused);
    await tester.tap(find.byKey(const Key('activeWorkoutDraftCard')));
    await tester.pumpAndSettle();
    final label = find.byKey(const Key('workoutElapsedLabel'));
    final resumed = tester.widget<Text>(label).data;
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.pump();
    expect(tester.widget<Text>(label).data, isNot(resumed));
    await tester.tap(find.byTooltip('セットを削除'));
    await tester.pumpAndSettle();
    final stopped = tester.widget<Text>(label).data;
    await Future<void>.delayed(const Duration(seconds: 3));
    await tester.pump();
    expect(tester.widget<Text>(label).data, stopped);
    await screenshot(tester, 'last_set_removed_timer_stopped');
    await tester.tap(find.byKey(const Key('deleteWorkoutDraftButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeleteWorkoutDraftButton')));
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(preferences.getString(activeWorkoutDraftStorageKey), isNull);
    expect(find.byKey(const Key('activeWorkoutDraftCard')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, skip: const bool.fromEnvironment('ONLY_REST_CHECK'));

  testWidgets('rest finish is visible in the running app', (tester) async {
    SharedPreferences.setMockInitialValues({});
    RestTimerPreference.enabled = true;
    RestTimerPreference.seconds = 3;
    if (const bool.fromEnvironment('MANUAL_BACKGROUND_CHECK')) {
      debugPrint('QA_NOTIFICATION_PERMISSION');
      await RestNotificationService.schedule(90);
      await RestNotificationService.cancel();
    }
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
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
    await Future<void>.delayed(const Duration(milliseconds: 3300));
    await tester.pump();
    expect(find.byKey(const Key('restTimerBanner')), findsNothing);
    expect(find.byKey(const Key('restTimerFinishedMessage')), findsOneWidget);
    await screenshot(tester, 'rest_finished_message');
    if (const bool.fromEnvironment('MANUAL_BACKGROUND_CHECK')) {
      RestTimerPreference.seconds = 90;
      await tester.tap(find.byIcon(Icons.circle_outlined).first);
      await tester.pumpAndSettle();
      await RestNotificationService.schedule(90);
      if (Platform.isIOS) {
        final status = await const MethodChannel('com.musclememory/rest_timer')
            .invokeMapMethod<String, dynamic>('debugStatus');
        debugPrint('QA_NOTIFICATION_STATUS:$status');
        expect(status?['authorization'], 2);
        expect(status?['pending'], hasLength(1));
      }
      debugPrint(
        'QA_BACKGROUND_REST_READY:${DateTime.now().millisecondsSinceEpoch}',
      );
      await Future<void>.delayed(const Duration(seconds: 120));
    }
    await tester.pumpWidget(const SizedBox());
    RestTimerPreference.enabled = false;
  });
}
