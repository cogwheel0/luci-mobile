import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Serialises applies so two screens cannot interleave on one session.
///
/// `SessionGuard.run` captures the session but does not serialise anything,
/// and rpcd keeps one staging area per session: two applies in flight can
/// therefore stage into the same set, and whichever calls `uci.apply` first
/// commits both. The foreign-change guard catches that and refuses, which is
/// safe but means one of the two operations simply fails. Holding a lock from
/// staging through confirmation makes them queue instead.
class ApplyLock {
  Future<void> _tail = Future<void>.value();

  /// Runs [body] once every earlier call has finished.
  Future<T> run<T>(Future<T> Function() body) {
    final done = Completer<void>();
    final previous = _tail;
    _tail = done.future;
    return previous
        // A failed apply must not wedge the queue for everything after it.
        .catchError((_) {})
        .then((_) => body())
        .whenComplete(done.complete);
  }
}

final applyLockProvider = Provider<ApplyLock>((ref) => ApplyLock());
