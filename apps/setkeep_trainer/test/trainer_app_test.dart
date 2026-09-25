import 'package:setkeep/main.dart'
    show ExerciseInputCard, ExercisePickerSheet, BodyMapPage;
import 'package:setkeep/design/family_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setkeep_trainer/trainer_widgets.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/services/account_auth_service.dart';
import 'package:setkeep/trainer/trainer_repository.dart';
import 'package:setkeep_trainer/main.dart';

class FakeAuth implements AccountAuthService {
  final events = StreamController<void>.broadcast();
  bool signedIn = true;
  @override
  bool get isSignedIn => signedIn;
  @override
  String get email => 'trainer@example.test';
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<void> signOut() async {
    signedIn = false;
    events.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRepository implements TrainerRepository {
  final links = <Map<String, dynamic>>[];
  final savedMenus = <Map<String, dynamic>>[];
  Map<String, dynamic>? savedProfile = {'display_name': 'Coach'};
  String? recordedClient;
  String? recordedRequest;
  List<Map<String, dynamic>> recordedSets = [];
  bool fail = false;
  final historyRows = <Map<String, dynamic>>[];
  @override
  Future<List<Map<String, dynamic>>> tenants() async => [
    {'id': 'tenant-a', 'name': 'Tenant A'},
  ];
  @override
  TrainerRepository forTenant(String tenantId) => this;
  @override
  String get userId => 'trainer-id';
  @override
  Future<Map<String, dynamic>?> profile() async {
    if (fail) throw Exception();
    return savedProfile;
  }

  @override
  Future<void> saveProfile(String name) async {
    savedProfile = {'display_name': name};
  }

  @override
  Future<List<Map<String, dynamic>>> clients() async => links;
  @override
  Future<List<Map<String, dynamic>>> menus({String? clientId}) async =>
      savedMenus;
  @override
  Future<List<Map<String, dynamic>>> notes(String clientId) async => [];
  @override
  Future<List<Map<String, dynamic>>> workouts(
    String clientId, {
    int offset = 0,
  }) async => offset == 0 ? historyRows : [];
  @override
  Future<void> addMenu(
    String clientId,
    String name,
    String note,
    List<Map<String, dynamic>> items,
  ) async {
    savedMenus.add({
      'client_id': clientId,
      'name': name,
      'note': note,
      'items': items,
    });
  }

  @override
  Future<void> recordWorkout(
    String clientId,
    String requestId,
    DateTime date,
    List<Map<String, dynamic>> sets,
  ) async {
    recordedClient = clientId;
    recordedRequest = requestId;
    recordedSets = sets;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DelayedRepository extends FakeRepository {
  final pending = Completer<List<Map<String, dynamic>>>();
  @override
  Future<List<Map<String, dynamic>>> clients() => pending.future;
}

class MultiTenantRepository extends FakeRepository {
  final first = DelayedRepository();
  final second = FakeRepository()
    ..links.add({...link(), 'client_name': 'Tenant B Client'});
  @override
  Future<List<Map<String, dynamic>>> tenants() async => [
    {'id': 'a', 'name': 'Tenant A'},
    {'id': 'b', 'name': 'Tenant B'},
  ];
  @override
  TrainerRepository forTenant(String id) => id == 'a' ? first : second;
}

Map<String, dynamic> link({bool recording = false}) => {
  'client_id': 'client-id',
  'client_name': 'Client',
  'created_at': '2026-09-25',
  'allow_recording': recording,
  'share_heatmap': false,
};
Map<String, dynamic> menuFixture() => {
  'client_id': 'client-id',
  'name': 'Strength A',
  'note': '',
  'items': [
    {
      'exercise_id': 'bench_press',
      'exercise_name': 'ベンチプレス',
      'body_part': '胸',
      'equipment': 'バーベル',
      'record_type': 'weightReps',
      'set_values': [
        {'weight': 20.0, 'reps': 10},
        {'weight': 25.0, 'reps': 8},
      ],
    },
  ],
};
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('missing configuration is actionable and does not crash', (
    t,
  ) async {
    await t.pumpWidget(const TrainerApp());
    expect(find.text('SETKEEP TRAINER'), findsOneWidget);
    expect(find.textContaining('Supabase configuration'), findsOneWidget);
  });
  for (final size in [const Size(390, 844), const Size(1024, 768)]) {
    testWidgets('empty navigation at $size and logout', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final auth = FakeAuth(), repo = FakeRepository();
      addTearDown(auth.events.close);
      await t.pumpWidget(TrainerApp(auth: auth, repository: repo));
      await t.pumpAndSettle();
      expect(find.textContaining('No clients yet'), findsOneWidget);
      await t.tap(find.text('Menus'));
      await t.pumpAndSettle();
      expect(find.textContaining('No menus yet'), findsOneWidget);
      await t.tap(find.text('Profile'));
      await t.pumpAndSettle();
      await t.tap(find.text('Sign out'));
      await t.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('Japanese home renders with a client', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearLocalesTestValue);
    final auth = FakeAuth(), repo = FakeRepository()..links.add(link());
    addTearDown(auth.events.close);
    await t.pumpWidget(TrainerApp(auth: auth, repository: repo));
    await t.pumpAndSettle();
    expect(find.text('担当顧客 1人'), findsOneWidget);
    expect(find.text('Client'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('new trainer profile uses existing identity', (t) async {
    final auth = FakeAuth(), repo = FakeRepository()..savedProfile = null;
    addTearDown(auth.events.close);
    await t.pumpWidget(TrainerApp(auth: auth, repository: repo));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'New Coach');
    await t.tap(find.text('Start coaching'));
    await t.pumpAndSettle();
    expect(repo.savedProfile?['display_name'], 'New Coach');
    expect(find.text('Hello, New Coach'), findsOneWidget);
  });
  testWidgets('load error supports retry', (t) async {
    final auth = FakeAuth(), repo = FakeRepository()..fail = true;
    addTearDown(auth.events.close);
    await t.pumpWidget(TrainerApp(auth: auth, repository: repo));
    await t.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    repo.fail = false;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.textContaining('No clients yet'), findsOneWidget);
  });
  testWidgets('client recording and heatmap disabled without consent', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: ClientPage(repository: FakeRepository(), link: link()),
      ),
    );
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Record session'),
          )
          .onPressed,
      isNull,
    );
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Heatmap'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('menu uses shared catalog with target client and set values', (
    t,
  ) async {
    final repo = FakeRepository();
    await t.pumpWidget(
      MaterialApp(
        theme: familyTheme(FamilyPalette.trainer),
        home: MenuEditor(
          repository: repo,
          clients: [link()],
          existing: menuFixture(),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(ExerciseInputCard), findsOneWidget);
    expect(find.byKey(const Key('toggleAllSets0')), findsNothing);
    await t.enterText(find.byType(TextField).first, 'Strength A');
    await t.scrollUntilVisible(
      find.text('Save'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(repo.savedMenus.single['client_id'], 'client-id');
    final item = (repo.savedMenus.single['items'] as List).single as Map;
    expect(item['exercise_id'], isNotEmpty);
    expect(item['set_values'], hasLength(2));
    expect(item['set_values'][0]['weight'], 20);
    expect(item['set_values'][1]['weight'], 25);
    expect(item['set_values'][1]['reps'], 8);
  });
  testWidgets('session writes reusable SETKEEP recorded sets', (t) async {
    final repo = FakeRepository();
    await t.pumpWidget(
      MaterialApp(
        theme: familyTheme(FamilyPalette.trainer),
        home: MenuEditor(
          repository: repo,
          clients: [link(recording: true)],
          recording: true,
          existing: menuFixture(),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Save'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(repo.recordedClient, 'client-id');
    expect(repo.recordedRequest, hasLength(36));
    expect(repo.recordedSets, hasLength(2));
    expect(repo.recordedSets.first['completed'], true);
    expect(repo.recordedSets.first['exerciseId'], isNotEmpty);
  });
  testWidgets('invalid menu numbers are not persisted', (t) async {
    final repo = FakeRepository();
    await t.pumpWidget(
      MaterialApp(
        theme: familyTheme(FamilyPalette.trainer),
        home: MenuEditor(repository: repo, clients: [link()]),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), 'Bad');
    // Empty exercise list must never persist as a menu.
    await t.scrollUntilVisible(
      find.text('Save'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(repo.savedMenus, isEmpty);
  });
  testWidgets('trainer uses the original body map and blue palette', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: familyTheme(FamilyPalette.trainer),
        home: const HeatmapPage(workouts: []),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(BodyMapPage), findsOneWidget);
    expect(find.byKey(const Key('musclePeriodweek')), findsOneWidget);
    expect(
      Theme.of(t.element(find.byType(BodyMapPage)))
          .extension<FamilyPalette>()!
          .accent,
      const Color(0xFF79D5F6),
    );
  });
  testWidgets('menu opens the real shared picker', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: familyTheme(FamilyPalette.trainer),
        home: MenuEditor(repository: FakeRepository(), clients: [link()]),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Add exercise'));
    await t.tap(find.text('Add exercise'));
    await t.pumpAndSettle();
    expect(find.byType(ExercisePickerSheet), findsOneWidget);
  });
  testWidgets('tenant switch discards previous routes and late responses', (
    t,
  ) async {
    final auth = FakeAuth(), repo = MultiTenantRepository();
    addTearDown(auth.events.close);
    await t.pumpWidget(TrainerApp(auth: auth, repository: repo));
    await t.pump();
    await t.pump();
    await t.tap(find.byType(DropdownButton<String>));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Tenant B').last);
    await t.pumpAndSettle();
    expect(find.text('Tenant B Client'), findsOneWidget);
    repo.first.pending.complete([
      {...link(), 'client_name': 'Tenant A Secret'},
    ]);
    await t.pumpAndSettle();
    expect(find.text('Tenant A Secret'), findsNothing);
    await t.tap(find.text('Tenant B Client'));
    await t.pumpAndSettle();
    expect(find.byType(ClientPage), findsOneWidget);
    await t.tap(find.byType(DropdownButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Tenant A').last);
    await t.pumpAndSettle();
    expect(find.byType(ClientPage), findsNothing);
    expect(find.text('Tenant B Client'), findsNothing);
    expect(find.text('Tenant A Secret'), findsOneWidget);
  });
  testWidgets(
    'shared previous-record action applies the permitted client history',
    (t) async {
      final repo = FakeRepository()
        ..historyRows.add({
          'performed_at': DateTime.now().toIso8601String(),
          'sets': [
            {
              'exerciseId': 'bench_press',
              'exerciseName': 'ベンチプレス',
              'recordType': 'weightReps',
              'weight': 42.0,
              'reps': 6,
              'completed': true,
            },
          ],
        });
      await t.pumpWidget(
        MaterialApp(
          theme: familyTheme(FamilyPalette.trainer),
          home: MenuEditor(
            repository: repo,
            clients: [link()],
            existing: menuFixture(),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('applyPrevious0')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const Key('applyPrevious0')));
      await t.pumpAndSettle();
      final exercise = t
          .widget<ExerciseInputCard>(find.byType(ExerciseInputCard))
          .exercise;
      expect(exercise.sets, hasLength(1));
      expect(exercise.sets.single.weight, 42);
      expect(exercise.sets.single.reps, 6);
    },
  );
}
