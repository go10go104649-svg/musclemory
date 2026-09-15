import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/body_weight.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('com.musclememory/rest_timer');
  const models = MethodChannel('interactive_3d_plugin');
  testWidgets(
    'home weights cloud lock timer stop and repeated native body surfaces',
    (tester) async {
      final today = DateUtils.dateOnly(DateTime.now());
      SharedPreferences.setMockInitialValues({
        BodyWeightPreference.storageKey: jsonEncode(
          List.generate(
            12,
            (i) => BodyWeightEntry(
              id: 'qa$i',
              recordedAt: today.subtract(Duration(days: 11 - i)),
              weightKg: 82 + i / 10,
            ).toJson(),
          ),
        ),
        'completion_check_enabled': true,
        'rest_timer_enabled': true,
        'rest_timer_seconds': 30,
      });
      await RestTimerPreference.load();
      await WorkoutUiPreference.load();
      await tester.pumpWidget(const MuscleMemoryApp());
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      expect(find.text('今週の記録'), findsNothing);
      expect(find.text('前回のトレーニング'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('bodyWeightTrendSection')),
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('home_latest_weight');
      expect(find.byTooltip('体重を編集'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('editBodyWeightqa11')));
      await tester.tap(find.byKey(const Key('editBodyWeightqa11')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bodyWeightField')), '87.5');
      await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
      await tester.pumpAndSettle();
      final saved = await BodyWeightPreference.load();
      expect(saved, hasLength(12));
      expect(saved.last.weightKg, 87.5);
      await binding.takeScreenshot('home_weight_edited');

      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('backupDataManagementButton')),
      );
      await tester.tap(find.byKey(const Key('backupDataManagementButton')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('exportBackupFile')))
            .onTap,
        isNotNull,
      );
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('importBackupFile')))
            .onTap,
        isNotNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('cloudBackupButton')))
            .onPressed,
        isNull,
      );
      await binding.takeScreenshot('local_backup_cloud_locked');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      for (var round = 0; round < 3; round++) {
        await tester.tap(find.byIcon(Icons.accessibility_new_outlined));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(seconds: 3));
        await tester.pump();
        for (final period in ['week', 'month', 'threeMonths', 'sixMonths']) {
          await tester.ensureVisible(find.byKey(Key('musclePeriod$period')));
          await tester.tap(find.byKey(Key('musclePeriod$period')));
          await tester.pumpAndSettle();
          for (final angle in ['前面', '側面', '背面']) {
            await tester.tap(find.text(angle));
            await tester.pumpAndSettle();
            await Future<void>.delayed(const Duration(milliseconds: 200));
            if (Platform.isAndroid) {
              final before = await models.invokeListMethod<dynamic>(
                'debugCameraStates',
              );
              expect(before, hasLength(1));
              final p = before!.single['projection'] as List;
              expect(
                (p[15] as num).toDouble(),
                closeTo(1, 0.0001),
                reason: 'must use orthographic camera',
              );
              final after = await models.invokeListMethod<dynamic>(
                'debugRecreateSurfaces',
              );
              expect(
                after!.single['projection'],
                p,
                reason: 'surface recreation must preserve camera',
              );
            }
          }
        }
        await tester.tap(find.text('前面'));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await binding.takeScreenshot('body_front_round_$round');
        await tester.tap(find.byIcon(Icons.person_outline_rounded));
        await tester.pumpAndSettle();
      }
      // A real workout action starts rest; stop must suppress every later cue.
      final context = tester.element(find.byType(ProfilePage));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutPage(
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
      await tester.tap(find.byIcon(Icons.circle_outlined).first);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('rest_stop_button');
      await tester.tap(find.byKey(const Key('stopRestTimerButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('restTimerBanner')), findsNothing);
      var status = await native.invokeMapMethod<String, dynamic>('debugStatus');
      if (Platform.isAndroid) {
        expect(status!['deadline'], 0);
      } else {
        expect(status!['pending'], isEmpty);
      }
      // Schedule and cancel a short native notification, then wait past its deadline.
      await RestNotificationService.schedule(2);
      await RestNotificationService.cancel();
      await Future<void>.delayed(const Duration(seconds: 3));
      status = await native.invokeMapMethod<String, dynamic>('debugStatus');
      expect(status!['delivered'], isEmpty);
      if (Platform.isIOS) expect(status['pending'], isEmpty);
      await RestNotificationService.playCompletionFeedback();
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
