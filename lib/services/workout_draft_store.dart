/// Orders draft writes and makes clearing a terminal operation for this session.
/// A write already in flight must finish before removal, and later UI callbacks
/// must never recreate a completed or discarded workout.
class WorkoutDraftStore {
  WorkoutDraftStore({required this.write, required this.remove});

  final Future<void> Function(String) write;
  final Future<void> Function() remove;
  Future<void> _pending = Future<void>.value();
  bool _closed = false;
  bool get isClosed => _closed;

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    // A failed write must not prevent a later retry or explicit removal.
    // The caller still receives the original failure through result.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> save(String snapshot) {
    if (_closed) return Future<void>.value();
    return _enqueue(() => write(snapshot));
  }

  Future<void> clear() {
    _closed = true;
    return _enqueue(remove);
  }
}
