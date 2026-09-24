import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('com.musclememory/rest_timer');
  testWidgets(
    'rest completion uses persistent controls and OS-respecting sound',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'completion_check_enabled': true,
        'rest_timer_enabled': true,
      });
      await WorkoutUiPreference.load();
      await RestTimerPreference.load();
      RestTimerPreference.seconds = 2;
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutPage(
            history: const [],
            initialWorkout: WorkoutRecord(
              date: DateTime.now(),
              sets: const [
                RecordedSet(
                  exerciseName: 'ベンチプレス',
                  bodyPart: '胸',
                  weight: 60,
                  reps: 10,
                  completed: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      debugPrint('QA_SOUND_PERMISSION_READY');
      await RestNotificationService.schedule(60);
      await Future<void>.delayed(const Duration(seconds: 5));
      await RestNotificationService.cancel();
      // Permission UI may resume the workout while the 60-second probe is active.
      // Resync after cancelling that setup probe before testing the real timer.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      debugPrint(
        'QA_SOUND_START lifecycle=${WidgetsBinding.instance.lifecycleState}',
      );
      await tester.tap(find.byKey(const Key('startRestTimerButton')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      await tester.pump();
      expect(find.byKey(const Key('startRestTimerButton')), findsOneWidget);
      expect(find.byKey(const Key('restTimerFinishedMessage')), findsOneWidget);
      var status = await native.invokeMapMethod<String, dynamic>('debugStatus');
      expect(
        Platform.isIOS
            ? (status!['delivered'] as List).any(
                (id) => (id as String).endsWith('_foreground'),
              )
            : status!['playing'],
        isTrue,
        reason: 'cue must survive the countdown disappearing',
      );
      await Future<void>.delayed(const Duration(milliseconds: 900));
      status = await native.invokeMapMethod<String, dynamic>('debugStatus');
      expect(
        Platform.isIOS
            ? (status!['delivered'] as List).any(
                (id) => (id as String).endsWith('_foreground'),
              )
            : status!['playing'],
        isTrue,
        reason: 'cue must not stop after a short beep',
      );
      await Future<void>.delayed(const Duration(milliseconds: 1700));
      status = await native.invokeMapMethod<String, dynamic>('debugStatus');
      expect(status!['playing'], isFalse);
      await RestNotificationService.playCompletionFeedback();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await RestNotificationService.cancel();
      status = await native.invokeMapMethod<String, dynamic>('debugStatus');
      expect(status!['playing'], isFalse);
      // Host backgrounds the app during this window to test actual OS delivery.
      await RestNotificationService.schedule(Platform.isIOS ? 25 : 5);
      debugPrint('QA_BACKGROUND_NOTIFICATION_READY');
      await Future<void>.delayed(Duration(seconds: Platform.isIOS ? 45 : 20));
      status = await native.invokeMapMethod<String, dynamic>('debugStatus');
      expect(
        status!['delivered'],
        isNotEmpty,
        reason: 'background local notification must arrive',
      );
      debugPrint('QA_BACKGROUND_DELIVERY_CONFIRMED');
      await RestNotificationService.cancel();
      await RestNotificationService.schedule(3);
      await RestNotificationService.cancel();
      await Future<void>.delayed(const Duration(seconds: 4));
      status = await native.invokeMapMethod<String, dynamic>('debugStatus');
      expect(status!['delivered'], isEmpty);
      if (Platform.isIOS) expect(status['pending'], isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
