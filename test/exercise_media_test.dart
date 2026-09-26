import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/exercise_form_catalog.dart';
import 'package:setkeep/exercise_media.dart';
import 'package:setkeep/exercise_media_form_view.dart';
import 'package:setkeep/main.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _TestVideoPlatform extends VideoPlayerPlatform {
  final sources = <DataSource>[];
  final loops = <bool>[];
  final volumes = <double>[];
  final calls = <String>[];
  final streams = <int, StreamController<VideoEvent>>{};
  var nextId = 1;
  bool failPlay = false;

  @override
  Future<void> init() async => calls.add('init');

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {}

  @override
  Future<int?> create(DataSource dataSource) => _create(dataSource);

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) =>
      _create(options.dataSource);

  Future<int> _create(DataSource source) async {
    final id = nextId++;
    sources.add(source);
    calls.add('create');
    final stream = streams[id] = StreamController<VideoEvent>();
    stream.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(100, 100),
        duration: const Duration(seconds: 2),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;

  @override
  Widget buildView(int playerId) => const ColoredBox(color: Colors.blue);

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    loops.add(looping);
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> play(int playerId) async {
    if (failPlay) throw PlatformException(code: 'VideoError');
    calls.add('play');
  }

  @override
  Future<void> pause(int playerId) async => calls.add('pause');

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    await streams.remove(playerId)?.close();
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mapped = {
    'pec_fly': '0051',
    'barbell_squat': '0054',
    'leg_press': '0074',
    'rope_pushdown': '0085',
    'machine_lateral_raise': '0097',
  };

  test('five Vital IDs map to existing SETKEEP identities only', () async {
    expect(ExerciseMediaCatalog.trialEntries, hasLength(5));
    for (final entry in mapped.entries) {
      final media = ExerciseMediaCatalog.forExerciseId(entry.key)!;
      expect(media.exerciseId, entry.key);
      expect(media.provider, 'vital_animations');
      expect(media.providerAssetId, entry.value);
      expect(media.assetPath, endsWith('/${entry.value}.mp4'));
      expect(media.thumbnailAssetPath, endsWith('/${entry.value}.png'));
      expect(ExerciseFormCatalog.byId[entry.key], isNotNull);
    }
    expect(
      ExerciseMediaCatalog.forExerciseId('triceps_pushdown')?.exerciseId,
      'rope_pushdown',
    );
    expect(ExerciseMediaCatalog.forExerciseId('bench_press'), isNull);
    expect(ExerciseMediaCatalog.forExerciseId('lateral_raise'), isNull);
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(
      manifest.listAssets(),
      contains(ExerciseMediaCatalog.forExerciseId('pec_fly')!.assetPath),
    );
    expect(
      manifest.listAssets(),
      contains(
        ExerciseMediaCatalog.forExerciseId('pec_fly')!.thumbnailAssetPath,
      ),
    );
  });

  test('local Free50 source and selected videos match the real metadata', () {
    final jsonFile = File(
      'local_assets/vital_animations/free50/50gymworkouts.json',
    );
    if (!jsonFile.existsSync()) return; // Licensed files are never committed.
    final entries = jsonDecode(jsonFile.readAsStringSync()) as List;
    expect(entries, hasLength(50));
    expect(entries.map((e) => e['id']).toSet(), hasLength(50));
    for (final entry in mapped.entries) {
      final vital = entries.singleWhere((e) => e['id'] == entry.value);
      expect(vital['name'], isNotEmpty);
      final video = File(
        ExerciseMediaCatalog.forExerciseId(entry.key)!.assetPath,
      );
      expect(video.existsSync(), isTrue);
      expect(video.lengthSync(), greaterThan(100000));
      expect(
        File(ExerciseMediaCatalog.forExerciseId(entry.key)!.thumbnailAssetPath!)
            .existsSync(),
        isTrue,
      );
    }
  });

  group('trial form video', () {
    late VideoPlayerPlatform original;
    late _TestVideoPlatform video;

    setUp(() {
      original = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = video = _TestVideoPlatform();
    });
    tearDown(() => VideoPlayerPlatform.instance = original);

    testWidgets('all five detail pages prefer muted looping video', (
      tester,
    ) async {
      for (final id in mapped.keys) {
        final form = ExerciseFormCatalog.byId[id]!;
        await tester.pumpWidget(
          MaterialApp(
            home: ExerciseMuscleDetailPage(
              exercise: ExerciseTemplate.fromForm(form),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('exerciseVitalVideoCard')),
          findsOneWidget,
          reason: id,
        );
        expect(find.byType(VideoPlayer), findsOneWidget, reason: id);
        expect(
          video.sources.last.asset,
          ExerciseMediaCatalog.forExerciseId(id)!.assetPath,
        );
        expect(video.loops.last, isTrue);
        expect(video.volumes.last, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(video.calls.where((call) => call == 'dispose'), hasLength(5));
    });

    testWidgets('absent Vital asset keeps the existing 3D guide', (
      tester,
    ) async {
      final media = ExerciseMediaCatalog.forExerciseId('barbell_squat')!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ExerciseMediaFormView(
                  media: media,
                  assetAvailable: (_) async => false,
                  fallback: const SizedBox(height: 100, key: Key('existing3D')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('existing3D')), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
    });

    testWidgets('no Vital and no 3D keeps the existing alternative', (
      tester,
    ) async {
      final form = ExerciseFormCatalog.byId['leg_press']!;
      expect(form.available, isFalse);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ExerciseMediaFormView(
                  media: ExerciseMediaCatalog.forExerciseId('leg_press')!,
                  assetAvailable: (_) async => false,
                  fallback: const SizedBox(
                    height: 100,
                    key: Key('existingAlternative'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('existingAlternative')), findsOneWidget);
    });

    testWidgets('video failure falls back without crashing', (tester) async {
      video.failPlay = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ExerciseMediaFormView(
                  media: ExerciseMediaCatalog.forExerciseId('pec_fly')!,
                  assetAvailable: (_) async => true,
                  fallback: const SizedBox(
                    height: 100,
                    key: Key('failedFallback'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('failedFallback')), findsOneWidget);
    });

    testWidgets('video pauses under another route and resumes on return', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [exerciseMediaRouteObserver],
          home: Scaffold(
            body: ListView(
              children: [
                ExerciseMediaFormView(
                  media: ExerciseMediaCatalog.forExerciseId('pec_fly')!,
                  assetAvailable: (_) async => true,
                  fallback: const SizedBox(height: 100),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(video.calls, contains('play'));
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('other page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(video.calls, contains('pause'));
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(video.calls.where((call) => call == 'play'), hasLength(2));
    });

    testWidgets('unmapped exercise detail has no video', (tester) async {
      final form = ExerciseFormCatalog.byId['bench_press']!;
      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseMuscleDetailPage(
            exercise: ExerciseTemplate.fromForm(form),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('exerciseVitalVideoCard')), findsNothing);
      expect(find.byKey(const Key('exerciseMuscleModel3D')), findsOneWidget);
    });
  });
}
