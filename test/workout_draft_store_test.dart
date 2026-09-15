import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/services/workout_draft_store.dart';

void main() {
  test(
    'slow writes remain ordered and cannot resurrect a cleared draft',
    () async {
      final firstWrite = Completer<void>();
      String? persisted;
      final writes = <String>[];
      final store = WorkoutDraftStore(
        write: (value) async {
          writes.add(value);
          if (value == 'first') await firstWrite.future;
          persisted = value;
        },
        remove: () async {
          persisted = null;
        },
      );
      final first = store.save('first');
      await Future<void>.delayed(Duration.zero);
      final second = store.save('latest');
      final clear = store.clear();
      await store.save('late UI callback');
      expect(writes, ['first']);
      firstWrite.complete();
      await Future.wait([first, second, clear]);
      expect(writes, ['first', 'latest']);
      expect(persisted, isNull);
      expect(store.isClosed, isTrue);
    },
  );

  test('a failed write does not block removal or a later save', () async {
    String? persisted;
    final store = WorkoutDraftStore(
      write: (value) async {
        if (value == 'fail') throw StateError('storage unavailable');
        persisted = value;
      },
      remove: () async {
        persisted = null;
      },
    );
    await expectLater(store.save('fail'), throwsStateError);
    await store.save('retry');
    expect(persisted, 'retry');
    await store.clear();
    expect(persisted, isNull);
  });
}
