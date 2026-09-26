import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/exercise_form_catalog.dart';
import 'package:setkeep/exercise_list_thumbnail.dart';

void main() {
  testWidgets('verified 3D form uses its still image in a square slot', (
    tester,
  ) async {
    final path = ExerciseFormCatalog.byId['bench_press']!.thumbnailAssetPath;
    expect(path, 'assets/exercise_thumbnails/bench_press.png');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ExerciseListThumbnail(assetPath: path)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('exerciseListThumbnail'))),
      const Size.square(56),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, path);
    expect(image.fit, BoxFit.contain);
    expect(tester.takeException(), isNull);
  });

  testWidgets('form without a still image uses muted SETKEEP mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExerciseListThumbnail())),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('exerciseListThumbnail'))),
      const Size.square(56),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/brand/setkeep_splash_mark.png',
    );
    expect(image.color, const Color(0xFFAFB5B4));
    expect(image.colorBlendMode, BlendMode.srcIn);
    expect(tester.takeException(), isNull);
  });
}
