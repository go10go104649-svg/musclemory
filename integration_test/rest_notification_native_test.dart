import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.musclememory/rest_timer');

  testWidgets('native rest completion and explicit feedback remain separate', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await RestNotificationService.cancel();
    await RestNotificationService.schedule(2);
    await Future<void>.delayed(const Duration(seconds: 3));
    if (Platform.isAndroid) {
      final status = await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      );
      expect(status!['lastCompletionPath'], 'foreground_native_sound');
      expect(status['playing'], true);
    }
    // Explicit test sound is still supported, but isn't called to rescue natural expiry.
    await RestNotificationService.cancel();
    await RestNotificationService.playCompletionFeedback();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final status = await channel.invokeMapMethod<String, dynamic>(
      'debugStatus',
    );
    if (Platform.isAndroid) expect(status!['playing'], true);
    if (Platform.isIOS) expect(status!['delivered'], isNotEmpty);
    await RestNotificationService.cancel();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Android OS suppression is diagnosed separately from playback failure',
    (t) async {
      if (!Platform.isAndroid ||
          !const bool.fromEnvironment('REST_BOUNDARY_HOST_QA')) {
        return;
      }
      await t.pumpWidget(const MaterialApp(home: Scaffold()));
      await RestNotificationService.cancel();
      final before = (await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      ))!;
      debugPrint('QA_REST_DND_READY');
      await Future<void>.delayed(const Duration(seconds: 2));
      await RestNotificationService.schedule(2);
      await Future<void>.delayed(const Duration(seconds: 3));
      final after = (await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      ))!;
      expect(after['lastCompletionPath'], 'suppressed_by_os');
      expect(
        after['lastSuppressedReason'],
        isIn(['do_not_disturb', 'ringer_mode']),
      );
      expect(after['soundStartCount'], before['soundStartCount']);
      expect(after['lastSoundError'], '');
      debugPrint('QA_REST_DND_DONE');
      await RestNotificationService.cancel();
    },
  );
}
