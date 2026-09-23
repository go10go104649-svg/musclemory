import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.musclememory/rest_timer');
  Future<Map<String, dynamic>> state() async =>
      (await RestNotificationService.state())!;
  Future<void> flush(WidgetTester t) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await t.pumpAndSettle();
  }

  testWidgets('native rest display uses one deadline and cancels consistently', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = false;
    WorkoutUiPreference.workoutDurationEnabled = false;
    RestTimerPreference.enabled = true;
    RestTimerPreference.seconds = 90;
    await RestNotificationService.cancel();
    await t.pumpWidget(
      MaterialApp(
        home: WorkoutPage(
          initialWorkout: WorkoutRecord(
            date: DateTime.now(),
            sets: const [
              RecordedSet(
                exerciseName: 'ベンチプレス',
                weight: 40,
                reps: 10,
                completed: true,
              ),
              RecordedSet(
                exerciseName: 'ベンチプレス',
                weight: 40,
                reps: 10,
                completed: true,
              ),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final check = find.byKey(const Key('toggleSet0_1'));
    await t.ensureVisible(check);
    await t.pumpAndSettle();
    await t.tap(check);
    await flush(t);
    final first = await state();
    expect(
      first['endsAtMilliseconds'],
      greaterThan(DateTime.now().millisecondsSinceEpoch),
    );
    expect(first['exerciseName'], 'ベンチプレス');
    final debug = await channel.invokeMapMethod<String, dynamic>('debugStatus');
    if (Platform.isAndroid) expect(debug!['delivered'], contains(7340));
    if (Platform.isIOS) expect(debug!['liveActivities'], 1);
    await t.scrollUntilVisible(
      find.byKey(const Key('stopRestTimerButton')),
      -220,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('debugRestAction', {'action': 'extend'});
      await flush(t);
      expect(
        (await state())['endsAtMilliseconds'],
        first['endsAtMilliseconds'] + 30000,
      );
      await channel.invokeMethod<void>('debugRestAction', {'action': 'stop'});
      await flush(t);
    } else {
      await t.drag(find.byType(Scrollable).first, const Offset(0, 500));
      await t.pumpAndSettle();
      await t.tap(find.text('+30秒'));
      await flush(t);
      expect(
        (await state())['endsAtMilliseconds'],
        greaterThan(first['endsAtMilliseconds'] + 28000),
      );
      await t.tap(find.byKey(const Key('stopRestTimerButton')));
      await flush(t);
    }
    final paused = await state();
    expect(paused['endsAtMilliseconds'], 0);
    expect(paused['remainingSeconds'], greaterThan(90));
    expect(find.byKey(const Key('startRestTimerButton')), findsOneWidget);
    final stopped = await channel.invokeMapMethod<String, dynamic>(
      'debugStatus',
    );
    if (Platform.isAndroid) {
      expect(stopped!['delivered'], isNot(contains(7340)));
    }
    if (Platform.isIOS) expect(stopped!['liveActivities'], 0);
    await t.tap(find.byKey(const Key('startRestTimerButton')));
    await flush(t);
    expect(
      (await state())['endsAtMilliseconds'],
      greaterThan(DateTime.now().millisecondsSinceEpoch + 85000),
    );
    final last = find.byKey(const Key('toggleSet0_2'));
    await t.ensureVisible(last);
    await t.pumpAndSettle();
    await t.tap(last);
    await flush(t);
    expect((await state())['endsAtMilliseconds'], 0);
    // Simulate a notification action followed by app resume; native state wins.
    await RestNotificationService.schedule(45, exerciseName: 'ベンチプレス');
    await RestNotificationService.cancel(remainingSeconds: 34);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flush(t);
    await t.drag(find.byType(Scrollable).first, const Offset(0, 500));
    await t.pumpAndSettle();
    expect(find.text('00:34'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    await flush(t);
    expect((await state())['remainingSeconds'], 0);
  });

  testWidgets('native display expires and a cancelled deadline stays silent', (
    t,
  ) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold()));
    await RestNotificationService.schedule(3, exerciseName: 'ベンチプレス');
    await Future<void>.delayed(const Duration(seconds: 5));
    await flush(t);
    expect((await state())['endsAtMilliseconds'], 0);
    var debug = await channel.invokeMapMethod<String, dynamic>('debugStatus');
    if (Platform.isAndroid) expect(debug!['delivered'], isNot(contains(7340)));
    if (Platform.isIOS) expect(debug!['liveActivities'], 0);
    await RestNotificationService.schedule(3, exerciseName: 'ベンチプレス');
    await RestNotificationService.cancel();
    await Future<void>.delayed(const Duration(seconds: 5));
    await flush(t);
    debug = await channel.invokeMapMethod<String, dynamic>('debugStatus');
    expect(debug!['delivered'], isEmpty);
    if (Platform.isIOS) {
      expect(debug['pending'], isEmpty);
      expect(debug['liveActivities'], 0);
    }
    if (const bool.fromEnvironment('REST_DISPLAY_VISUAL_QA')) {
      // Bounded window for host-side lock-screen/notification screenshots on QA devices.
      await RestNotificationService.schedule(120, exerciseName: 'ベンチプレス');
      await flush(t);
      debugPrint('REST_DISPLAY_VISUAL_QA_READY');
      await Future<void>.delayed(const Duration(seconds: 45));
      await RestNotificationService.cancel();
    }
  });
}
