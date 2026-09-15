import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native rest completion feedback and notification sound', (
    tester,
  ) async {
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await RestNotificationService.schedule(2);
    await Future<void>.delayed(const Duration(seconds: 3));
    await RestNotificationService.playCompletionFeedback();
    expect(tester.takeException(), isNull);
  });
}
