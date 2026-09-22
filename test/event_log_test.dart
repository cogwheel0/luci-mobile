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
  int? bootTime,
}) => RouterObservation(
  reachable: reachable,
  wanUp: wanUp,
  clientMacs: clients,
  bootTime: bootTime,
);

/// A `system.info` payload for a router booted at [bootTime] whose clock now
/// reads [localtime], both in epoch seconds.
Map<String, dynamic> sysInfo({required int bootTime, required int localtime}) =>
    {'uptime': localtime - bootTime, 'localtime': localtime};

/// Epoch seconds of a moment well after the router's clock is set.
final _epoch = DateTime.utc(2026, 9, 20, 12).millisecondsSinceEpoch ~/ 1000;

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

    // The router has no event stream. Its boot time, by its own clock,
    // moving forward is the only evidence of a reboot there is - and it
    // holds however stale the payload, whatever the phone's clock does, and
    // however many reboots in a row.
    test('a boot time that moved forward is a reboot', () {
      expect(
        diff(obs(bootTime: _epoch), obs(bootTime: _epoch + 600)).single.kind,
        RouterEventKind.rebooted,
      );
      // A running router keeps its boot time, give or take rounding.
      expect(diff(obs(bootTime: _epoch), obs(bootTime: _epoch + 5)), isEmpty);
      // The router's clock being adjusted backwards is not a reboot.
      expect(diff(obs(bootTime: _epoch), obs(bootTime: _epoch - 900)), isEmpty);
      // Unknown on either side is not evidence of anything.
      expect(diff(obs(bootTime: _epoch), obs()), isEmpty);
      expect(diff(obs(), obs(bootTime: _epoch)), isEmpty);
    });

    test('two reboots in a row are both seen', () {
      final first = obs(bootTime: _epoch);
      final second = obs(bootTime: _epoch + 600);
      final third = obs(bootTime: _epoch + 900);
      expect(diff(first, second).single.kind, RouterEventKind.rebooted);
      expect(diff(second, third).single.kind, RouterEventKind.rebooted);
    });

    // The foreground feed reads out of a dashboard payload that may be
    // minutes old. The same payload seen twice is the same boot time.
    test('the same dashboard payload seen twice is not a reboot', () {
      final payload = {
        'sysInfo': sysInfo(bootTime: _epoch, localtime: _epoch + 600),
      };
      RouterObservation seen() => EventDeriver.observe(
        reachable: true,
        dashboardData: payload,
        clients: const [],
      );
      expect(seen().bootTime, _epoch);
      expect(diff(seen(), seen()), isEmpty);
    });

    // OpenWrt boots at its build date until NTP answers; a boot time
    // computed from that would jump forward by years once it does.
    test('a router whose clock is not set yet reports no boot time', () {
      expect(
        EventDeriver.bootTimeOf(sysInfo(bootTime: 1000, localtime: 90000)),
        isNull,
      );
      expect(EventDeriver.bootTimeOf({'uptime': 5}), isNull);
      expect(EventDeriver.bootTimeOf(null), isNull);
    });

    // A reboot is usually seen as an outage. The observation taken while the
    // router was away carries the last boot time it reported, so the
    // comparison still happens when it comes back - alongside "router back".
    test('a reboot seen through an outage is still a reboot', () {
      final away = obs(reachable: false).withBootTime(_epoch);
      expect(
        diff(away, obs(bootTime: _epoch + 600)).map((e) => e.kind),
        containsAll([RouterEventKind.routerBack, RouterEventKind.rebooted]),
      );
      // Going away is not a reboot, whatever the stale payload says.
      expect(
        diff(
          obs(bootTime: _epoch),
          obs(reachable: false, bootTime: _epoch + 600),
        ).single.kind,
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
    test('reads the boot time out of the dashboard payload', () {
      final o = EventDeriver.observe(
        reachable: true,
        dashboardData: {
          'sysInfo': sysInfo(bootTime: _epoch, localtime: _epoch + 1234),
        },
        clients: const [],
      );
      expect(o.bootTime, _epoch);
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
