import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interactive_3d/src/form_asset_bundle.dart';
import 'package:muscle_memory/exercise_form_catalog.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FileFormBundle extends CachingAssetBundle {
  final reads = <String, int>{};
  @override
  Future<ByteData> load(String key) async {
    reads.update(key, (n) => n + 1, ifAbsent: () => 1);
    return ByteData.sublistView(await File(key).readAsBytes());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog distinguishes reviewed scenes from explicit previews', () {
    final generated = File('lib/exercise_form_catalog.g.dart')
        .readAsStringSync();
    expect(generated, isNot(contains('TEMPORARY QA CANDIDATES')));
    final source = jsonDecode(
      File('tool/exercise_forms/catalog.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final raw in source['exercises'] as List) {
      final entry = raw as Map<String, dynamic>;
      final form = ExerciseFormCatalog.byId[entry['exerciseId']]!;
      expect(
        form.available,
        entry['status'] == 'verified' || entry['previewEnabled'] == true,
      );
      if (form.isPreview) {
        expect(form.status, 'authored');
        expect((entry['review'] as Map)['staticPose'], isTrue);
        expect(File(form.assetPath!).existsSync(), isTrue);
      }
      if (form.status != 'verified' ||
          {'bench_press', 'incline_dumbbell_press'}.contains(form.exerciseId)) {
        continue;
      }
      expect(entry['references'], isNotEmpty);
      expect(form.primaryMuscleLabels, isNotEmpty);
      expect(form.secondaryMuscleLabels.length, form.secondaryMuscles.length);
      for (final check in [
        'equipmentReference',
        'staticPose',
        'motion',
        'android',
        'ios',
        'productionRoute',
      ]) {
        expect(
          (entry['review'] as Map)[check],
          isTrue,
          reason: '${form.exerciseId}: $check',
        );
      }
    }
  });

  test('trial availability requires explicit opt-in, pose QA and an asset', () {
    final source = <String, Object?>{
      'status': 'authored',
      'assetPath': 'assets/models/forms/example.form.json',
      'previewEnabled': true,
      'review': {'staticPose': true},
    };
    expect(ExerciseFormDefinition(source).isPreview, isTrue);
    expect(ExerciseFormDefinition(source).available, isTrue);
    for (final override in <Map<String, Object?>>[
      {'previewEnabled': false},
      {'status': 'planned'},
      {'assetPath': null},
      {'review': {'staticPose': false}},
    ]) {
      expect(ExerciseFormDefinition({...source, ...override}).available, isFalse);
    }
    expect(ExerciseFormCatalog.byId['chin_up']!.available, isFalse);
    expect(ExerciseFormCatalog.byId['lat_pulldown']!.available, isFalse);
    expect(ExerciseFormCatalog.entries.where((form) => form.isPreview), isEmpty);
  });

  test(
    'catalog preserves the two existing scenes and legacy chin-up identity',
    () {
      final entries = ExerciseFormCatalog.entries;
      expect(
        entries.map((e) => e.exerciseId).toSet(),
        hasLength(entries.length),
      );
      expect(
        ExerciseFormCatalog.forName('ベンチプレス')!.assetPath,
        'assets/models/bench_press.glb',
      );
      expect(
        ExerciseFormCatalog.forName('インクラインダンベルプレス')!.assetPath,
        'assets/models/incline_dumbbell_press.glb',
      );
      expect(
        ExerciseFormCatalog.forName('懸垂'),
        same(ExerciseFormCatalog.forName('チンニング')),
      );
      final source = <String, dynamic>{
        'exerciseName': '懸垂',
        'bodyPart': '背中',
        'weight': 0,
        'reps': 8,
        'completed': true,
      };
      final restored = RecordedSet.fromJson(source);
      expect(restored.toJson()['exerciseName'], '懸垂');
      expect(exerciseDisplayName(restored.exerciseName), '懸垂');
      expect(exerciseDisplayName(restored.exerciseName, exerciseId: 'chin_up'), 'チンニング');
      expect(restored.reps, 8);
      expect(restored.hasRequiredValues, isTrue);
    },
  );

  test(
    'back extension accepts bodyweight or extra load without changing storage',
    () {
      expect(ExerciseFormCatalog.byId['back_extension']!.primaryMuscleLabels, [
        '脊柱起立筋',
      ]);
      for (final load in [0.0, 5.0, 10.0, 20.0]) {
        final set = RecordedSet(
          exerciseName: 'バックエクステンション',
          bodyPart: '背中',
          weight: load,
          reps: 12,
          completed: true,
        );
        expect(set.hasRequiredValues, isTrue);
        final copy = RecordedSet.fromJson(jsonDecode(jsonEncode(set.toJson())));
        expect(copy.weight, load);
        expect(copy.reps, 12);
        expect(copy.exerciseName, set.exerciseName);
        expect(copy.displaySummary, contains(load == 0 ? '自重' : '+'));
      }
      expect(
        const RecordedSet(
          weight: 0,
          reps: 12,
          completed: true,
        ).hasRequiredValues,
        isFalse,
      );
      expect(
        const RecordedSet(
          exerciseName: 'バックエクステンション',
          weight: -5,
          reps: 12,
          completed: true,
        ).hasRequiredValues,
        isFalse,
      );
    },
  );

  test(
    'new built-ins preserve existing custom definitions across backups',
    () async {
      const custom = ExerciseTemplate(
        name: 'ケーブルフライ',
        bodyPart: '胸',
        equipment: '独自ケーブル',
        startWeight: 12.5,
        recordType: ExerciseRecordType.bodyweightReps,
      );
      SharedPreferences.setMockInitialValues({
        'custom_exercises': jsonEncode([custom.toJson()]),
      });
      await CustomExercisePreference.load();
      addTearDown(() => CustomExercisePreference.exercises = []);
      expect(
        recordTypeForExerciseName(custom.name),
        ExerciseRecordType.bodyweightReps,
      );
      final backup = decodeExerciseTemplates(
        jsonDecode(
          jsonEncode(
            CustomExercisePreference.exercises.map((e) => e.toJson()).toList(),
          ),
        ),
      );
      await CustomExercisePreference.replaceAll(backup);
      await CustomExercisePreference.load();
      expect(CustomExercisePreference.exercises.single.startWeight, 12.5);
      expect(
        await CustomExercisePreference.update(custom.name, custom),
        isTrue,
      );
      expect(await CustomExercisePreference.add(custom), isFalse);
    },
  );

  test(
    'shared scenes rebuild aligned GLBs with unchanged buffer data',
    () async {
      final recipes = Directory('assets/models/forms')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.form.json'));
      expect(recipes, isNotEmpty);
      for (final recipeFile in recipes) {
        final recipe = jsonDecode(recipeFile.readAsStringSync()) as Map;
        final bundle = FileFormBundle();
        final bytes = await loadFormAsset(recipeFile.path, bundle: bundle);
        final header = ByteData.sublistView(bytes);
        expect(header.getUint32(0, Endian.little), 0x46546c67);
        expect(header.getUint32(4, Endian.little), 2);
        expect(header.getUint32(8, Endian.little), bytes.length);
        final jsonSize = header.getUint32(12, Endian.little);
        final gltf =
            jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonSize))) as Map;
        final views = gltf['bufferViews'] as List;
        final refs = recipe['chunks'] as List;
        expect(gltf['skins'], isNotEmpty);
        expect(gltf['animations'], hasLength(1));
        expect(gltf['nodes'], recipe['gltf']['nodes']);
        for (var i = 0; i < views.length; i++) {
          final offset = views[i]['byteOffset'] as int;
          final length = views[i]['byteLength'] as int;
          expect(offset % 4, 0);
          expect(
            bytes.sublist(
              28 + jsonSize + offset,
              28 + jsonSize + offset + length,
            ),
            orderedEquals(File(refs[i]['path'] as String).readAsBytesSync()),
          );
        }
        expect(
          bundle.reads.values.every((n) => n == 1),
          isTrue,
          reason: 'Repeated buffers are loaded once for the selected scene',
        );
      }
    },
    // Validate every packed scene; the growing catalog exceeds 30s on QA hosts.
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
