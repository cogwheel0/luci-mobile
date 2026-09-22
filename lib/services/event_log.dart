import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/utils/logger.dart';

/// A snapshot of the things the feed watches, taken on each poll.
@immutable
class RouterObservation {
  const RouterObservation({
    required this.reachable,
    required this.wanUp,
    required this.clientMacs,
    this.names = const {},
    this.uptime,
    this.uptimeAt,
  });

  final bool reachable;
  final bool wanUp;
  final Set<String> clientMacs;

  /// Seconds since the router booted, when `system.info` reported it. Going
  /// backwards between two observations is the only evidence of a reboot
  /// there is.
  final int? uptime;

  /// When [uptime] was read from the router - not when this observation
  /// was made. The foreground feed reads it out of a dashboard payload that
  /// may be minutes old, and two observations of the same payload must not
  /// read as a router that failed to gain uptime.
  final DateTime? uptimeAt;

  /// MAC -> the name to show. A feed that says "AA:BB:CC:11:22:33 joined"
  /// makes the reader do the lookup the app already did.
  final Map<String, String> names;

  String label(String mac) => names[mac] ?? mac;

  /// This observation with [uptime], read at [uptimeAt], in place of its own.
  RouterObservation withUptime(int? uptime, DateTime? uptimeAt) =>
      RouterObservation(
        reachable: reachable,
        wanUp: wanUp,
        clientMacs: clientMacs,
        names: names,
        uptime: uptime,
        uptimeAt: uptimeAt,
      );
}

/// Derives events by comparing consecutive observations.
///
/// This is a pure diff on purpose: the router has no event stream to
/// subscribe to, so "what changed" is the only honest source, and keeping it
/// pure makes every rule testable without a router or a clock.
class EventDeriver {
  const EventDeriver._();

  /// Events implied by moving from [previous] to [current].
  ///
  /// The first observation of a session yields nothing: with nothing to
  /// compare against, every client would look like it had just joined.
  static List<RouterEvent> diff({
    required RouterObservation? previous,
    required RouterObservation current,
    required String routerId,
    required DateTime at,
  }) {
    if (previous == null) return const [];
    final events = <RouterEvent>[];

    if (previous.reachable && !current.reachable) {
      events.add(
        RouterEvent(
          kind: RouterEventKind.routerUnreachable,
          at: at,
          routerId: routerId,
        ),
      );
    } else if (!previous.reachable && current.reachable) {
      events.add(
        RouterEvent(
          kind: RouterEventKind.routerBack,
          at: at,
          routerId: routerId,
        ),
      );
    }

    // Before the reachability guard: a reboot is usually *seen* as an
    // outage, and the observation taken while the router was away carries
    // the last uptime it reported, so the comparison still works when it
    // comes back.
    if (current.reachable && rebootedBetween(previous, current)) {
      events.add(
        RouterEvent(kind: RouterEventKind.rebooted, at: at, routerId: routerId),
      );
    }

    // A router we cannot reach tells us nothing about its WAN or its clients;
    // reporting "every client left" on a dropped connection would be noise.
    if (!current.reachable || !previous.reachable) return events;

    if (previous.wanUp && !current.wanUp) {
      events.add(
        RouterEvent(kind: RouterEventKind.wanDown, at: at, routerId: routerId),
      );
    } else if (!previous.wanUp && current.wanUp) {
      events.add(
        RouterEvent(kind: RouterEventKind.wanUp, at: at, routerId: routerId),
      );
    }

    for (final mac in current.clientMacs.difference(previous.clientMacs)) {
      events.add(
        RouterEvent(
          kind: RouterEventKind.clientJoined,
          at: at,
          routerId: routerId,
          subject: current.label(mac),
        ),
      );
    }
    for (final mac in previous.clientMacs.difference(current.clientMacs)) {
      events.add(
        RouterEvent(
          kind: RouterEventKind.clientLeft,
          at: at,
          routerId: routerId,
          subject: previous.label(mac),
        ),
      );
    }

    return events;
  }

  /// Jitter allowed between the uptime a router gained and the time that
  /// passed between two observations, before the gap reads as a reboot.
  static const Duration rebootSlack = Duration(seconds: 30);

  /// Whether the router's uptime fell short of what it should have gained
  /// between the two readings.
  ///
  /// Comparing the raw numbers is not enough: a router that rebooted twice
  /// in a row, or whose last known uptime was shorter than the gap between
  /// polls, shows a *larger* uptime after the second reboot. With the time
  /// between the two readings known, `uptime` should have grown by about
  /// that much. A reading that is not newer than the previous one is the
  /// same payload seen twice, and says nothing.
  static bool rebootedBetween(
    RouterObservation previous,
    RouterObservation current,
  ) {
    final before = previous.uptime;
    final now = current.uptime;
    if (before == null || now == null) return false;
    final since = previous.uptimeAt;
    final until = current.uptimeAt;
    if (since == null || until == null) return now < before;
    if (!until.isAfter(since)) return false;
    final elapsed = until.difference(since);
    return now + rebootSlack.inSeconds < before + elapsed.inSeconds;
  }

  /// Builds an observation from what the dashboard already fetched.
  static RouterObservation observe({
    required bool reachable,
    required Map<String, dynamic>? dashboardData,
    required List<Client> clients,
    DateTime? uptimeAt,
  }) {
    final wan = dashboardData?['wan'];
    final sysInfo = dashboardData?['sysInfo'];
    final uptime = sysInfo is Map ? sysInfo['uptime'] : null;
    return RouterObservation(
      reachable: reachable,
      wanUp: wan is Map ? wan['up'] == true : false,
      uptime: uptime is num ? uptime.toInt() : null,
      // The dashboard stamps its payload; a poll that fetched `system.info`
      // itself says so.
      uptimeAt: uptimeAt ?? dashboardData?['fetchedAt'] as DateTime?,
      clientMacs: {
        for (final c in clients)
          if (c.macAddress != 'N/A') c.macAddress.toUpperCase(),
      },
      names: {
        for (final c in clients)
          if (c.macAddress != 'N/A' &&
              c.hostname.isNotEmpty &&
              c.hostname != 'Unknown')
            c.macAddress.toUpperCase(): c.hostname,
      },
    );
  }
}

/// Persists the feed per router.
///
/// Events only exist while the app is open, so without persistence the feed
/// is empty on every cold start — which users read as broken. Keeping the
/// last [maxEntries] means it has something to show and can honestly say how
/// far back it goes.
///
/// Two isolates write events: the app, and the WorkManager poll. Each has a
/// key of its own, because an append is a read-modify-write and two of them
/// on one key silently lose whichever landed first. The feed the app shows
/// is the union of both.
class EventLog {
  EventLog(this._storage);

  final SecureStorageService _storage;

  static const int maxEntries = 100;

  /// The key the app writes.
  static String storageKey(String routerId) => 'events:$routerId';

  /// The key the background isolate writes.
  static String backgroundKey(String routerId) => 'events:bg:$routerId';

  /// Everything recorded for [routerId], from both writers.
  Future<List<RouterEvent>> load(String routerId) async {
    final (own, background) = await (
      _read(storageKey(routerId)),
      _read(backgroundKey(routerId)),
    ).wait;
    return _merge(own, background);
  }

  Future<List<RouterEvent>> _read(String key) async {
    try {
      final raw = await _storage.readValue(key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map<String, dynamic>) ?RouterEvent.fromJson(e),
      ];
    } catch (e, stack) {
      Logger.exception('Failed to read the event log', e, stack);
      return const [];
    }
  }

  /// [a] and [b] de-duplicated, in time order, trimmed to [maxEntries].
  static List<RouterEvent> _merge(List<RouterEvent> a, List<RouterEvent> b) {
    final seen = <String>{};
    final merged = [
      for (final e in a)
        if (seen.add(e.dedupeKey)) e,
      for (final e in b)
        if (seen.add(e.dedupeKey)) e,
    ];
    merged.sort((a, b) => a.at.compareTo(b.at));
    return merged.length <= maxEntries
        ? merged
        : merged.sublist(merged.length - maxEntries);
  }

  /// Appends [events], de-duplicating and trimming to [maxEntries].
  ///
  /// [fromBackground] selects the background isolate's key; the app's copy
  /// picks those events up on its next [load]. Returns the full feed so
  /// callers do not have to re-read.
  Future<List<RouterEvent>> append(
    String routerId,
    List<RouterEvent> events, {
    bool fromBackground = false,
  }) async {
    if (events.isEmpty) return load(routerId);
    final key = fromBackground ? backgroundKey(routerId) : storageKey(routerId);
    final own = _merge(await _read(key), events);
    try {
      await _storage.writeValue(
        key,
        jsonEncode([for (final e in own) e.toJson()]),
      );
    } catch (e, stack) {
      Logger.exception('Failed to save the event log', e, stack);
    }
    return fromBackground
        ? _merge(await _read(storageKey(routerId)), own)
        : _merge(own, await _read(backgroundKey(routerId)));
  }

  Future<void> clear(String routerId) async {
    // Each on its own: a failure on one must not leave the other to bring
    // the cleared feed back on the next load.
    for (final key in [storageKey(routerId), backgroundKey(routerId)]) {
      try {
        await _storage.deleteValue(key);
      } catch (e, stack) {
        Logger.exception('Failed to clear the event log', e, stack);
      }
    }
  }
}
