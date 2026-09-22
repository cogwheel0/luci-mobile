import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/services/background_monitor.dart';
import 'package:luci_mobile/services/background_worker.dart';
import 'package:luci_mobile/services/event_log.dart';

final _at = DateTime.utc(2026, 9, 20, 12);

RouterObservation obs({
  bool reachable = true,
  bool wanUp = true,
  Set<String> clients = const {'AA:BB:CC:11:22:33'},
}) =>
    RouterObservation(reachable: reachable, wanUp: wanUp, clientMacs: clients);

List<RouterEvent> notifiable(
  RouterObservation? prev,
  RouterObservation now, {
  Set<RouterEventKind>? kinds,
}) => BackgroundMonitor.notifiable(
  previous: prev,
  current: now,
  routerId: 'r1',
  at: _at,
  kinds: kinds ?? notifiableKinds,
);

void main() {
  _wanDetection();

  group('deciding what is worth a notification', () {
    // The whole point of the feature.
    test('losing the internet is notified', () {
      final events = notifiable(obs(), obs(wanUp: false));
      expect(events.single.kind, RouterEventKind.wanDown);
    });

    test('a new device joining is notified', () {
      final events = notifiable(obs(clients: const {}), obs());
      expect(events.single.kind, RouterEventKind.clientJoined);
    });

    // The single most important rule here. A background poll that cannot
    // reach the router almost always means the phone left the network, so
    // notifying would fire every time the user walks out the front door.
    test('an unreachable router is never notified', () {
      final events = notifiable(
        obs(),
        obs(reachable: false, clients: const {}),
      );
      expect(events, isEmpty);
    });

    test('routerUnreachable is not in the notifiable set at all', () {
      expect(
        notifiableKinds.contains(RouterEventKind.routerUnreachable),
        isFalse,
      );
    });

    // A device leaving is normal and constant; it belongs in the feed, not
    // on the lock screen.
    test('a device leaving is not notified', () {
      final events = notifiable(obs(), obs(clients: const {}));
      expect(events, isEmpty);
    });

    test('the first poll of a session notifies nothing', () {
      expect(notifiable(null, obs()), isEmpty);
    });

    test('an unchanged router notifies nothing', () {
      expect(notifiable(obs(), obs()), isEmpty);
    });

    test('the user can narrow what is notified', () {
      final events = notifiable(
        obs(clients: const {}),
        obs(wanUp: false),
        kinds: const {RouterEventKind.wanDown},
      );
      expect(events.single.kind, RouterEventKind.wanDown);
    });

    test('turning every kind off notifies nothing', () {
      expect(notifiable(obs(), obs(wanUp: false), kinds: const {}), isEmpty);
    });
  });

  group('capping one poll', () {
    RouterEvent event(RouterEventKind kind, String? subject) =>
        RouterEvent(kind: kind, at: _at, routerId: 'r1', subject: subject);

    test('a few events pass through untouched', () {
      final events = [
        event(RouterEventKind.clientJoined, 'a'),
        event(RouterEventKind.clientJoined, 'b'),
      ];
      expect(BackgroundMonitor.capped(events), hasLength(2));
    });

    // Coming home wakes every device at once; a dozen "joined"
    // notifications is a shade nobody reads again.
    test('a flood is trimmed', () {
      final events = [
        for (var i = 0; i < 12; i++)
          event(RouterEventKind.clientJoined, 'device$i'),
      ];
      expect(
        BackgroundMonitor.capped(events),
        hasLength(BackgroundMonitor.maxPerPoll),
      );
    });

    // If something is dropped it must not be the thing that matters.
    test('problems survive the trim, chatter does not', () {
      final events = [
        for (var i = 0; i < 6; i++)
          event(RouterEventKind.clientJoined, 'device$i'),
        event(RouterEventKind.wanDown, null),
      ];
      final kept = BackgroundMonitor.capped(events);
      expect(kept.map((e) => e.kind), contains(RouterEventKind.wanDown));
    });
  });

  group('the stored baseline', () {
    StoredObservation stored(DateTime at) =>
        StoredObservation(observation: obs(), at: at);

    test('round-trips through JSON', () {
      final back = StoredObservation.fromJson(
        StoredObservation(
          observation: RouterObservation(
            reachable: true,
            wanUp: false,
            clientMacs: {'AA:BB:CC:11:22:33'},
            names: {'AA:BB:CC:11:22:33': 'Laptop'},
            uptime: 4321,
            uptimeAt: _at,
          ),
          at: _at,
        ).toJson(),
      );
      expect(back, isNotNull);
      expect(back!.observation.wanUp, isFalse);
      expect(back.observation.uptime, 4321);
      expect(back.observation.uptimeAt?.isAtSameMomentAs(_at), isTrue);
      expect(back.observation.clientMacs, {'AA:BB:CC:11:22:33'});
      expect(back.observation.names['AA:BB:CC:11:22:33'], 'Laptop');
      expect(back.at.isAtSameMomentAs(_at), isTrue);
    });

    test('a malformed entry is dropped rather than crashing the poll', () {
      expect(StoredObservation.fromJson(const {}), isNull);
      expect(StoredObservation.fromJson(const {'at': 'nonsense'}), isNull);
    });

    // After a long gap the client list has churned for reasons nobody wants
    // notified; a fresh start is quieter and more honest.
    test('an old baseline is stale', () {
      expect(stored(_at).isStale(_at.add(const Duration(hours: 7))), isTrue);
      expect(stored(_at).isStale(_at.add(const Duration(hours: 1))), isFalse);
    });
  });

  group('the monitored router', () {
    test('round-trips through JSON', () {
      const router = MonitoredRouter(
        id: 'r1',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'secret',
        useHttps: true,
      );
      final back = MonitoredRouter.fromJson(router.toJson());
      expect(back, isNotNull);
      expect(back!.ipAddress, '192.168.1.1');
      expect(back.useHttps, isTrue);
      expect(back.password, 'secret');
    });

    test('an entry with no address is dropped', () {
      expect(MonitoredRouter.fromJson(const {'id': 'r1'}), isNull);
    });

    test('a missing username falls back to root', () {
      final back = MonitoredRouter.fromJson(const {
        'id': 'r1',
        'ipAddress': '192.168.1.1',
      });
      expect(back!.username, 'root');
    });
  });

  test('the interval respects the platform floor', () {
    // Asking for less is a promise Android will not keep.
    expect(
      BackgroundMonitor.minimumInterval.inMinutes,
      greaterThanOrEqualTo(15),
    );
  });
}

void _wanDetection() {
  // A background poll that misreads the WAN raises a push notification about
  // an outage that never happened — the exact false alarm this feature is
  // built to avoid.
  group('reading the WAN from an interface dump', () {
    Map<String, dynamic> dump(List<Map<String, Object>> interfaces) => {
      'interface': interfaces,
    };

    test('a down wan6 does not mask an up wan', () {
      final wan = wanStateFrom(
        dump([
          {'interface': 'wan6', 'up': false},
          {'interface': 'wan', 'up': true},
        ]),
      );
      expect(wan['up'], isTrue);
    });

    test('every WAN-like interface down reads as down', () {
      final wan = wanStateFrom(
        dump([
          {'interface': 'wan', 'up': false},
          {'interface': 'wan6', 'up': false},
        ]),
      );
      expect(wan['up'], isFalse);
    });

    test('a LAN-only router reads as down rather than throwing', () {
      expect(
        wanStateFrom(
          dump([
            {'interface': 'lan', 'up': true},
          ]),
        )['up'],
        isFalse,
      );
      expect(wanStateFrom(const {})['up'], isFalse);
      expect(wanStateFrom(null)['up'], isFalse);
    });

    test('wwan counts', () {
      expect(
        wanStateFrom(
          dump([
            {'interface': 'wwan', 'up': true},
          ]),
        )['up'],
        isTrue,
      );
    });
  });
}
