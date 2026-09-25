import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/trainer/trainer_repository.dart';
import 'package:setkeep/trainer/trainer_sharing_page.dart';

class FakeSharingRepository implements TrainerRepository {
  bool accepted = false;
  bool recording = true;
  bool heatmap = true;
  int shared = 0;
  @override
  Future<List<Map<String, dynamic>>> myLinks() async => accepted
      ? [
          {
            'id': 'link',
            'trainer_id': 'trainer',
            'trainer_profiles': {'display_name': 'Verified Coach'},
          },
        ]
      : [];
  @override
  Future<String?> previewInvite(String token) async => 'Verified Coach';
  @override
  Future<void> acceptInvite(
    String token,
    String name, {
    required bool recording,
    required bool heatmap,
  }) async {
    accepted = true;
    this.recording = recording;
    this.heatmap = heatmap;
  }

  @override
  Future<void> shareWorkout(Map<String, dynamic> workout) async {
    shared++;
  }

  @override
  Future<List<Map<String, dynamic>>> recordedForMe({int offset = 0}) async => [
    {
      'performed_at': '2026-09-25T10:00:00Z',
      'sets': [],
      'duration_seconds': 60,
    },
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('request IDs are UUIDs and unique', () {
    final ids = List.generate(100, (_) => TrainerRepository.requestId());
    expect(ids.toSet(), hasLength(100));
    for (final id in ids) {
      expect(
        RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch(id),
        true,
      );
    }
  });
  testWidgets(
    'preview never links automatically, explicit consent defaults private',
    (t) async {
      t.view.physicalSize = const Size(600, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FakeSharingRepository();
      await t.pumpWidget(
        MaterialApp(
          home: TrainerSharingPage(
            history: const [],
            repository: repo,
            onReceived: (_) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byType(TextField).first,
        '11111111-1111-4111-8111-111111111111',
      );
      await t.tap(find.text('Check invitation'));
      await t.pumpAndSettle();
      expect(repo.accepted, false);
      expect(find.text('Trainer: Verified Coach'), findsOneWidget);
      await t.enterText(find.byType(TextField).at(1), 'Client');
      await t.tap(find.text('Approve this sharing'));
      await t.pumpAndSettle();
      expect(repo.accepted, true);
      expect(repo.recording, false);
      expect(repo.heatmap, false);
      expect(repo.shared, 0);
    },
  );
  testWidgets('session receipt forwards original history payload', (t) async {
    final repo = FakeSharingRepository();
    List<Map<String, dynamic>>? received;
    await t.pumpWidget(
      MaterialApp(
        home: TrainerSharingPage(
          history: const [],
          repository: repo,
          onReceived: (rows) async {
            received = rows;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Receive recorded sessions'));
    await t.tap(find.text('Receive recorded sessions'));
    await t.pumpAndSettle();
    expect(received!.single['date'], '2026-09-25T10:00:00Z');
    expect(received!.single['durationSeconds'], 60);
    expect(repo.shared, 0);
  });
}
