import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:setkeep/body_weight.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'latest row remains single after editing and body survives background',
    (tester) async {
      final today = DateUtils.dateOnly(DateTime.now());
      SharedPreferences.setMockInitialValues({
        BodyWeightPreference.storageKey: jsonEncode(
          List.generate(
            12,
            (i) => BodyWeightEntry(
              id: 'w$i',
              recordedAt: today.subtract(Duration(days: 11 - i)),
              weightKg: 80 + i / 10,
            ).toJson(),
          ),
        ),
      });
      await tester.pumpWidget(const SetkeepApp());
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('editBodyWeightw11')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editBodyWeightw11')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bodyWeightField')), '87.5');
      await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('87.5 kg'), findsOneWidget);
      expect(await BodyWeightPreference.load(), hasLength(12));
      await captureScreen(binding, 'home_final_single_weight');
      await tester.tap(find.byIcon(Icons.accessibility_new_outlined));
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(seconds: 3));
      await tester.pump();
      const models = MethodChannel('interactive_3d_plugin');
      final before = Platform.isAndroid
          ? await models.invokeListMethod<dynamic>('debugCameraStates')
          : null;
      await waitForVisibleBody(tester, binding, 'body_before_background');
      debugPrint('QA_BODY_BACKGROUND_READY');
      await Future<void>.delayed(const Duration(seconds: 30));
      binding.scheduleFrame();
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(seconds: 1));
      if (Platform.isAndroid) {
        final after = await models.invokeListMethod<dynamic>(
          'debugCameraStates',
        );
        expect(after!.single['projection'], before!.single['projection']);
      }
      await waitForVisibleBody(tester, binding, 'body_after_background');
      expect(tester.takeException(), isNull);
    },
  );
}

// Camera matrices alone cannot detect a lost/blank native frame.
Future<(double, double)> bodyPixelMetrics(
  WidgetTester tester,
  List<int> png,
) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final rect = tester.getRect(
    find.byKey(const ValueKey('body-tab-continuous')),
  );
  final scale =
      image.width /
      (tester.view.physicalSize.width / tester.view.devicePixelRatio);
  final left = (rect.left * scale).ceil().clamp(0, image.width - 1);
  final right = (rect.right * scale).floor().clamp(0, image.width);
  final top = (rect.top * scale).ceil().clamp(0, image.height - 1);
  final bottom = (rect.bottom * scale).floor().clamp(0, image.height);
  var count = 0, minY = bottom, maxY = top;
  for (var y = top; y < bottom; y += 3) {
    for (var x = left; x < right; x += 3) {
      final i = (y * image.width + x) * 4;
      final r = pixels.getUint8(i),
          g = pixels.getUint8(i + 1),
          b = pixels.getUint8(i + 2);
      if (r > 100 && g > 100 && b > 100) {
        count++;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  image.dispose();
  codec.dispose();
  return (
    count * 9 / ((right - left) * (bottom - top)),
    (maxY - minY) / (bottom - top),
  );
}

Future<void> waitForVisibleBody(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  // Native model loading and the resumed Surface queue are asynchronous to
  // Flutter's pumpAndSettle. Wait for their pixels, not a guessed short delay.
  (double, double) metrics = (0, 0);
  for (var attempt = 0; attempt < 15; attempt++) {
    binding.scheduleFrame();
    await tester.pump();
    await Future<void>.delayed(const Duration(seconds: 1));
    try {
      metrics = await bodyPixelMetrics(
        tester,
        await captureScreen(binding, name),
      );
      if (metrics.$1 > 0.03 && metrics.$2 > 0.65) {
        debugPrint('QA_BODY_PIXELS $name: $metrics, attempts=${attempt + 1}');
        return;
      }
    } on PlatformException catch (error) {
      if (error.code != 'PIXEL_COPY') rethrow;
    }
  }
  expect(
    metrics.$1,
    greaterThan(0.03),
    reason: 'body must actually be visible',
  );
  expect(
    metrics.$2,
    greaterThan(0.65),
    reason: 'body must occupy a useful height',
  );
}

Future<List<int>> captureScreen(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  if (!Platform.isAndroid) return binding.takeScreenshot(name);
  // Do not convert FlutterSurfaceView to ImageView: that changes the surface
  // lifecycle we are testing and can hold an old frame of an external Texture.
  final bytes = await const MethodChannel('com.setkeep.app/rest_timer')
      .invokeMethod<Uint8List>('debugScreenshot');
  await File('${Directory.systemTemp.path}/$name.png').writeAsBytes(bytes!);
  return bytes;
}
