import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/exercise_identity_flow.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('identity and HYROX production input persistence flow', (
    t,
  ) async {
    await verifyIdentityFlow(
      t,
      screenshot: (name) async {
        await t.pumpAndSettle();
        if (Platform.isAndroid) {
          final bytes = await const MethodChannel('com.musclememory/rest_timer')
              .invokeMethod<Uint8List>('debugScreenshot');
          binding.reportData ??= <String, dynamic>{};
          final shots = binding.reportData!.putIfAbsent(
            'screenshots',
            () => <dynamic>[],
          ) as List;
          shots.add({
            'screenshotName': 'identity_$name',
            'bytes': bytes!.toList(),
          });
        } else {
          await binding.takeScreenshot('identity_$name');
        }
      },
    );
  });
}
