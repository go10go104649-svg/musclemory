import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/body_weight.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seven item settings and sharing smoke flow', (tester) async {
    SharedPreferences.setMockInitialValues({
      BodyWeightPreference.storageKey: jsonEncode([
        BodyWeightEntry(
          id: 'android-weight',
          recordedAt: DateTime.now(),
          weightKg: 82.5,
        ).toJson(),
      ]),
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

    expect(find.byKey(const Key('bodyWeightTrendSection')), findsOneWidget);
    await binding.takeScreenshot('seven_home_weight');
    expect(tester.takeException(), isNull, reason: 'home');

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bodyWeightTrendSection')), findsNothing);
    expect(tester.takeException(), isNull, reason: 'history');

    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('locationSettingsButton')));
    expect(find.text('カスタム場所'), findsNothing);
    await tester.tap(find.byKey(const Key('locationSettingsButton')));
    await tester.pumpAndSettle();
    expect(find.text('いつもの場所'), findsOneWidget);
    expect(find.byKey(const Key('addCustomGymButton')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'location');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('trainingSettingsButton')));
    await tester.tap(find.byKey(const Key('trainingSettingsButton')));
    await tester.pumpAndSettle();
    final completionY = tester
        .getTopLeft(find.byKey(const Key('completionCheckSwitch')))
        .dy;
    final restY = tester
        .getTopLeft(find.byKey(const Key('restTimerSwitch')))
        .dy;
    final durationY = tester
        .getTopLeft(find.byKey(const Key('trainingDurationSwitch')))
        .dy;
    expect(completionY, lessThan(restY));
    expect(restY, lessThan(durationY));
    await binding.takeScreenshot('seven_training_settings');
    expect(tester.takeException(), isNull, reason: 'training settings');
    await tester.tap(find.byKey(const Key('completionCheckSwitch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('restTimerSwitch')), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final profileContext = tester.element(find.byType(ProfilePage));
    Navigator.of(profileContext).push(
      MaterialPageRoute<void>(
        builder: (_) => BackupDataManagementPage(
          onExport: (_) async {},
          onImportFile: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('バックアップを書き出す'), findsOneWidget);
    expect(find.text('バックアップから復元'), findsOneWidget);
    expect(find.text('バックアップをコピー'), findsNothing);
    expect(find.text('バックアップを読み込む'), findsNothing);
    expect(tester.takeException(), isNull, reason: 'backup');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    Navigator.of(profileContext)
        .push(MaterialPageRoute<void>(builder: (_) => const ContactPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contactCategoryField')), findsOneWidget);
    expect(find.byKey(const Key('contactSubjectField')), findsOneWidget);
    expect(find.byKey(const Key('contactMessageField')), findsOneWidget);
    expect(find.byKey(const Key('contactImageButton')), findsOneWidget);
    await binding.takeScreenshot('seven_contact');
    expect(tester.takeException(), isNull, reason: 'contact');

    final context = tester.element(find.byType(ContactPage));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutSharePage(
          workout: WorkoutRecord(
            date: DateTime.now(),
            durationSeconds: 1800,
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
    expect(find.text('ベンチプレス'), findsOneWidget);
    expect(find.textContaining('60 kg'), findsOneWidget);
    expect(find.text('総ボリューム'), findsNothing);
    expect(find.text('トレーニング時間'), findsNothing);
    await binding.takeScreenshot('seven_sns_exercise_only');
    expect(tester.takeException(), isNull);
  });
}
