import 'package:flutter_test/flutter_test.dart';

import 'support/exercise_identity_flow.dart';

void main() {
  testWidgets('identity picker draft resume completion history and edit', (
    t,
  ) async {
    await verifyIdentityFlow(t);
  });
}
