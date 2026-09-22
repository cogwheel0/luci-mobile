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
    this.bootTime,
    this.uptime,
    this.uptimeAt,
  });

  final bool reachable;

  /// Whether the WAN is up, or null when the payload did not say - a poll
  /// that landed before the first dashboard fetch, say. Unknown is not
  /// down: a baseline of "down" would report the internet as restored on
  /// the next poll.
  final bool? wanUp;
  final Set<String> clientMacs;

  /// When the router booted, in its own clock's seconds: `localtime` minus
  /// `uptime` from `system.info`. Stays put while it runs and moves forward
  /// when it reboots - whatever the phone's clock does in between. It also
  /// moves when the router's clock does (a DST change, a new timezone),
  /// which is why [EventDeriver.rebootedBetween] asks the phone's clock to
  /// agree. Null when the router did not say, or its clock was not set.
  final int? bootTime;

  /// Seconds since boot, and the phone's time when they were read - the
  /// dashboard's fetch time, not this observation's. Together with
  /// [bootTime] this is the second witness a reboot needs.
  final int? uptime;
  final DateTime? uptimeAt;

  /// MAC -> the name to show. A feed that says "AA:BB:CC:11:22:33 joined"
  /// makes the reader do the lookup the app already did.
  final Map<String, String> names;

  String label(String mac) => names[mac] ?? mac;

  /// This observation carrying [other]'s reading of the router's clocks.
  RouterObservation withClocksOf(RouterObservation? other) => RouterObservation(
    reachable: reachable,
    wanUp: wanUp,
    clientMacs: clientMacs,
    names: names,
    bootTime: other?.bootTime,
    uptime: other?.uptime,
    uptimeAt: other?.uptimeAt,
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
    // the last boot time it reported, so the comparison still works when it
    // comes back.
    if (current.reachable && rebootedBetween(previous, current)) {
      events.add(
        RouterEvent(kind: RouterEventKind.rebooted, at: at, routerId: routerId),
      );
    }

    // A router we cannot reach tells us nothing about its WAN or its clients;
    // reporting "every client left" on a dropped connection would be noise.
    if (!current.reachable || !previous.reachable) return events;

    final wanWas = previous.wanUp;
    final wanIs = current.wanUp;
    if (wanWas == null || wanIs == null) {
      // Nothing to compare against on one side or the other.
    } else if (wanWas && !wanIs) {
      events.add(
        RouterEvent(kind: RouterEventKind.wanDown, at: at, routerId: routerId),
      );
    } else if (!wanWas && wanIs) {
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

  /// How far a router's boot time may drift between two readings before it
  /// counts as a reboot. `localtime` and `uptime` are read a moment apart
  /// and rounded to seconds; NTP nudges the clock by fractions.
  static const Duration rebootSlack = Duration(seconds: 30);

  /// A router clock earlier than this is not set yet: OpenWrt boots at its
  /// build date until NTP answers, and a boot time computed from that
  /// would jump forward by years once it does.
  static final DateTime clockSetAfter = DateTime.utc(2020);

  /// Whether the router booted between the two readings.
  ///
  /// Uptime going backwards is proof on its own. Otherwise two witnesses
  /// must agree, because each alone has a false positive the other does
  /// not: the router's boot time moving forward also happens when its
  /// clock changes (DST, a new timezone), and uptime falling short of the
  /// phone-measured elapsed time also happens when the *phone's* clock
  /// jumps. A real reboot shows in both. The same payload read twice is
  /// one reading, and no evidence of anything.
  static bool rebootedBetween(
    RouterObservation previous,
    RouterObservation current,
  ) {
    final before = previous.uptime;
    final now = current.uptime;
    if (before == null || now == null) return false;
    final since = previous.uptimeAt;
    final until = current.uptimeAt;
    if (since != null && until != null && !until.isAfter(since)) return false;
    if (now < before) return true;

    final booted = previous.bootTime;
    final bootedNow = current.bootTime;
    if (booted == null || bootedNow == null) return false;
    if (bootedNow - booted <= rebootSlack.inSeconds) return false;
    if (since == null || until == null) return false;
    final elapsed = until.difference(since).inSeconds;
    return now + rebootSlack.inSeconds < before + elapsed;
  }

  /// The router's boot time out of a `system.info` payload, or null when it
  /// is missing or the router's clock is plainly unset.
  static int? bootTimeOf(dynamic sysInfo) {
    if (sysInfo is! Map) return null;
    final uptime = sysInfo['uptime'];
    final localtime = sysInfo['localtime'];
    if (uptime is! num || localtime is! num) return null;
    if (localtime < clockSetAfter.millisecondsSinceEpoch ~/ 1000) return null;
    return localtime.toInt() - uptime.toInt();
  }

  /// Builds an observation from what the dashboard already fetched.
  ///
  /// [readAt] is when `system.info` was read; the dashboard stamps its
  /// payload with `fetchedAt`, and a poll that read it itself says so.
  static RouterObservation observe({
    required bool reachable,
    required Map<String, dynamic>? dashboardData,
    required List<Client> clients,
    DateTime? readAt,
  }) {
    final wan = dashboardData?['wan'];
    final sysInfo = dashboardData?['sysInfo'];
    final uptime = sysInfo is Map ? sysInfo['uptime'] : null;
    return RouterObservation(
      reachable: reachable,
      wanUp: wan is Map ? wan['up'] == true : null,
      bootTime: bootTimeOf(sysInfo),
      uptime: uptime is num ? uptime.toInt() : null,
      uptimeAt: readAt ?? dashboardData?['fetchedAt'] as DateTime?,
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

  /// How close two records of the same thing may be before they are one
  /// event seen by two observers.
  static const Duration echoWindow = Duration(minutes: 5);

  /// [a] and [b] de-duplicated, in time order, trimmed to [maxEntries].
  ///
  /// The app and the background poll each derive events against their own
  /// baseline, so one change - a device joining - can be recorded by both,
  /// seconds apart. A record of the same kind about the same subject, with
  /// nothing else about that subject in between and within [echoWindow] of
  /// the last, is the echo, not a second event.
  static List<RouterEvent> _merge(List<RouterEvent> a, List<RouterEvent> b) {
    final seen = <String>{};
    final merged = [
      for (final e in a)
        if (seen.add(e.dedupeKey)) e,
      for (final e in b)
        if (seen.add(e.dedupeKey)) e,
    ];
    merged.sort((a, b) => a.at.compareTo(b.at));
    final kept = <RouterEvent>[];
    final lastFor = <String, RouterEvent>{};
    for (final e in merged) {
      final subject = '${e.routerId}|${e.subject ?? ""}';
      final last = lastFor[subject];
      final echo =
          last != null &&
          last.kind == e.kind &&
          e.at.difference(last.at) <= echoWindow;
      lastFor[subject] = e;
      if (!echo) kept.add(e);
    }
    return kept.length <= maxEntries
        ? kept
        : kept.sublist(kept.length - maxEntries);
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
