import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/bench_press_form.dart';
import 'package:muscle_memory/exercise_form_catalog.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'baseline and revised form load, play, pause, change speed and reopen',
    (tester) async {
      const selected = String.fromEnvironment('FORM_QA_IDS');
      final ids = selected.isEmpty
          ? [
              'bench_press',
              'incline_dumbbell_press',
              'incline_press_machine',
              'lat_pulldown',
              'mag_narrow',
              'mag_medium',
              'mag_wide',
              'linear_row',
              'decline_fly_machine',
              'decline_press_machine',
              'assisted_chin_up',
              'mag_narrow',
            ]
          : selected.split(',');
      for (final id in ids) {
        final form = ExerciseFormCatalog.byId[id]!;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  child: ExerciseFormView(
                    key: UniqueKey(),
                    exerciseName: form.exerciseName,
                    definition: form,
                  ),
                ),
              ),
            ),
          ),
        );
        var ready = false;
        for (var attempt = 0; attempt < 30; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await tester.pump();
          expect(find.textContaining('読み込めませんでした'), findsNothing);
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            ready = true;
            break;
          }
        }
        expect(ready, isTrue, reason: 'Native loading failed: $id');
        debugPrint('QA_FORM_READY $id');
        if (Platform.isAndroid) {
          await Future<void>.delayed(const Duration(seconds: 2));
          debugPrint(
            'QA_FORM_CAMERA $id: ${await const MethodChannel("interactive_3d_plugin").invokeMethod<Object?>("debugCameraStates")}',
          );
        }
        // Native asset loading can finish before the first textured frame.
        // Begin motion evidence only after visible geometry reaches the screen.
        if (Platform.isAndroid) {
          var visible = false;
          for (var attempt = 0; attempt < 15; attempt++) {
            final pixels = await capture(
              binding,
              '${id}_warming',
              record: false,
            );
            if (await brightSceneFraction(tester, pixels) > .015) {
              visible = true;
              break;
            }
            await Future<void>.delayed(const Duration(seconds: 1));
            await tester.pump();
          }
          expect(visible, isTrue, reason: 'First visible frame failed: $id');
        }
        for (var frame = 0; frame < 4; frame++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          await tester.pump();
          final pixels = await capture(binding, '${id}_stage_$frame');
          if (frame == 3) {
            expect(
              await brightSceneFraction(tester, pixels),
              greaterThan(.015),
              reason: 'The native scene must contain visible geometry: $id',
            );
          }
        }
        await tester.tap(find.byKey(const Key('benchPressPlayPause')));
        await tester.pump();
        await capture(binding, '${id}_paused');
        await tester.tap(find.byKey(const Key('benchPressPlaybackSpeed')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('0.5倍速').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('benchPressPlayPause')));
        await tester.pump();
        await Future<void>.delayed(const Duration(seconds: 8));
        await capture(binding, '${id}_half_speed');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}

Future<List<int>> capture(
  IntegrationTestWidgetsFlutterBinding binding,
  String name, {
  bool record = true,
}) async {
  if (Platform.isAndroid) {
    final bytes = await const MethodChannel('com.musclememory/rest_timer')
        .invokeMethod<Uint8List>('debugScreenshot');
    if (!record) return bytes!;
    binding.reportData ??= <String, dynamic>{};
    final shots = binding.reportData!.putIfAbsent(
      'screenshots',
      () => <dynamic>[],
    ) as List;
    shots.add({'screenshotName': 'form_$name', 'bytes': bytes!.toList()});
    return bytes;
  } else {
    return binding.takeScreenshot('form_$name');
  }
}

Future<double> brightSceneFraction(WidgetTester tester, List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final image = (await codec.getNextFrame()).image;
  final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final rect = tester.getRect(find.byKey(const Key('benchPressNativeScene')));
  final scale =
      image.width /
      (tester.view.physicalSize.width / tester.view.devicePixelRatio);
  var visible = 0, total = 0;
  for (
    var y = (rect.top * scale).ceil();
    y < (rect.bottom * scale).floor().clamp(0, image.height);
    y += 4
  ) {
    for (
      var x = (rect.left * scale).ceil();
      x < (rect.right * scale).floor().clamp(0, image.width);
      x += 4
    ) {
      final i = (y * image.width + x) * 4;
      if (pixels.getUint8(i) > 100 &&
          pixels.getUint8(i + 1) > 100 &&
          pixels.getUint8(i + 2) > 100) {
        visible++;
      }
      total++;
    }
  }
  image.dispose();
  codec.dispose();
  return total == 0 ? 0 : visible / total;
}
