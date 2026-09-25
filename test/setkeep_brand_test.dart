import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/config/supabase_config.dart';
import 'package:setkeep/trainer_invite_qr.dart';

void main() {
  test('new brand preserves historic backups without rewriting records', () {
    for (final brand in ['SETKEEP', 'MUSCLEMORY', 'MuscleMemory']) {
      for (final version in [1, 2, 3]) {
        final record = WorkoutRecord(
          date: DateTime(2026, 9, 24),
          gymName: '体育館',
          sets: [
            RecordedSet(
              exerciseName: 'ベンチプレス',
              exerciseId: 'bench_press',
              bodyPart: '胸',
              equipment: 'バーベル',
              weight: 80,
              reps: 8,
              completed: true,
            ),
          ],
        );
        final json = SetkeepBackup(
          workouts: [record],
          restTimerSeconds: 270,
        ).toJson();
        json['app'] = brand;
        json['version'] = version;
        final restored = SetkeepBackup.fromJson(json);
        expect(restored.workouts.single.toJson(), record.toJson());
        expect(restored.toJson()['app'], 'SETKEEP');
        expect(restored.restTimerSeconds, 270);
      }
    }
  });
  test('native identifiers and channels match Flutter', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('namespace = "com.setkeep.app"'));
    expect(gradle, contains('applicationId = "com.setkeep.app"'));
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:scheme="setkeep"'));
    expect(manifest, contains('android:label="SETKEEP"'));
    final project = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = com.setkeep.app;'));
    expect(
      project,
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.setkeep.app.RestTimerWidget;'),
    );
    final ios = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final android = File(
      'android/app/src/main/kotlin/com/setkeep/app/MainActivity.kt',
    ).readAsStringSync();
    for (final channel in [
      'com.setkeep.app/rest_timer',
      'com.setkeep.app/workout_image',
    ]) {
      expect(ios, contains(channel));
      expect(android, contains(channel));
    }
    expect(SupabaseConfig.authRedirectUrl, 'setkeep://login-callback/');
  });
  test('new and legacy trainer invites remain readable', () {
    for (final scheme in ['setkeep', 'musclemory']) {
      expect(
        TrainerInviteQr.parse('$scheme://trainer/invite?v=1&token=test')?.token,
        'test',
      );
    }
  });
}
