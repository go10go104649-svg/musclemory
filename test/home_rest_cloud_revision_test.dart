import 'support/legal_consent_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/body_weight.dart';
import 'package:muscle_memory/main.dart';
import 'package:muscle_memory/services/supabase_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    '12 weights stay in graph, only latest row is shown and editable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final today = DateUtils.dateOnly(DateTime.now());
      final entries = ValueNotifier(
        List.generate(
          12,
          (i) => BodyWeightEntry(
            id: 'w$i',
            recordedAt: today.subtract(Duration(days: 11 - i)),
            weightKg: 80 + i / 10,
          ),
        ),
      );
      addTearDown(entries.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder<List<BodyWeightEntry>>(
                valueListenable: entries,
                builder: (_, value, _) => BodyWeightTrendSection(
                  entries: value,
                  onDeleted: (entry) async => entries.value = [
                    for (final old in entries.value) if (old.id != entry.id) old,
                  ],
                  onSaved: (entry) async => entries.value = [
                    for (final old in value) old.id == entry.id ? entry : old,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byTooltip('体重を編集'), findsOneWidget);
      expect(find.byKey(const Key('editBodyWeightw11')), findsOneWidget);
      expect(find.text('任意で記録できます ・ kg'), findsNothing);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byKey(const Key('bodyWeightChart')),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as BodyWeightChartPainter;
      expect(painter.entries, hasLength(12));
      await tester.tap(find.byKey(const Key('editBodyWeightw11')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bodyWeightField')), '87.5');
      await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
      await tester.pumpAndSettle();
      expect(entries.value, hasLength(12));
      expect(entries.value.last.weightKg, 87.5);
      expect(find.textContaining('87.5 kg'), findsOneWidget);
      expect(entries.value.first.weightKg, 80);
      Future<void> deleteOpenedEntry() async {
        await tester.tap(find.byKey(const Key('deleteBodyWeightButton')));
        await tester.pumpAndSettle();
        expect(find.text('この体重記録を削除しますか？'), findsOneWidget);
        await tester.tap(find.byKey(const Key('confirmDeleteBodyWeightButton')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('editBodyWeightw11')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deleteBodyWeightButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('deleteBodyWeightButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelDeleteBodyWeightButton')));
      await tester.pumpAndSettle();
      expect(entries.value, hasLength(12));
      expect(find.byKey(const Key('bodyWeightField')), findsOneWidget);
      await deleteOpenedEntry();
      expect(entries.value, hasLength(11));
      expect(find.byKey(const Key('editBodyWeightw10')), findsOneWidget);
      expect(find.byKey(const Key('bodyWeightField')), findsNothing);
      // Select and delete an older graph point, keeping the latest unchanged.
      final chart = find.byKey(const Key('bodyWeightChart'));
      await tester.tapAt(tester.getTopLeft(chart) + const Offset(46, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byKey(const Key('selectedBodyWeight')),
        matching: find.text('編集'),
      ));
      await tester.pumpAndSettle();
      await deleteOpenedEntry();
      expect(entries.value.any((e) => e.id == 'w0'), isFalse);
      expect(entries.value, hasLength(10));
      final updatedPainter = tester.widget<CustomPaint>(find.descendant(
        of: chart, matching: find.byType(CustomPaint),
      )).painter! as BodyWeightChartPainter;
      expect(updatedPainter.entries, hasLength(10));
      expect(updatedPainter.selectedId, isNull);
      expect(find.byKey(const Key('selectedBodyWeight')), findsNothing);
      while (entries.value.isNotEmpty) {
        await tester.tap(find.byKey(Key('editBodyWeight${entries.value.last.id}')));
        await tester.pumpAndSettle();
        await deleteOpenedEntry();
      }
      expect(find.byKey(const Key('bodyWeightChart')), findsNothing);
      expect(find.text('体重を記録するとグラフが表示されます'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('free local backup actions work and cloud button is locked', (
    tester,
  ) async {
    var exports = 0, imports = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BackupDataManagementPage(
          onExport: (_) async {
            exports++;
          },
          onImportFile: (_) async {
            imports++;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('exportBackupFile')));
    await tester.tap(find.byKey(const Key('importBackupFile')));
    expect(exports, 1);
    expect(imports, 1);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('cloudBackupButton')),
    );
    expect(button.onPressed, isNull);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('verified premium presentation enables cloud area only', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudBackupSection(premium: true, onOpen: () => opens++),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('cloudBackupButton')));
    expect(opens, 1);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  test(
    'all cloud entry points deny free access before using Supabase',
    () async {
      expect(SupabaseSyncService.canUseCloud, isFalse);
      await expectLater(SupabaseSyncService.syncWorkouts([]), throwsStateError);
      await expectLater(SupabaseSyncService.fetchWorkouts(), throwsStateError);
      await expectLater(
        SupabaseSyncService.deleteWorkout('x'),
        throwsStateError,
      );
    },
  );

  testWidgets('home removes summaries without removing saved workouts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true, 'legal_consent': acceptedLegalConsentJson});
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    expect(find.byType(WeeklySummary), findsNothing);
    expect(find.byType(LastWorkoutCard), findsNothing);
    expect(find.text('今週の記録'), findsNothing);
    expect(find.text('前回のトレーニング'), findsNothing);
    expect(find.byKey(const Key('startWorkoutButton')), findsOneWidget);
  });

  testWidgets('manual rest stop remains silent past original deadline', (
    tester,
  ) async {
    final sounds = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        sounds.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
    'legal_consent': acceptedLegalConsentJson,
      'rest_timer_enabled': true,
      'rest_timer_seconds': 30,
      'completion_check_enabled': true,
    });
    await RestTimerPreference.load();
    await WorkoutUiPreference.load();
    final initial = WorkoutRecord(
      date: DateTime.now(),
      durationSeconds: 0,
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 60,
          reps: 10,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutPage(history: const [], initialWorkout: initial),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startRestTimerButton')));
    await tester.pump();
    expect(find.byKey(const Key('restTimerBanner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('stopRestTimerButton')));
    await tester.pump();
    expect(find.byKey(const Key('startRestTimerButton')), findsOneWidget);
    expect(find.text('休憩  00:30'), findsOneWidget);
    sounds.clear();
    await tester.pump(const Duration(seconds: 35));
    expect(find.byKey(const Key('restTimerFinishedMessage')), findsNothing);
    expect(sounds.where((c) => c.method == 'SystemSound.play'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
