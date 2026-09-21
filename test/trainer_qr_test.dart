import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/trainer_invite_qr.dart';
import 'package:muscle_memory/trainer_qr_page.dart';

void main() {
  test('trainer QR parses only supported invite URLs', () {
    final invite = TrainerInviteQr.parse(
      'musclemory://trainer/invite?v=1&token=test-token',
    );
    expect(invite?.version, 1);
    expect(invite?.token, 'test-token');
    for (final invalid in [
      'musclemory://trainer/invite?v=1&token=',
      'musclemory://trainer/invite?v=1&token=%20',
      'musclemory://trainer/invite?token=test',
      'musclemory://trainer/invite?v=2&token=test',
      'musclemory://gym/invite?v=1&token=test',
      'musclemory://trainer/connect?v=1&token=test',
      'https://trainer/invite?v=1&token=test',
      'not a URI',
      'musclemory://[broken',
      'musclemory://trainer/invite?v=1&token=%ZZ',
      'musclemory://trainer/invite?v=1&token=a&token=b',
      'musclemory://trainer/invite?v=1&v=2&token=a',
      'musclemory://trainer/invite?v=1&token=a&trainerId=123',
      'musclemory://user@trainer/invite?v=1&token=a',
      'musclemory://trainer:80/invite?v=1&token=a',
      'musclemory://trainer/invite?v=1&token=a#fragment',
    ]) {
      expect(TrainerInviteQr.parse(invalid), isNull, reason: invalid);
    }
  });

  testWidgets('trainer QR handles invalid, valid and duplicate results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late ValueChanged<String> detect;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TrainerQrPage(
                    scannerBuilder: (_, callback) {
                      detect = callback;
                      return const SizedBox(key: Key('fakeCamera'));
                    },
                  ),
                ),
              ),
              child: const Text('マイページ'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('マイページ'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      detect('https://example.com');
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invalidTrainerQr')), findsOneWidget);
    expect(find.byKey(const Key('fakeCamera')), findsOneWidget);
    expect(tester.takeException(), isNull);
    detect('musclemory://trainer/invite?v=1&token=secret-token');
    detect('musclemory://trainer/invite?v=1&token=secret-token');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trainerInviteRecognized')), findsOneWidget);
    expect(find.byKey(const Key('fakeCamera')), findsNothing);
    expect(find.textContaining('secret-token'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('closeTrainerInvite')));
    await tester.tap(find.byKey(const Key('closeTrainerInvite')));
    await tester.pumpAndSettle();
    expect(find.text('マイページ'), findsOneWidget);
  });

  testWidgets(
    'trainer QR camera unavailable explains permissions and allows back',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('開く'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TrainerQrPage(
                      scannerBuilder: (_, _) =>
                          const TrainerCameraUnavailable(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(find.text('カメラを利用できません'), findsOneWidget);
      expect(find.textContaining('カメラ権限'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('開く'), findsOneWidget);
    },
  );
}
