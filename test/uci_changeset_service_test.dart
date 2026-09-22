import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/firewall_planner.dart';
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
  Object? changesError;

  /// Sections whose delete throws.
  Set<String> deleteErrorsFor = const {};

  /// Like [changesError], but only once `apply` has been called - the read
  /// before apply succeeds, the session-liveness probes after it fail.
  Object? changesErrorAfterApply;
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
    if (deleteErrorsFor.contains(section)) throw Exception('timeout');
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
    if (changesError != null) throw changesError!;
    if (changesErrorAfterApply != null &&
        calls.any((c) => c.startsWith('apply'))) {
      throw changesErrorAfterApply!;
    }
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

  _foreignChangeRegressions();
  _applyFailureCleanupReporting();

  group('stage', () {
    test(
      'runs operations in order and returns generated section ids',
      () async {
        final h = _build();
        h.api.addedSection = 'cfg09ab12';

        final staged = await h.service.stage(_session, const [
          UciAdd('dhcp', type: 'host', values: {'mac': 'AA:BB:CC:DD:EE:FF'}),
          UciSet('dhcp', section: 'lan', values: {'start': '100'}),
          UciRemove('firewall', section: 'cfg03', option: 'src_mac'),
        ]);

        expect(h.api.calls, [
          // Read first, so cleanup can tell our configs from anybody
          // else's before it reverts anything.
          'changes',
          'add dhcp host',
          'set dhcp.lan start',
          'delete firewall.cfg03.src_mac',
        ]);
        expect(staged.sections, {0: 'cfg09ab12'});
      },
    );

    test('a named add reports the name the caller chose', () async {
      final h = _build();

      final staged = await h.service.stage(_session, const [
        UciAdd(
          'firewall',
          type: 'rule',
          values: {'target': 'REJECT'},
          name: 'luci_mobile_block_aabb',
        ),
      ]);

      expect(staged.sections[0], 'luci_mobile_block_aabb');
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

    // LuCI's /admin/ubus proxy reports a dead session as a JSON-RPC error
    // with no ubus status at all - only the message says "Access denied".
    // Treating that as transient meant probing for the whole window and then
    // reporting the router unreachable, which it was not.
    test('an access-denied error without a status is a lost session', () async {
      final h = _build();
      const denied = RpcException(
        object: 'uci',
        method: 'confirm',
        detail: 'Access denied',
      );
      h.api.changesErrorAfterApply = denied;
      h.api.confirmError = denied;

      final outcome = await h.service.apply(_session);

      expect(outcome.phase, ApplyPhase.rolledBack);
      expect(outcome.reason, RollbackReason.sessionLost);
      expect(h.api.confirmCount, 1);
      expect(h.probe.calls, 1, reason: 'no point probing a dead session');
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
    // Applying blind would commit whatever is staged, including the rows the
    // foreign-change guard exists to refuse; and a failure after that would
    // have nothing to revert or report.
    test('an unreadable staging state refuses and backs out', () async {
      final h = _build();
      h.api.changesError = const RpcException(
        object: 'uci',
        method: 'changes',
        detail: 'timeout',
      );

      final outcome = await h.service.apply(
        _session,
        ours: const {'dhcp', 'network'},
        baseline: const UciChangeSet(
          byConfig: {
            'network': [
              UciChange(op: UciOp.set, config: 'network', section: 'lan'),
            ],
          },
          fetchedAt: null,
        ),
      );

      expect(outcome.phase, ApplyPhase.failed);
      expect(outcome.reason, RollbackReason.stateUnknown);
      expect(h.api.calls.where((c) => c.startsWith('apply')), isEmpty);
      // Only the config we alone dirtied is backed out; the one that was
      // already dirty is left alone and reported, as stage() does.
      expect(h.api.calls, contains('revert dhcp'));
      expect(h.api.calls, isNot(contains('revert network')));
      expect(outcome.stillStaged, {'network'});
    });

    // Same policy as stage(): with no baseline, a revert could discard an
    // edit the user still wanted, so nothing is reverted - and everything we
    // touched is reported, because it is still there.
    test(
      'an unreadable staging state with no baseline reverts nothing',
      () async {
        final h = _build();
        h.api.changesError = Exception('timeout');

        final outcome = await h.service.apply(_session, ours: const {'dhcp'});

        expect(outcome.reason, RollbackReason.stateUnknown);
        expect(h.api.calls.where((c) => c.startsWith('revert')), isEmpty);
        expect(outcome.stillStaged, {'dhcp'});
      },
    );

    test('an unreadable staging state names what it could not clear', () async {
      final h = _build();
      h.api.changesError = Exception('timeout');
      h.api.revertError = const RpcException(
        object: 'uci',
        method: 'revert',
        status: 6,
      );

      final outcome = await h.service.apply(
        _session,
        ours: const {'dhcp'},
        baseline: const UciChangeSet.empty(),
      );

      expect(outcome.reason, RollbackReason.stateUnknown);
      expect(outcome.stillStaged, {'dhcp'});
    });

    test('a rejected apply tells the progress listener it failed', () async {
      final h = _build();
      h.api.applyError = Exception('boom');
      final phases = <ApplyPhase>[];

      await h.service.apply(_session, onPhase: (phase, _) => phases.add(phase));

      expect(phases.last, ApplyPhase.failed);
    });

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
    // libuci stages a named section as a `set` of its type, three elements
    // and no value. Read as anything but an add, a leftover named forward
    // would be invisible to every retry rule.
    test('a three-element set row is a named section add', () {
      final change = UciChange.fromWire('firewall', const [
        'set',
        'luci_mobile_plex',
        'redirect',
      ]);
      expect(change!.op, UciOp.add);
      expect(change.section, 'luci_mobile_plex');
      expect(change.option, 'redirect');
      final set = UciChangeSet.fromWire({
        'firewall': [
          ['set', 'luci_mobile_plex', 'redirect'],
          ['set', 'luci_mobile_plex', 'name', 'Plex'],
        ],
      });
      expect(set.hasAdd('firewall', 'luci_mobile_plex'), isTrue);
      expect(set.addedSections('firewall', 'redirect'), ['luci_mobile_plex']);
      expect(
        FirewallPlanner.takenSectionNames({'luci_mobile_plex', 'cfg01'}, set),
        {'cfg01'},
      );
    });

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

      final foreign = (await h.service.pending(
        _session,
      )).foreignTo({'dhcp'}, writtenKeys: const {'dhcp|set|cfg01|name'});

      expect(foreign.configs, {'network'});
    });
  });
}

// ---------------------------------------------------------------------------
// `uci.apply` commits the whole session and `uci.revert` is config-wide, so
// neither may be used as if it only touched the configs this operation named.
//
// Measured on OpenWrt 24.10.4: rpcd stages per session, so the changes at
// risk here are this session's own leftovers — a failed batch, an edit backed
// out of — not another admin's. Another rpcd session's work is invisible to
// `uci.changes` and survives our apply untouched.
// ---------------------------------------------------------------------------

void _foreignChangeRegressions() {
  group('unrelated changes are still staged', () {
    // Applying would commit the leftover firewall edit alongside ours.
    test('apply refuses rather than committing an unrelated edit', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['set', 'lan', 'start', '100'],
        ],
        'firewall': [
          ['set', 'cfg02', 'enabled', '0'],
        ],
      };

      final outcome = await h.service.apply(
        _session,
        ours: const {'dhcp'},
        writtenKeys: const {'dhcp|set|lan|start'},
      );

      expect(outcome.phase, ApplyPhase.failed);
      expect(outcome.reason, RollbackReason.foreignChanges);
      expect(outcome.foreign.configs, {'firewall'});
      expect(
        h.api.calls.where((c) => c.startsWith('apply')),
        isEmpty,
        reason: 'nothing may reach the router once a stray edit is seen',
      );
    });

    // Refusing must not leave our own rows behind as well, or the next
    // apply finds them in its baseline and refuses for them too.
    test('a refusal backs our own staging out and names the rest', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['set', 'lan', 'start', '100'],
        ],
        'firewall': [
          ['set', 'cfg02', 'enabled', '0'],
        ],
      };

      final outcome = await h.service.apply(
        _session,
        ours: const {'dhcp'},
        baseline: const UciChangeSet(
          byConfig: {
            'firewall': [
              UciChange(
                op: UciOp.set,
                config: 'firewall',
                section: 'cfg02',
                option: 'enabled',
              ),
            ],
          },
          fetchedAt: null,
        ),
        writtenKeys: const {'dhcp|set|lan|start'},
      );

      expect(outcome.reason, RollbackReason.foreignChanges);
      expect(h.api.calls, contains('revert dhcp'));
      expect(h.api.calls, isNot(contains('revert firewall')));
      expect(outcome.stillStaged, isEmpty);
    });

    test('apply proceeds when every pending change is ours', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['set', 'lan', 'start', '100'],
        ],
      };

      final outcome = await h.service.apply(
        _session,
        ours: const {'dhcp'},
        writtenKeys: const {'dhcp|set|lan|start'},
        mode: ApplyMode.unchecked,
      );

      expect(outcome.phase, ApplyPhase.confirmed);
    });

    // With no baseline there is no telling a leftover from our own work
    // except by what we wrote. A row we cannot account for is foreign.
    test('without a baseline, only what was written passes', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['set', 'lan', 'start', '100'],
          ['set', 'lan', 'leasetime', '24h'],
        ],
      };

      final outcome = await h.service.apply(
        _session,
        ours: const {'dhcp'},
        writtenKeys: const {'dhcp|set|lan|start'},
      );

      expect(outcome.reason, RollbackReason.foreignChanges);
      expect(outcome.foreign.forConfig('dhcp').single.option, 'leasetime');
    });

    // The hole a config-name-only check leaves: a row already staged in a
    // config this operation also touches is not ours just because the config
    // is. Applying would commit an edit the user had backed out of.
    test('a stale row inside an owned config is still foreign', () async {
      final h = _build();
      const baseline = UciChangeSet(
        byConfig: {
          'dhcp': [
            UciChange(
              op: UciOp.set,
              config: 'dhcp',
              section: 'oldhost',
              option: 'ip',
              value: '192.168.1.9',
            ),
          ],
        },
        fetchedAt: null,
      );
      h.api.changes = {
        'dhcp': [
          // Still there from before, plus the row this operation staged.
          ['set', 'oldhost', 'ip', '192.168.1.9'],
          ['set', 'lan', 'start', '100'],
        ],
      };

      final outcome = await h.service.apply(
        _session,
        ours: const {'dhcp'},
        baseline: baseline,
      );

      expect(outcome.reason, RollbackReason.foreignChanges);
      expect(outcome.foreign.configs, {'dhcp'});
      expect(h.api.calls.where((c) => c.startsWith('apply')), isEmpty);
    });

    test('rows this operation staged are not mistaken for stale', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['set', 'lan', 'start', '100'],
        ],
      };

      final outcome = await h.service.apply(
        _session,
        ours: const {'dhcp'},
        baseline: const UciChangeSet(byConfig: {}, fetchedAt: null),
        mode: ApplyMode.unchecked,
      );

      expect(outcome.phase, ApplyPhase.confirmed);
    });

    // The stock ACL denies `uci.revert`, so a failed apply can leave our own
    // row staged. Retrying the same edit re-stages the same key; the row in
    // the baseline is ours, overwritten, and must not block the retry forever.
    test(
      're-staging an edit left behind by a failed apply is not foreign',
      () async {
        final h = _build();
        h.api.changes = {
          'wireless': [
            ['set', 'wifinet0', 'disabled', '1'],
          ],
        };

        final staged = await h.service.stage(_session, const [
          UciSet('wireless', section: 'wifinet0', values: {'disabled': '1'}),
        ]);
        expect(staged.writtenKeys, {'wireless|set|wifinet0|disabled'});
        expect(staged.ownedSections, isEmpty);

        final outcome = await h.service.apply(
          _session,
          ours: const {'wireless'},
          baseline: staged.baseline,
          writtenKeys: staged.writtenKeys,
          ownedSections: staged.ownedSections,
          mode: ApplyMode.unchecked,
        );

        expect(outcome.phase, ApplyPhase.confirmed);
      },
    );

    test('a leftover row this retry did not touch is still foreign', () async {
      final h = _build();
      h.api.changes = {
        'wireless': [
          ['set', 'wifinet0', 'disabled', '1'],
          ['set', 'wifinet1', 'ssid', 'Old'],
        ],
      };

      final staged = await h.service.stage(_session, const [
        UciSet('wireless', section: 'wifinet0', values: {'disabled': '1'}),
      ]);
      final outcome = await h.service.apply(
        _session,
        ours: const {'wireless'},
        baseline: staged.baseline,
        writtenKeys: staged.writtenKeys,
        ownedSections: staged.ownedSections,
      );

      expect(outcome.reason, RollbackReason.foreignChanges);
      expect(outcome.foreign.forConfig('wireless').single.section, 'wifinet1');
    });

    test('every operation kind reports the section it wrote', () async {
      final h = _build();
      h.api.addedSection = 'cfg0f00';

      final staged = await h.service.stage(_session, const [
        UciAdd('firewall', type: 'rule', values: {'name': 'x', 'src': 'lan'}),
        UciAdd('firewall', type: 'rule', name: 'named', values: {'src': 'lan'}),
        UciSetList(
          'dhcp',
          section: 'lan',
          option: 'dhcp_option',
          values: ['a'],
        ),
        UciRemove('dhcp', section: 'host1', option: 'ip'),
        UciRemove('dhcp', section: 'host2'),
      ]);

      expect(staged.ownedSections, {'firewall|cfg0f00', 'firewall|named'});
      expect(staged.writtenKeys, {
        'dhcp|remove|lan|dhcp_option',
        'dhcp|listAdd|lan|dhcp_option',
        'dhcp|remove|host1|ip',
        'dhcp|remove|host2|',
      });
    });

    // Ownership is per row on a committed section: editing `dhcp.lan.start`
    // must not quietly commit a stale `dhcp.lan.leasetime` from an earlier,
    // unrelated failure.
    test('a leftover option on a committed section stays foreign', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['set', 'lan', 'leasetime', '24h'],
          ['set', 'lan', 'start', '100'],
        ],
      };

      final staged = await h.service.stage(_session, const [
        UciSet('dhcp', section: 'lan', values: {'start': '100'}),
      ]);
      final outcome = await h.service.apply(
        _session,
        ours: const {'dhcp'},
        baseline: staged.baseline,
        writtenKeys: staged.writtenKeys,
        ownedSections: staged.ownedSections,
      );

      expect(outcome.reason, RollbackReason.foreignChanges);
      expect(outcome.foreign.forConfig('dhcp').single.option, 'leasetime');
    });

    // A corrected retry: the planner still adds, because the values differ.
    // The leftover is this session's own failed attempt, and `uci.delete` of
    // an uncommitted section is granted where `uci.revert` is not.
    test('a corrected anonymous add deletes the leftover first', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['add', 'cfg0a', 'host'],
          ['set', 'cfg0a', 'mac', 'AA:BB:CC:11:22:33'],
          ['set', 'cfg0a', 'ip', '192.168.1.50'],
        ],
      };

      final staged = await h.service.stage(_session, const [
        UciAdd(
          'dhcp',
          type: 'host',
          identity: ['mac'],
          values: {'mac': 'AA:BB:CC:11:22:33', 'ip': '192.168.1.51'},
        ),
      ]);

      expect(h.api.calls, contains('delete dhcp.cfg0a'));
      expect(
        h.api.calls.indexOf('delete dhcp.cfg0a'),
        lessThan(h.api.calls.indexOf('add dhcp host')),
      );
      expect(staged.ownedSections, {'dhcp|cfg0a1b2c', 'dhcp|cfg0a'});

      // libuci keeps the swept section's rows in the delta next to the
      // removal (the mock leaves `changes` as it was), and they are ours.
      final outcome = await h.service.apply(
        _session,
        ours: const {'dhcp'},
        baseline: staged.baseline,
        writtenKeys: staged.writtenKeys,
        ownedSections: staged.ownedSections,
        mode: ApplyMode.unchecked,
      );
      expect(outcome.phase, ApplyPhase.confirmed);
    });

    // Once the router shows the staged section, the planner edits it rather
    // than adding it again, so the retry writes a `set` and never repeats the
    // leftover `add` row. Ownership has to be per section for that to pass.
    test(
      'editing a section left staged by a failed add owns its rows',
      () async {
        final h = _build();
        h.api.changes = {
          'dhcp': [
            ['add', 'cfg0a', 'host'],
            ['set', 'cfg0a', 'mac', 'AA:BB:CC:11:22:33'],
            ['set', 'cfg0a', 'ip', '192.168.1.50'],
          ],
        };

        final staged = await h.service.stage(_session, const [
          UciSet('dhcp', section: 'cfg0a', values: {'ip': '192.168.1.60'}),
        ]);
        final outcome = await h.service.apply(
          _session,
          ours: const {'dhcp'},
          baseline: staged.baseline,
          writtenKeys: staged.writtenKeys,
          ownedSections: staged.ownedSections,
          mode: ApplyMode.unchecked,
        );

        expect(outcome.phase, ApplyPhase.confirmed);
      },
    );

    test(
      'an adopted section is still reported when a later op fails',
      () async {
        final h = _build();
        h.api.changes = {
          'dhcp': [
            ['add', 'cfg0a', 'host'],
            ['set', 'cfg0a', 'mac', 'AA:BB:CC:11:22:33'],
          ],
        };
        h.api.setError = const RpcException(
          object: 'uci',
          method: 'set',
          status: 6,
        );

        await expectLater(
          h.service.stage(_session, const [
            UciAdd(
              'dhcp',
              type: 'host',
              identity: ['mac'],
              values: {'mac': 'AA:BB:CC:11:22:33'},
            ),
            UciSet('firewall', section: 'cfg02', values: {'enabled': '0'}),
          ]),
          throwsA(
            isA<UciStagingException>().having(
              (e) => e.stillStaged,
              'stillStaged',
              {'dhcp'},
            ),
          ),
        );
      },
    );

    // `network.lan.ipaddr` and `dhcp.lan.ipaddr` are different rows; a key
    // without the config would let the one we wrote vouch for the other.
    test(
      'a leftover in another config with the same section is foreign',
      () async {
        final h = _build();
        h.api.changes = {
          'network': [
            ['set', 'lan', 'ipaddr', '192.168.1.1'],
          ],
          'dhcp': [
            ['set', 'lan', 'ipaddr', 'stale'],
          ],
        };

        final staged = await h.service.stage(_session, const [
          UciSet('network', section: 'lan', values: {'ipaddr': '192.168.1.1'}),
        ]);
        final outcome = await h.service.apply(
          _session,
          ours: const {'network', 'dhcp'},
          baseline: staged.baseline,
          writtenKeys: staged.writtenKeys,
          ownedSections: staged.ownedSections,
        );

        expect(outcome.reason, RollbackReason.foreignChanges);
        expect(outcome.foreign.configs, {'dhcp'});
      },
    );

    // An anonymous add cannot be re-staged onto the same row: the router
    // names the section. Retrying must reuse the leftover, not stack a
    // duplicate on it and then be refused for the leftover.
    test('retrying an anonymous add adopts the identical leftover', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['add', 'cfg0a', 'host'],
          ['set', 'cfg0a', 'mac', 'AA:BB:CC:11:22:33'],
          ['set', 'cfg0a', 'ip', '192.168.1.50'],
        ],
      };

      final staged = await h.service.stage(_session, const [
        UciAdd(
          'dhcp',
          type: 'host',
          identity: ['mac'],
          values: {'mac': 'AA:BB:CC:11:22:33', 'ip': '192.168.1.50'},
        ),
      ]);

      expect(staged.sections, {0: 'cfg0a'});
      expect(h.api.calls.where((c) => c.startsWith('add')), isEmpty);

      final outcome = await h.service.apply(
        _session,
        ours: const {'dhcp'},
        baseline: staged.baseline,
        writtenKeys: staged.writtenKeys,
        ownedSections: staged.ownedSections,
        mode: ApplyMode.unchecked,
      );
      expect(outcome.phase, ApplyPhase.confirmed);
    });

    // libuci keeps a deleted section's rows in the delta and appends the
    // removal; only the last word counts, or a third attempt would adopt a
    // section that no longer exists, or try to delete it again.
    test(
      'an add that was deleted again is neither adopted nor swept',
      () async {
        final h = _build();
        h.api.changes = {
          'dhcp': [
            ['add', 'cfg0a', 'host'],
            ['set', 'cfg0a', 'mac', 'AA:BB:CC:11:22:33'],
            ['set', 'cfg0a', 'ip', '192.168.1.50'],
            ['remove', 'cfg0a'],
            ['add', 'cfg0b', 'host'],
            ['set', 'cfg0b', 'mac', 'AA:BB:CC:11:22:33'],
            ['set', 'cfg0b', 'ip', '192.168.1.51'],
          ],
        };

        final staged = await h.service.stage(_session, const [
          UciAdd(
            'dhcp',
            type: 'host',
            identity: ['mac'],
            values: {'mac': 'AA:BB:CC:11:22:33', 'ip': '192.168.1.50'},
          ),
        ]);

        expect(h.api.calls, isNot(contains('delete dhcp.cfg0a')));
        expect(h.api.calls, contains('delete dhcp.cfg0b'));
        expect(staged.sections, {0: 'cfg0a1b2c'});
      },
    );

    // A leftover that shares no value with the new add is somebody's other
    // edit: it stays, and the apply names it rather than destroying it.
    test('an unrelated leftover add is not swept', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['add', 'cfg0a', 'host'],
          ['set', 'cfg0a', 'mac', 'AA:BB:CC:11:22:33'],
          ['set', 'cfg0a', 'ip', '192.168.1.50'],
        ],
      };

      final staged = await h.service.stage(_session, const [
        UciAdd(
          'dhcp',
          type: 'host',
          identity: ['mac'],
          values: {'mac': 'DD:EE:FF:11:22:33', 'ip': '192.168.1.60'},
        ),
      ]);
      expect(h.api.calls.where((c) => c.startsWith('delete')), isEmpty);

      final outcome = await h.service.apply(
        _session,
        ours: const {'dhcp'},
        baseline: staged.baseline,
        writtenKeys: staged.writtenKeys,
        ownedSections: staged.ownedSections,
      );
      expect(outcome.reason, RollbackReason.foreignChanges);
    });

    // Options such as `mode ap` or `device radio0` are the same on every
    // section of the type; only the identifying option says whether two
    // adds are about the same thing.
    test('a leftover about something else is not swept', () async {
      final h = _build();
      h.api.changes = {
        'wireless': [
          ['add', 'cfg0a', 'wifi-iface'],
          ['set', 'cfg0a', 'device', 'radio0'],
          ['set', 'cfg0a', 'mode', 'ap'],
          ['set', 'cfg0a', 'ssid', 'Guest'],
          ['set', 'cfg0a', 'key', 'first-try'],
        ],
      };

      await h.service.stage(_session, const [
        UciAdd(
          'wireless',
          type: 'wifi-iface',
          identity: ['ssid', 'device'],
          values: {'device': 'radio0', 'mode': 'ap', 'ssid': 'IoT'},
        ),
      ]);
      expect(h.api.calls.where((c) => c.startsWith('delete')), isEmpty);

      // The same SSID on another radio is another network, not a retry.
      await h.service.stage(_session, const [
        UciAdd(
          'wireless',
          type: 'wifi-iface',
          identity: ['ssid', 'device'],
          values: {'device': 'radio1', 'mode': 'ap', 'ssid': 'Guest'},
        ),
      ]);
      expect(h.api.calls.where((c) => c.startsWith('delete')), isEmpty);

      // The same SSID with a corrected key is the same edit, retried.
      await h.service.stage(_session, const [
        UciAdd(
          'wireless',
          type: 'wifi-iface',
          identity: ['ssid', 'device'],
          values: {
            'device': 'radio0',
            'mode': 'ap',
            'ssid': 'Guest',
            'key': 'second-try',
          },
        ),
      ]);
      expect(h.api.calls, contains('delete wireless.cfg0a'));
    });

    test('a sweep that fails part-way still owns what it deleted', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['add', 'cfg0a', 'host'],
          ['set', 'cfg0a', 'mac', 'AA:BB:CC:11:22:33'],
          ['add', 'cfg0b', 'host'],
          ['set', 'cfg0b', 'mac', 'AA:BB:CC:11:22:33'],
        ],
      };
      h.api.deleteErrorsFor = const {'cfg0b'};

      final staged = await h.service.stage(_session, const [
        UciAdd(
          'dhcp',
          type: 'host',
          identity: ['mac'],
          values: {'mac': 'AA:BB:CC:11:22:33', 'ip': '192.168.1.9'},
        ),
      ]);

      expect(staged.ownedSections, contains('dhcp|cfg0a'));
      expect(staged.ownedSections, isNot(contains('dhcp|cfg0b')));
    });

    // A section this batch already deleted is not there to adopt, whatever
    // the (stale) baseline still says about it.
    test('a section swept earlier in the batch is not adopted', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['add', 'cfg0a', 'host'],
          ['set', 'cfg0a', 'mac', 'AA:BB:CC:11:22:33'],
          ['set', 'cfg0a', 'ip', '192.168.1.10'],
        ],
      };

      final staged = await h.service.stage(_session, const [
        UciAdd(
          'dhcp',
          type: 'host',
          identity: ['mac'],
          values: {'mac': 'AA:BB:CC:11:22:33', 'ip': '192.168.1.20'},
        ),
        UciAdd(
          'dhcp',
          type: 'host',
          identity: ['mac'],
          values: {'mac': 'AA:BB:CC:11:22:33', 'ip': '192.168.1.10'},
        ),
      ]);

      expect(h.api.calls, contains('delete dhcp.cfg0a'));
      expect(staged.sections.values, isNot(contains('cfg0a')));
      expect(h.api.calls.where((c) => c == 'add dhcp host'), hasLength(2));
    });

    test('a section adopted earlier in the batch is never swept', () async {
      final h = _build();
      h.api.changes = {
        'firewall': [
          ['add', 'cfg0a', 'rule'],
          ['set', 'cfg0a', 'name', 'block-a'],
        ],
      };

      await h.service.stage(_session, const [
        UciAdd('firewall', type: 'rule', values: {'name': 'block-a'}),
        UciAdd('firewall', type: 'rule', values: {'name': 'block-a'}),
      ]);

      expect(h.api.calls.where((c) => c.startsWith('delete')), isEmpty);
    });

    // A wifi-iface's `network` is a list, staged as one `list-add` row per
    // entry. Identical is identical; the retry adopts it instead of
    // deleting and re-adding.
    test('an identical add carrying a list is adopted', () async {
      final h = _build();
      h.api.changes = {
        'wireless': [
          ['add', 'cfg0a', 'wifi-iface'],
          ['set', 'cfg0a', 'device', 'radio0'],
          ['set', 'cfg0a', 'ssid', 'Guest'],
          ['list-add', 'cfg0a', 'network', 'lan'],
          ['list-add', 'cfg0a', 'network', 'guest'],
        ],
      };

      final staged = await h.service.stage(_session, const [
        UciAdd(
          'wireless',
          type: 'wifi-iface',
          identity: ['ssid', 'device'],
          values: {
            'device': 'radio0',
            'ssid': 'Guest',
            'network': ['lan', 'guest'],
          },
        ),
      ]);

      expect(staged.sections, {0: 'cfg0a'});
      expect(h.api.calls.where((c) => c.startsWith('delete')), isEmpty);
      expect(h.api.calls.where((c) => c.startsWith('add')), isEmpty);
    });

    test('a leftover add with different values is not adopted', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['add', 'cfg0a', 'host'],
          ['set', 'cfg0a', 'mac', 'AA:BB:CC:11:22:33'],
          ['set', 'cfg0a', 'ip', '192.168.1.50'],
        ],
      };

      final staged = await h.service.stage(_session, const [
        UciAdd(
          'dhcp',
          type: 'host',
          identity: ['mac'],
          values: {'mac': 'AA:BB:CC:11:22:33', 'ip': '192.168.1.60'},
        ),
      ]);

      expect(staged.sections, {0: 'cfg0a1b2c'});
      expect(h.api.calls, contains('add dhcp host'));
    });

    // Callers that do not say what they staged keep the old behaviour, so
    // the guard cannot silently change an unrelated call site.
    test('no ownership set means no ownership check', () async {
      final h = _build();
      h.api.changes = {
        'firewall': [
          ['set', 'cfg02', 'enabled', '0'],
        ],
      };

      final outcome = await h.service.apply(
        _session,
        mode: ApplyMode.unchecked,
      );

      expect(outcome.phase, ApplyPhase.confirmed);
    });

    // `uci.revert` is config-wide. Cleaning up our own failed batch must not
    // discard an edit that was already staged in the same config.
    test('staging cleanup spares a config that was already dirty', () async {
      final h = _build();
      h.api.changes = {
        'firewall': [
          ['set', 'cfg02', 'enabled', '0'],
        ],
      };
      h.api.setError = Exception('nope');

      await expectLater(
        h.service.stage(_session, const [
          UciSet('firewall', section: 'cfg03', values: {'target': 'REJECT'}),
        ]),
        throwsA(isA<UciStagingException>()),
      );

      expect(
        h.api.calls.where((c) => c.startsWith('revert')),
        isEmpty,
        reason: 'firewall already held changes we did not stage',
      );
    });

    // A failure that could not clean up after itself leaves work on the
    // router; "failed" alone hides that there is something to undo.
    test('a spared config is reported as still staged', () async {
      final h = _build();
      h.api.changes = {
        'firewall': [
          ['set', 'cfg02', 'enabled', '0'],
        ],
      };
      h.api.setError = Exception('nope');

      try {
        await h.service.stage(_session, const [
          UciSet('firewall', section: 'cfg03', values: {'target': 'REJECT'}),
        ]);
        fail('staging should have thrown');
      } on UciStagingException catch (e) {
        expect(e.stillStaged, {'firewall'});
        expect(e.revertedConfigs, isEmpty);
      }
    });

    test('a failed revert reports everything it touched', () async {
      final h = _build();
      h.api.changes = const {};
      h.api.setError = Exception('nope');
      h.api.revertError = Exception('revert denied');

      try {
        await h.service.stage(_session, const [
          UciSet('dhcp', section: 'lan', values: {'start': '100'}),
        ]);
        fail('staging should have thrown');
      } on UciStagingException catch (e) {
        expect(e.revertFailed, isTrue);
        expect(e.stillStaged, {'dhcp'});
      }
    });

    test('staging cleanup still reverts a config only we touched', () async {
      final h = _build();
      h.api.changes = const {};
      h.api.setError = Exception('nope');

      await expectLater(
        h.service.stage(_session, const [
          UciSet('dhcp', section: 'lan', values: {'start': '100'}),
        ]),
        throwsA(isA<UciStagingException>()),
      );

      expect(h.api.calls, contains('revert dhcp'));
    });
  });

  group('rollback the router will not perform', () {
    // Counting down to a rollback that cannot happen promises a safety net
    // that is not there.
    test('unchecked mode asks for no rollback and no countdown', () async {
      final h = _build();
      final phases = <({ApplyPhase phase, Duration remaining})>[];

      await h.service.apply(
        _session,
        mode: ApplyMode.unchecked,
        onPhase: (p, r) => phases.add((phase: p, remaining: r)),
      );

      expect(h.api.calls, contains('apply rollback=false timeout=0'));
      expect(
        phases.every((p) => p.remaining == Duration.zero),
        isTrue,
        reason: 'no countdown may be shown when nothing will roll back',
      );
      expect(h.api.confirmCount, 0);
    });

    // Rollback requested without a measured grant: the router may well have
    // kept the change. The outcome says so, so the message can too.
    // Rollback was asked for, so it may well happen: the countdown is
    // shown. What is not claimed afterwards is that it did happen.
    test('an unverified rollback is still counted down', () async {
      final h = _build(reachable: false);
      final phases = <(ApplyPhase, Duration)>[];

      await h.service.apply(
        _session,
        rollbackVerified: false,
        onPhase: (p, r) => phases.add((p, r)),
      );

      final awaiting = phases.where((p) => p.$1 == ApplyPhase.awaitingConfirm);
      expect(awaiting, isNotEmpty);
      expect(awaiting.first.$2, greaterThan(Duration.zero));
    });

    test('an unverified rollback is reported as such', () async {
      final h = _build(reachable: false);

      final outcome = await h.service.apply(_session, rollbackVerified: false);

      expect(outcome.phase, ApplyPhase.rolledBack);
      expect(outcome.rollbackVerified, isFalse);
      expect((await _build().service.apply(_session)).rollbackVerified, isTrue);
    });
  });
}

void _applyFailureCleanupReporting() {
  // `uci.revert` is not granted by the stock ACL, so cleanup after a rejected
  // apply can be refused. Whatever it could not clear is still on the router
  // and the message has to be able to name it.
  group('cleanup after a rejected apply', () {
    test('names the configs it could not revert', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['set', 'lan', 'start', '100'],
        ],
        'firewall': [
          ['set', 'cfg03', 'target', 'REJECT'],
        ],
      };
      h.api.applyError = Exception('rejected');
      h.api.revertError = Exception('revert denied');

      final outcome = await h.service.apply(_session);

      expect(outcome.phase, ApplyPhase.failed);
      expect(outcome.reason, RollbackReason.routerRejected);
      expect(outcome.stillStaged, {'dhcp', 'firewall'});
    });

    test('a successful cleanup reports nothing left staged', () async {
      final h = _build();
      h.api.changes = {
        'dhcp': [
          ['set', 'lan', 'start', '100'],
        ],
      };
      h.api.applyError = Exception('rejected');

      final outcome = await h.service.apply(_session);

      expect(outcome.phase, ApplyPhase.failed);
      expect(outcome.stillStaged, isEmpty);
      expect(h.api.calls, contains('revert dhcp'));
    });
  });
}
