import 'package:flutter/foundation.dart';

import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/services/event_log.dart';

/// Which events are worth waking someone for.
///
/// `routerUnreachable` is deliberately absent and must stay that way. A
/// background poll that cannot reach the router almost always means the
/// phone left the network, not that the router died — so notifying on it
/// would fire every time the user walks out of the front door, and a false
/// "your router is down" at 3am is the worst thing this feature could do.
/// It stays visible in the in-app feed, where it has context.
const Set<RouterEventKind> notifiableKinds = {
  RouterEventKind.wanDown,
  RouterEventKind.wanUp,
  RouterEventKind.rebooted,
  RouterEventKind.clientJoined,
};

/// Decides what a background poll should notify about.
///
/// Pure, so every rule here is testable without a router, a scheduler or a
/// notification channel — none of which exist in a unit test.
class BackgroundMonitor {
  const BackgroundMonitor._();

  /// The default poll interval.
  ///
  /// Android's WorkManager will not run periodic work more often than every
  /// 15 minutes, so asking for less is a promise the platform will not keep.
  static const Duration minimumInterval = Duration(minutes: 15);

  static const String taskName = 'luci-mobile-router-poll';

  /// The events from this poll that should be notified.
  static List<RouterEvent> notifiable({
    required RouterObservation? previous,
    required RouterObservation current,
    required String routerId,
    required DateTime at,
    Set<RouterEventKind> kinds = notifiableKinds,
  }) {
    // An unreachable router tells us nothing trustworthy, and the first
    // poll of a session has nothing to compare against.
    if (!current.reachable || previous == null) return const [];

    return [
      for (final event in EventDeriver.diff(
        previous: previous,
        current: current,
        routerId: routerId,
        at: at,
      ))
        if (kinds.contains(event.kind)) event,
    ];
  }

  /// Caps how many notifications one poll may post.
  ///
  /// Coming home wakes every device at once; twelve separate "joined"
  /// notifications is a notification shade nobody reads again.
  static const int maxPerPoll = 3;

  static List<RouterEvent> capped(List<RouterEvent> events) {
    if (events.length <= maxPerPoll) return events;
    // Most severe first: if something is being dropped it must not be the
    // thing that actually matters. `EventSeverity` runs info -> problem, so
    // this sorts descending.
    final sorted = [...events]
      ..sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return sorted.take(maxPerPoll).toList();
  }
}

/// What the background isolate needs to reach a router, flattened so it can
/// cross an isolate boundary and live in secure storage.
@immutable
class MonitoredRouter {
  const MonitoredRouter({
    required this.id,
    required this.ipAddress,
    required this.username,
    required this.password,
    required this.useHttps,
  });

  final String id;
  final String ipAddress;
  final String username;
  final String password;
  final bool useHttps;

  Map<String, dynamic> toJson() => {
    'id': id,
    'ipAddress': ipAddress,
    'username': username,
    'password': password,
    'useHttps': useHttps,
  };

  static MonitoredRouter? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final ip = json['ipAddress'];
    if (id is! String || ip is! String) return null;
    return MonitoredRouter(
      id: id,
      ipAddress: ip,
      username: json['username'] as String? ?? 'root',
      password: json['password'] as String? ?? '',
      useHttps: json['useHttps'] == true,
    );
  }
}

/// The observation a background poll persists so the next one can diff
/// against it.
///
/// The foreground feed keeps its baseline in memory, which a background
/// isolate does not share — without this every poll would be a first poll
/// and would report nothing, forever.
@immutable
class StoredObservation {
  const StoredObservation({required this.observation, required this.at});

  final RouterObservation observation;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'reachable': observation.reachable,
    'wanUp': observation.wanUp,
    'clients': observation.clientMacs.toList(),
    'names': observation.names,
    'uptime': ?observation.uptime,
  };

  static StoredObservation? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (at == null) return null;
    final clients = json['clients'];
    final names = json['names'];
    final uptime = json['uptime'];
    return StoredObservation(
      at: at,
      observation: RouterObservation(
        reachable: json['reachable'] == true,
        wanUp: json['wanUp'] == true,
        clientMacs: {
          if (clients is List)
            for (final c in clients) c.toString(),
        },
        names: {
          if (names is Map)
            for (final e in names.entries) e.key.toString(): e.value.toString(),
        },
        uptime: uptime is num ? uptime.toInt() : null,
        observedAt: at,
      ),
    );
  }

  /// Whether this baseline is too old to diff against.
  ///
  /// After a long gap the client list has churned for reasons nobody wants
  /// notified; treating it as a fresh start is quieter and more honest.
  bool isStale(DateTime now, {Duration maxAge = const Duration(hours: 6)}) =>
      now.difference(at) > maxAge;
}

/// Client list handling shared with the foreground feed.
List<Client> clientsFromLeases(List<dynamic> leases) => [
  for (final lease in leases)
    if (lease is Map)
      Client(
        ipAddress: lease['ipaddr']?.toString() ?? 'N/A',
        macAddress: lease['macaddr']?.toString() ?? 'N/A',
        hostname: lease['hostname']?.toString() ?? 'Unknown',
      ),
];
