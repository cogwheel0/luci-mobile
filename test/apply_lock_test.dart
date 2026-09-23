import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/state/apply_lock.dart';

void main() {
  group('serialising applies', () {
    // rpcd keeps one staging area per session, so two applies in flight can
    // stage into the same set and whichever calls uci.apply first commits
    // both.
    test('a second run waits for the first to finish', () async {
      final lock = ApplyLock();
      final order = <String>[];
      final first = Completer<void>();

      final a = lock.run(() async {
        order.add('a-start');
        await first.future;
        order.add('a-end');
        return 'a';
      });
      final b = lock.run(() async {
        order.add('b-start');
        return 'b';
      });

      // b must not have begun while a is still running.
      await Future<void>.delayed(Duration.zero);
      expect(order, ['a-start']);

      first.complete();
      expect(await a, 'a');
      expect(await b, 'b');
      expect(order, ['a-start', 'a-end', 'b-start']);
    });

    // A failed apply must not wedge every apply after it — including one
    // that was already waiting behind it when it failed.
    test('a successor already queued behind a failure still runs', () async {
      final lock = ApplyLock();
      final gate = Completer<void>();

      final failing = lock.run<String>(() async {
        await gate.future;
        throw StateError('nope');
      });
      final queued = lock.run(() async => 'after');

      gate.complete();
      await expectLater(failing, throwsStateError);
      expect(await queued, 'after');
    });

    test('a failure does not block a later run', () async {
      final lock = ApplyLock();

      final failing = lock.run<String>(() async => throw StateError('nope'));
      await expectLater(failing, throwsStateError);

      expect(await lock.run(() async => 'after'), 'after');
    });

    test('the error reaches the caller that queued it', () async {
      final lock = ApplyLock();
      unawaited(lock.run(() async => 'ok'));
      await expectLater(
        lock.run<String>(() async => throw StateError('mine')),
        throwsStateError,
      );
    });

    // The guard that matters most is in applyUciOperations, not here: a
    // queued apply must abandon if the user switched routers while it
    // waited. This pins the lock behaviour that makes such a wait possible.
    test('a run can observe state that changed while it waited', () async {
      final lock = ApplyLock();
      final gate = Completer<void>();
      var selected = 'router-a';

      final first = lock.run(() async {
        await gate.future;
        return 'first';
      });
      final second = lock.run(() async => selected);

      selected = 'router-b';
      gate.complete();
      await first;
      expect(
        await second,
        'router-b',
        reason: 'the queued body runs after the switch, so it must re-check',
      );
    });

    test('order is preserved across several queued runs', () async {
      final lock = ApplyLock();
      final order = <int>[];
      final runs = [
        for (var i = 0; i < 5; i++)
          lock.run(() async {
            await Future<void>.delayed(const Duration(milliseconds: 1));
            order.add(i);
          }),
      ];
      await Future.wait(runs);
      expect(order, [0, 1, 2, 3, 4]);
    });
  });
}
