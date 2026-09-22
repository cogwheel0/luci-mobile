import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/services/event_log.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';

class _MemoryStorage implements SecureStorageService {
  final Map<String, String> values = {};

  @override
  Future<String?> readValue(String key) async => values[key];

  @override
  Future<void> writeValue(String key, String value) async =>
      values[key] = value;

  @override
  Future<void> deleteValue(String key) async => values.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _at = DateTime.utc(2026, 9, 20, 12);

RouterObservation obs({
  bool reachable = true,
  bool wanUp = true,
  Set<String> clients = const {'AA:BB:CC:11:22:33'},
  int? uptime,
}) => RouterObservation(
  reachable: reachable,
  wanUp: wanUp,
  clientMacs: clients,
  uptime: uptime,
);

List<RouterEvent> diff(RouterObservation? prev, RouterObservation now) =>
    EventDeriver.diff(previous: prev, current: now, routerId: 'r1', at: _at);

void main() {
  group('deriving events', () {
    // With nothing to compare against, every client would look like it had
    // just joined - a wall of noise the moment the app opens.
    test('the first observation yields nothing', () {
      expect(diff(null, obs()), isEmpty);
    });

    test('an unchanged router yields nothing', () {
      expect(diff(obs(), obs()), isEmpty);
    });

    test('losing and regaining the router is reported', () {
      expect(
        diff(obs(), obs(reachable: false)).single.kind,
        RouterEventKind.routerUnreachable,
      );
      expect(
        diff(obs(reachable: false), obs()).single.kind,
        RouterEventKind.routerBack,
      );
    });

    test('WAN transitions are reported', () {
      expect(
        diff(obs(), obs(wanUp: false)).single.kind,
        RouterEventKind.wanDown,
      );
      expect(diff(obs(wanUp: false), obs()).single.kind, RouterEventKind.wanUp);
    });

    // The router has no event stream; uptime going backwards is the only
    // evidence of a reboot there is.
    test('uptime going backwards is a reboot', () {
      expect(
        diff(obs(uptime: 90000), obs(uptime: 120)).single.kind,
        RouterEventKind.rebooted,
      );
      expect(diff(obs(uptime: 100), obs(uptime: 200)), isEmpty);
      // Unknown on either side is not evidence of anything.
      expect(diff(obs(uptime: 100), obs()), isEmpty);
      expect(diff(obs(), obs(uptime: 5)), isEmpty);
    });

    // A reboot is usually seen as an outage. The observation taken while the
    // router was away carries the last uptime it reported, so the comparison
    // still happens when it comes back - alongside "router back".
    // Raw numbers are not enough: after two reboots in a row the second
    // uptime can exceed the first. What the router should have gained is
    // the time that passed.
    test('a reboot is judged against the time that passed', () {
      RouterObservation at(int uptime, DateTime? when) => RouterObservation(
        reachable: true,
        wanUp: true,
        clientMacs: const {},
        uptime: uptime,
        uptimeAt: when,
      );
      final earlier = _at.subtract(const Duration(minutes: 15));
      // 600s read 15 minutes ago; now 900s. Should be ~1500s: rebooted.
      expect(
        EventDeriver.rebootedBetween(at(600, earlier), at(900, _at)),
        isTrue,
      );
      // 600s then 1495s: within the slack, just a running router.
      expect(
        EventDeriver.rebootedBetween(at(600, earlier), at(1495, _at)),
        isFalse,
      );
      // Without a time on either reading, only going backwards counts.
      expect(
        EventDeriver.rebootedBetween(at(600, null), at(900, _at)),
        isFalse,
      );
      expect(EventDeriver.rebootedBetween(at(600, null), at(30, _at)), isTrue);
    });

    // The foreground feed reads uptime out of a dashboard payload that may
    // be minutes old. Two polls of the same payload are one reading, not a
    // router that stopped gaining uptime.
    test('the same dashboard payload seen twice is not a reboot', () {
      final fetched = _at.subtract(const Duration(minutes: 5));
      final payload = {
        'fetchedAt': fetched,
        'sysInfo': {'uptime': 600},
      };
      RouterObservation seen() => EventDeriver.observe(
        reachable: true,
        dashboardData: payload,
        clients: const [],
      );
      expect(seen().uptimeAt, fetched);
      expect(EventDeriver.rebootedBetween(seen(), seen()), isFalse);
      expect(diff(seen(), seen()), isEmpty);
    });

    test('a reboot seen through an outage is still a reboot', () {
      final away = obs(reachable: false).withUptime(90000, null);
      expect(
        diff(away, obs(uptime: 30)).map((e) => e.kind),
        containsAll([RouterEventKind.routerBack, RouterEventKind.rebooted]),
      );
      // Going away is not a reboot, whatever the stale payload says.
      expect(
        diff(obs(uptime: 90000), obs(reachable: false, uptime: 10)).single.kind,
        RouterEventKind.routerUnreachable,
      );
    });

    test('clients joining and leaving are reported with their MAC', () {
      final joined = diff(
        obs(clients: const {}),
        obs(clients: const {'AA:BB:CC:11:22:33'}),
      );
      expect(joined.single.kind, RouterEventKind.clientJoined);
      expect(joined.single.subject, 'AA:BB:CC:11:22:33');

      final left = diff(
        obs(clients: const {'AA:BB:CC:11:22:33'}),
        obs(clients: const {}),
      );
      expect(left.single.kind, RouterEventKind.clientLeft);
    });

    // An unreachable router tells us nothing about its clients; announcing
    // that they all left would be actively misleading.
    test('an unreachable router does not imply its clients left', () {
      final events = diff(
        obs(clients: const {'AA:BB:CC:11:22:33', 'DD:EE:FF:00:11:22'}),
        obs(reachable: false, clients: const {}),
      );
      expect(events, hasLength(1));
      expect(events.single.kind, RouterEventKind.routerUnreachable);
    });

    test('coming back does not replay every client as newly joined', () {
      final events = diff(
        obs(reachable: false, clients: const {}),
        obs(clients: const {'AA:BB:CC:11:22:33'}),
      );
      expect(events, hasLength(1));
      expect(events.single.kind, RouterEventKind.routerBack);
    });

    // A feed that says "AA:BB:CC:11:22:33 joined" makes the reader do the
    // lookup the app already did.
    test('a joining client is named when the name is known', () {
      final events = EventDeriver.diff(
        previous: const RouterObservation(
          reachable: true,
          wanUp: true,
          clientMacs: {},
        ),
        current: const RouterObservation(
          reachable: true,
          wanUp: true,
          clientMacs: {'AA:BB:CC:11:22:33'},
          names: {'AA:BB:CC:11:22:33': 'Laptop'},
        ),
        routerId: 'r1',
        at: _at,
      );
      expect(events.single.subject, 'Laptop');
    });

    test('a departing client keeps the name it had', () {
      final events = EventDeriver.diff(
        previous: const RouterObservation(
          reachable: true,
          wanUp: true,
          clientMacs: {'AA:BB:CC:11:22:33'},
          names: {'AA:BB:CC:11:22:33': 'Laptop'},
        ),
        current: const RouterObservation(
          reachable: true,
          wanUp: true,
          clientMacs: {},
        ),
        routerId: 'r1',
        at: _at,
      );
      expect(events.single.subject, 'Laptop');
    });

    test('an unnamed client falls back to its MAC', () {
      final events = diff(obs(clients: const {}), obs());
      expect(events.single.subject, 'AA:BB:CC:11:22:33');
    });

    test('severity separates problems from noise', () {
      expect(
        diff(obs(), obs(wanUp: false)).single.severity,
        EventSeverity.problem,
      );
      expect(
        diff(obs(clients: const {}), obs()).single.severity,
        EventSeverity.info,
      );
    });
  });

  group('observing', () {
    test('reads the uptime the dashboard already fetched', () {
      final o = EventDeriver.observe(
        reachable: true,
        dashboardData: {
          'sysInfo': {'uptime': 1234},
        },
        clients: const [],
        uptimeAt: _at,
      );
      expect(o.uptime, 1234);
      expect(o.uptimeAt, _at);
    });

    test('reads WAN state and client MACs from the dashboard payload', () {
      final o = EventDeriver.observe(
        reachable: true,
        dashboardData: const {
          'wan': {'up': true},
        },
        clients: [
          Client(
            ipAddress: '192.168.1.5',
            macAddress: 'aa:bb:cc:11:22:33',
            hostname: 'Laptop',
          ),
          // A wireless-only client with no lease has no address; it still
          // counts as present.
          Client(ipAddress: 'N/A', macAddress: 'N/A', hostname: 'Unknown'),
        ],
      );
      expect(o.reachable, isTrue);
      expect(o.wanUp, isTrue);
      expect(o.clientMacs, {'AA:BB:CC:11:22:33'});
      expect(o.names['AA:BB:CC:11:22:33'], 'Laptop');
      // "Unknown" is a placeholder, not a name.
      expect(o.names.values, isNot(contains('Unknown')));
    });

    test('a missing wan block reads as down rather than throwing', () {
      final o = EventDeriver.observe(
        reachable: true,
        dashboardData: const {},
        clients: const [],
      );
      expect(o.wanUp, isFalse);
    });
  });

  group('persisting', () {
    RouterEvent event(RouterEventKind kind, int minute) => RouterEvent(
      kind: kind,
      at: _at.add(Duration(minutes: minute)),
      routerId: 'r1',
    );

    // Two isolates append: the app and the background poll. A shared key
    // would lose whichever read-modify-write landed first.
    test('the app and the background poll never write the same key', () async {
      final storage = _MemoryStorage();
      final log = EventLog(storage);

      await log.append('r1', [event(RouterEventKind.wanDown, 1)]);
      await log.append('r1', [
        event(RouterEventKind.wanUp, 2),
      ], fromBackground: true);

      expect(storage.values.keys, {
        EventLog.storageKey('r1'),
        EventLog.backgroundKey('r1'),
      });
      expect((await log.load('r1')).map((e) => e.kind), [
        RouterEventKind.wanDown,
        RouterEventKind.wanUp,
      ]);
    });

    test('a background event already in the app copy is not doubled', () async {
      final storage = _MemoryStorage();
      final log = EventLog(storage);
      final e = event(RouterEventKind.wanDown, 1);

      await log.append('r1', [e], fromBackground: true);
      final merged = await log.append('r1', [e]);

      expect(merged, hasLength(1));
      expect(await log.load('r1'), hasLength(1));
    });

    test('clearing empties both copies', () async {
      final storage = _MemoryStorage();
      final log = EventLog(storage);
      await log.append('r1', [event(RouterEventKind.wanDown, 1)]);
      await log.append('r1', [
        event(RouterEventKind.wanUp, 2),
      ], fromBackground: true);

      await log.clear('r1');

      expect(storage.values, isEmpty);
      expect(await log.load('r1'), isEmpty);
    });
  });

  group('serialisation', () {
    test('round-trips through JSON', () {
      final event = RouterEvent(
        kind: RouterEventKind.clientJoined,
        at: _at,
        routerId: 'r1',
        subject: 'AA:BB:CC:11:22:33',
      );
      final back = RouterEvent.fromJson(event.toJson());
      expect(back, isNotNull);
      expect(back!.kind, event.kind);
      // Restored as local time: the same moment, not the same flag.
      expect(back.at.isAtSameMomentAs(event.at), isTrue);
      expect(back.subject, event.subject);
    });

    test('a malformed entry is dropped rather than crashing the feed', () {
      expect(RouterEvent.fromJson(const {'kind': 'nope'}), isNull);
      expect(RouterEvent.fromJson(const {'at': 1, 'routerId': 'r'}), isNull);
    });

    // The same poll repeating must not append the event twice.
    test('the dedupe key is stable within a second', () {
      final a = RouterEvent(
        kind: RouterEventKind.wanDown,
        at: _at,
        routerId: 'r1',
      );
      final b = RouterEvent(
        kind: RouterEventKind.wanDown,
        at: _at.add(const Duration(milliseconds: 400)),
        routerId: 'r1',
      );
      expect(a.dedupeKey, b.dedupeKey);
    });
  });
}
