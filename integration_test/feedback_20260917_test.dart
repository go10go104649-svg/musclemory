import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exercise_form_expansion_test.dart' as captures;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'feedback scroll, pause, native deadline, last sets and manual restart',
    (tester) async {
      if (Platform.isIOS) {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('通知許可を確認中'))),
        );
        unawaited(RestNotificationService.schedule(3600));
        debugPrint('QA_PERMISSION_WAIT');
        var allowed = false;
        for (var attempt = 0; attempt < 120; attempt++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          final status = await const MethodChannel(
            'com.musclememory/rest_timer',
          ).invokeMapMethod<String, dynamic>('debugStatus');
          if (status!['authorization'] == 2 &&
              status['applicationState'] == 0) {
            allowed = true;
            break;
          }
        }
        expect(
          allowed,
          isTrue,
          reason: 'Grant notifications on the dedicated QA device',
        );
        await RestNotificationService.cancel();
      }
      SharedPreferences.setMockInitialValues({
        'rest_timer_enabled': true,
        'rest_timer_seconds': 90,
        'completion_check_enabled': true,
      });
      await RestTimerPreference.load();
      await WorkoutUiPreference.load();
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutPage(
            history: const [],
            initialWorkout: WorkoutRecord(
              date: DateTime.now(),
              durationSeconds: 0,
              sets: [
                for (final name in ['ベンチプレス', 'インクラインフライマシン'])
                  for (var i = 0; i < 3; i++)
                    RecordedSet(
                      exerciseName: name,
                      bodyPart: '胸',
                      weight: 30,
                      reps: 10,
                      completed: true,
                    ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in [
        'toggleSet0_1',
        'toggleSet0_2',
        'toggleSet1_1',
        'toggleSet1_3',
      ]) {
        final target = find.byKey(Key(key));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        final position = tester.getCenter(target);
        await tester.tap(target);
        await tester.pump();
        expect(tester.getCenter(target), position);
        await tester.tap(target);
        await tester.pump();
        expect(tester.getCenter(target), position);
      }
      final start = find.byKey(const Key('startRestTimerButton'));
      // A last-set completion cancels the previous interval.
      await tester.tap(find.byKey(const Key('toggleSet1_3')));
      await tester.pump();
      await tester.scrollUntilVisible(
        start,
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pump();
      await Future<void>.delayed(const Duration(seconds: 56));
      await tester.pump();
      await tester.tap(find.byKey(const Key('stopRestTimerButton')));
      await tester.pump();
      final paused = tester.widget<Text>(find.byKey(const Key('restRemainingLabel'))).data!;
      expect(paused, anyOf('00:34', '00:33'));
      final channel = const MethodChannel('com.musclememory/rest_timer');
      final stopped = await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      );
      if (Platform.isAndroid) {
        expect(stopped!['deadline'], 0);
      } else {
        expect(stopped!['pending'], isEmpty);
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text(paused), findsOneWidget);
      await captures.capture(binding, 'feedback_paused');
      await tester.tap(start);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final resumed = await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      );
      debugPrint('QA_RESUMED $resumed');
      if (Platform.isAndroid) {
        final remaining =
            (resumed!['deadline'] as int) -
            DateTime.now().millisecondsSinceEpoch;
        expect(remaining, inInclusiveRange(30000, 34000));
      } else {
        expect(resumed!['pending'], hasLength(1));
      }
      await tester.tap(find.byKey(const Key('stopRestTimerButton')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await RestNotificationService.cancel();
      await RestNotificationService.playCompletionFeedback();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final feedback = await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      );
      if (Platform.isAndroid) {
        expect(feedback!['playing'], isTrue);
      } else {
        expect(feedback!['delivered'], contains(endsWith('_foreground')));
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      await RestNotificationService.cancel();
    },
  );
}
