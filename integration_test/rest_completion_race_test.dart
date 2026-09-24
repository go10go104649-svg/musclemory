import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/main.dart';

/// Host QA driver responds to QA_REST_BOUNDARY markers with real Android
/// home/resume/shade/lock operations. No foreground boolean is mocked.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.musclememory/rest_timer');
  Future<Map<String, dynamic>> status() async =>
      (await channel.invokeMapMethod<String, dynamic>('debugStatus'))!;
  int count(Map<String, dynamic> value, String key) => value[key] as int? ?? 0;
  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
  Future<void> stale(Map<String, dynamic> timer) => channel.invokeMethod(
    'debugRestAlarm',
    {'timerId': timer['timerId'], 'deadline': timer['deadline']},
  );

  testWidgets('Android natural completion has one native owner across races', (
    t,
  ) async {
    if (!Platform.isAndroid) return;
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Text('休憩音QA'))));
    await RestNotificationService.cancel();
    debugPrint('QA_REST_PERMISSION_READY');
    await RestNotificationService.schedule(60);
    await wait(3000);
    await RestNotificationService.cancel();
    for (var round = 0; round < 3; round++) {
      final before = await status();
      await RestNotificationService.schedule(2);
      final active = await status();
      await wait(2250);
      // Duplicate Flutter/Alarm and state-sync calls after the native deadline.
      await RestNotificationService.completeIfDue(
        DateTime.fromMillisecondsSinceEpoch(active['deadline'] as int),
      );
      await stale(active);
      await RestNotificationService.state();
      var after = await status();
      expect(
        count(after, 'completionCount'),
        count(before, 'completionCount') + 1,
      );
      expect(
        count(after, 'soundStartCount'),
        count(before, 'soundStartCount') + 1,
      );
      expect(
        count(after, 'notificationPostCount'),
        count(before, 'notificationPostCount'),
      );
      expect(after['lastCompletionTimerId'], active['timerId']);
      expect(after['lastCompletionPath'], 'foreground_native_sound');
      expect(after['lastSoundError'], '');
      expect(after['playing'], true);
      await wait(900);
      expect((await status())['playing'], true);
      await wait(2200);
      after = await status();
      expect(after['playing'], false);
      expect(
        after['lastSoundCompletedAt'],
        greaterThan(after['lastSoundStartedAt'] as int),
      );
    }

    final beforeCancel = await status();
    await RestNotificationService.schedule(1);
    final cancelled = await status();
    await RestNotificationService.cancel();
    await wait(1300);
    await stale(cancelled);
    expect(
      count(await status(), 'completionCount'),
      count(beforeCancel, 'completionCount'),
    );

    await RestNotificationService.schedule(1);
    final old = await status();
    await channel.invokeMethod<void>('debugRestAction', {'action': 'extend'});
    final extended = await status();
    expect(extended['deadline'], (old['deadline'] as int) + 30000);
    await wait(1300);
    await stale(old);
    await RestNotificationService.completeIfDue(
      DateTime.fromMillisecondsSinceEpoch(old['deadline'] as int),
    );
    expect((await status())['timerId'], extended['timerId']);
    expect(
      count(await status(), 'completionCount'),
      count(beforeCancel, 'completionCount'),
    );
    await RestNotificationService.cancel();

    // An expired old generation must not complete a newer generation.
    await RestNotificationService.schedule(1);
    final replaced = await status();
    await RestNotificationService.schedule(2);
    final replacement = await status();
    await wait(1200);
    await stale(replaced);
    expect((await status())['timerId'], replacement['timerId']);
    await wait(1200);
    expect((await status())['lastCompletionTimerId'], replacement['timerId']);
    await wait(3000);

    if (const bool.fromEnvironment('REST_BOUNDARY_HOST_QA')) {
      for (final phase in [
        'background',
        'late_background',
        'before_resume',
        'at_resume',
        'shade',
        'lock',
      ]) {
        final before = await status();
        await RestNotificationService.schedule(6, exerciseName: 'ベンチプレス');
        final active = await status();
        debugPrint('QA_REST_BOUNDARY_$phase');
        await wait(10500);
        final after = await status();
        expect(
          count(after, 'completionCount'),
          count(before, 'completionCount') + 1,
          reason: phase,
        );
        final outputs =
            count(after, 'soundStartCount') -
            count(before, 'soundStartCount') +
            count(after, 'notificationPostCount') -
            count(before, 'notificationPostCount');
        expect(outputs, 1, reason: '$phase must have exactly one output');
        expect(after['lastCompletionTimerId'], active['timerId']);
        expect(after['lastCompletionPath'], isNot('failed'), reason: phase);
        expect(
          after['lastCompletionPath'],
          isNot('suppressed_by_os'),
          reason: phase,
        );
        debugPrint('QA_REST_RESULT_$phase $after');
        await RestNotificationService.cancel();
      }
    }
    await RestNotificationService.cancel();
  });
}
