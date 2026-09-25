import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:setkeep/main.dart';

// Dedicated QA device only. The native photo picker and photo save are
// operated manually; fixtures are never written into workout history.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native photo picker preview and image save', (tester) async {
    await tester.pumpWidget(const SetkeepApp());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(HomeShell));
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
              RecordedSet(
                exerciseName: 'ベンチプレス',
                bodyPart: '胸',
                weight: 60,
                reps: 8,
                completed: true,
              ),
              RecordedSet(
                exerciseName: 'クランチ',
                bodyPart: '腹筋',
                weight: 0,
                reps: 20,
                completed: true,
                recordType: ExerciseRecordType.bodyweightReps,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('chooseSharePhotoButton')));
    await tester.tap(find.byKey(const Key('chooseSharePhotoButton')));
    await tester.pumpAndSettle();
    debugPrint('QA_NATIVE_PHOTO_PICKER_READY');
    for (
      var i = 0;
      i < 180 &&
          find.byKey(const Key('shareBackgroundPhoto')).evaluate().isEmpty;
      i++
    ) {
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pump();
    }
    expect(find.byKey(const Key('shareBackgroundPhoto')), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('share_photo_preview');
    expect(find.text('総ボリューム'), findsNothing);
    expect(find.text('トレーニング時間'), findsNothing);
    await tester.ensureVisible(
      find.byKey(const Key('shareWorkoutImageButton')),
    );
    await tester.tap(find.byKey(const Key('shareWorkoutImageButton')));
    await tester.pumpAndSettle();
    debugPrint('QA_NATIVE_IMAGE_SAVE_REQUESTED');
    for (
      var i = 0;
      i < 180 && find.text('画像を保存中…').evaluate().isNotEmpty;
      i++
    ) {
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pump();
    }
    expect(find.text('画像を保存中…'), findsNothing);
    expect(find.text('画像を保存できませんでした'), findsNothing);
    expect(find.text('画像を写真へ保存しました'), findsOneWidget);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('share_image_saved');
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 7)));
}
