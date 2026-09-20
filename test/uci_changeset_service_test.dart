import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/router_liveness_probe.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/router_session.dart';

const _session = RouterSession(
  routerId: 'r1',
  ipAddress: '192.168.1.1',
  sysauth: 'sid-abc',
  useHttps: false,
  token: 1,
);

/// A clock the test drives. [advance] doubles as the service's delay hook, so
/// waiting for a backoff moves time forward without any real sleeping.
class _FakeClock {
  DateTime now = DateTime.utc(2026, 1, 1);
  Future<void> advance(Duration d) async {
    now = now.add(d);
  }
}

class _FakeProbe implements IRouterLivenessProbe {
  _FakeProbe(this.reachable);
  bool reachable;
  int calls = 0;

  /// When set, the router "comes back" once this many probes have been made.
  int? reachableAfterCalls;

  @override
  Future<bool> isReachable(String hostWithPort, bool useHttps) async {
    calls++;
    final threshold = reachableAfterCalls;
    if (threshold != null) return calls >= threshold;
    return reachable;
  }
}

/// Records every uci call and lets each one be scripted.
class _RecordingApi extends MockApiService {
  final List<String> calls = <String>[];

  Map<String, List<List<String>>> changes = <String, List<List<String>>>{};
  Object? setError;
  Object? addError;
  Object? applyError;
  Object? confirmError;
  Object? revertError;
  String addedSection = 'cfg0a1b2c';

  int get confirmCount => calls.where((c) => c == 'confirm').length;

  @override
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, Object> values,
    BuildContext? context,
  }) async {
    calls.add('set $config.$section ${values.keys.join(",")}');
    if (setError != null) throw setError!;
    return [0, 'success'];
  }

  @override
  Future<dynamic> uciAdd(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String type,
    required Map<String, dynamic> values,
    String? name,
    BuildContext? context,
  }) async {
    calls.add('add $config $type');
    if (addError != null) throw addError!;
    return [
      0,
      {'section': name ?? addedSection},
    ];
  }

  @override
  Future<dynamic> uciDelete(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    String? option,
    BuildContext? context,
  }) async {
    calls.add('delete $config.$section${option == null ? '' : '.$option'}');
    return [0, 'success'];
  }

  @override
  Future<Map<String, List<List<String>>>> uciChanges(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String? config,
    BuildContext? context,
  }) async {
    calls.add('changes');
    return changes;
  }

  @override
  Future<dynamic> uciRevert(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    calls.add('revert $config');
    if (revertError != null) throw revertError!;
    return [0, 'success'];
  }

  @override
  Future<dynamic> uciApply(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required bool rollback,
    required int timeoutSeconds,
    BuildContext? context,
  }) async {
    calls.add('apply rollback=$rollback timeout=$timeoutSeconds');
    if (applyError != null) throw applyError!;
    return [0, 'success'];
  }

  @override
  Future<dynamic> uciConfirm(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    calls.add('confirm');
    if (confirmError != null) throw confirmError!;
    return [0, 'success'];
  }
}

({_RecordingApi api, _FakeProbe probe, UciChangesetService service}) _build({
  bool reachable = true,
}) {
  final api = _RecordingApi();
  final probe = _FakeProbe(reachable);
  final clock = _FakeClock();
  return (
    api: api,
    probe: probe,
    service: UciChangesetService(
      api,
      probe: probe,
      clock: () => clock.now,
      delay: clock.advance,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stage', () {
    test(
      'runs operations in order and returns generated section ids',
      () async {
        final h = _build();
        h.api.addedSection = 'cfg09ab12';

        final sections = await h.service.stage(_session, const [
          UciAdd('dhcp', type: 'host', values: {'mac': 'AA:BB:CC:DD:EE:FF'}),
          UciSet('dhcp', section: 'lan', values: {'start': '100'}),
          UciRemove('firewall', section: 'cfg03', option: 'src_mac'),
        ]);

        expect(h.api.calls, [
          'add dhcp host',
          'set dhcp.lan start',
          'delete firewall.cfg03.src_mac',
        ]);
        expect(sections, {0: 'cfg09ab12'});
      },
    );

    test('a named add reports the name the caller chose', () async {
      final h = _build();

      final sections = await h.service.stage(_session, const [
        UciAdd(
          'firewall',
          type: 'rule',
          values: {'target': 'REJECT'},
          name: 'luci_mobile_block_aabb',
        ),
      ]);

      expect(sections[0], 'luci_mobile_block_aabb');
    });

    test('reverts every touched config when an operation fails', () async {
      final h = _build();
      h.api.setError = Exception('boom');

      await expectLater(
        h.service.stage(_session, const [
          UciAdd('dhcp', type: 'host', values: {'mac': 'AA'}),
          UciSet('firewall', section: 'cfg03', values: {'target': 'REJECT'}),
        ]),
        throwsA(
          isA<UciStagingException>()
              .having((e) => e.failedIndex, 'failedIndex', 1)
              .having((e) => e.revertFailed, 'revertFailed', isFalse)
              .having((e) => e.revertedConfigs, 'revertedConfigs', {
                'dhcp',
                'firewall',
              }),
        ),
      );

      expect(
        h.api.calls,
        containsAll(<String>['revert dhcp', 'revert firewall']),
      );
    });

    test('flags when the cleanup revert itself fails', () async {
      final h = _build();
      h.api.setError = Exception('boom');
      h.api.revertError = const RpcException(
        object: 'uci',
        method: 'revert',
        status: 6,
      );

      await expectLater(
        h.service.stage(_session, const [
          UciSet('dhcp', section: 'lan', values: {'start': '100'}),
        ]),
        throwsA(
          isA<UciStagingException>().having(
            (e) => e.revertFailed,
            'revertFailed',
            isTrue,
          ),
        ),
      );
    });

    test('nothing is committed - stage never calls apply or commit', () async {
      final h = _build();

      await h.service.stage(_session, const [
        UciSet('dhcp', section: 'lan', values: {'start': '100'}),
      ]);

      expect(h.api.calls.where((c) => c.startsWith('apply')), isEmpty);
      expect(h.api.confirmCount, 0);
    });
  });

  group('apply - checked', () {
    test('applies with rollback, then confirms once', () async {
      final h = _build();

      final outcome = await h.service.apply(_session);

      expect(outcome.phase, ApplyPhase.confirmed);
      expect(outcome.succeeded, isTrue);
      expect(outcome.reason, isNull);
      expect(h.api.confirmCount, 1);
      expect(h.api.calls, contains('apply rollback=true timeout=90'));
      // The apply must precede any confirm.
      expect(
        h.api.calls.indexWhere((c) => c.startsWith('apply')),
        lessThan(h.api.calls.indexOf('confirm')),
      );
    });

    test('a permission error on confirm means the session was lost', () async {
      final h = _build();
      h.api.confirmError = const RpcException(
        object: 'uci',
        method: 'confirm',
        status: 6,
      );

      final outcome = await h.service.apply(_session);

      expect(outcome.phase, ApplyPhase.rolledBack);
      expect(outcome.reason, RollbackReason.sessionLost);
      // It gives up immediately rather than retrying a hopeless confirm.
      expect(h.api.confirmCount, 1);
    });

    test('a no-data error on confirm means the timer already fired', () async {
      final h = _build();
      h.api.confirmError = const RpcException(
        object: 'uci',
        method: 'confirm',
        status: 5,
      );

      final outcome = await h.service.apply(_session);

      expect(outcome.reason, RollbackReason.deadlineMissed);
    });

    test('never confirms when the router stays unreachable', () async {
      final h = _build(reachable: false);

      final outcome = await h.service.apply(_session);

      expect(outcome.phase, ApplyPhase.rolledBack);
      expect(outcome.reason, RollbackReason.unreachable);
      expect(h.api.confirmCount, 0);
      expect(h.probe.calls, greaterThan(1));
    });

    test('stops probing before the router timer fires', () async {
      final h = _build(reachable: false);
      final phases = <(ApplyPhase, Duration)>[];

      await h.service.apply(
        _session,
        timeout: const Duration(seconds: 30),
        onPhase: (phase, remaining) => phases.add((phase, remaining)),
      );

      // Every awaiting-confirm tick must leave at least the guard band, so a
      // confirm can never land after the router has already reverted.
      final awaiting = phases.where((p) => p.$1 == ApplyPhase.awaitingConfirm);
      expect(awaiting, isNotEmpty);
      for (final tick in awaiting) {
        expect(tick.$2, greaterThanOrEqualTo(const Duration(seconds: 5)));
      }
      expect(phases.last.$1, ApplyPhase.rolledBack);
    });

    test('recovers when the router only answers on a later probe', () async {
      final h = _build(reachable: false);
      h.probe.reachableAfterCalls = 3;

      final outcome = await h.service.apply(_session);

      expect(outcome.phase, ApplyPhase.confirmed);
      expect(h.probe.calls, 3);
      expect(h.api.confirmCount, 1);
    });

    test('reports what was staged at the moment of the apply', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['set', 'cfg01', 'name', 'laptop'],
        ],
      };

      final outcome = await h.service.apply(_session);

      expect(outcome.applied.count, 1);
      expect(outcome.applied.configs, {'dhcp'});
      expect(outcome.applied.forConfig('dhcp').single.option, 'name');
    });
  });

  group('apply - failures and unchecked mode', () {
    test('a rejected apply reverts and reports routerRejected', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['set', 'cfg01', 'name', 'laptop'],
        ],
      };
      h.api.applyError = const RpcException(
        object: 'uci',
        method: 'apply',
        status: 6,
      );

      final outcome = await h.service.apply(_session);

      expect(outcome.phase, ApplyPhase.failed);
      expect(outcome.reason, RollbackReason.routerRejected);
      expect(h.api.calls, contains('revert dhcp'));
      expect(h.api.confirmCount, 0);
    });

    test(
      'unchecked mode commits without a rollback timer or confirm',
      () async {
        final h = _build();

        final outcome = await h.service.apply(
          _session,
          mode: ApplyMode.unchecked,
        );

        expect(outcome.phase, ApplyPhase.confirmed);
        expect(h.api.calls, contains('apply rollback=false timeout=0'));
        expect(h.api.confirmCount, 0);
        expect(h.probe.calls, 0);
      },
    );
  });

  group('pending', () {
    test('parses the router change rows into a changeset', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['set', 'cfg01', 'name', 'laptop'],
          ['add', 'cfg02', 'host'],
        ],
        'firewall': [
          ['remove', 'cfg03'],
        ],
      };

      final set = await h.service.pending(_session);

      expect(set.isNotEmpty, isTrue);
      expect(set.count, 3);
      expect(set.configs, {'dhcp', 'firewall'});
      expect(set.forConfig('dhcp').first.op, UciOp.set);
      expect(set.forConfig('dhcp')[1].op, UciOp.add);
      expect(set.forConfig('firewall').single.option, isNull);
    });

    test('foreignTo isolates changes this app did not stage', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['set', 'cfg01', 'name', 'laptop'],
        ],
        'network': [
          ['set', 'lan', 'ipaddr', '10.0.0.1'],
        ],
      };

      final foreign = (await h.service.pending(_session)).foreignTo({'dhcp'});

      expect(foreign.configs, {'network'});
    });
  });
}
