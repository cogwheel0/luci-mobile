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
  });

  final bool reachable;
  final bool wanUp;
  final Set<String> clientMacs;

  /// MAC -> the name to show. A feed that says "AA:BB:CC:11:22:33 joined"
  /// makes the reader do the lookup the app already did.
  final Map<String, String> names;

  String label(String mac) => names[mac] ?? mac;
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

  /// Builds an observation from what the dashboard already fetched.
  static RouterObservation observe({
    required bool reachable,
    required Map<String, dynamic>? dashboardData,
    required List<Client> clients,
  }) {
    final wan = dashboardData?['wan'];
    return RouterObservation(
      reachable: reachable,
      wanUp: wan is Map ? wan['up'] == true : false,
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
class EventLog {
  EventLog(this._storage);

  final SecureStorageService _storage;

  static const int maxEntries = 100;

  static String storageKey(String routerId) => 'events:$routerId';

  Future<List<RouterEvent>> load(String routerId) async {
    try {
      final raw = await _storage.readValue(storageKey(routerId));
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

  /// Appends [events], de-duplicating and trimming to [maxEntries].
  ///
  /// Returns the new list so callers do not have to re-read.
  Future<List<RouterEvent>> append(
    String routerId,
    List<RouterEvent> events,
  ) async {
    if (events.isEmpty) return load(routerId);
    final existing = await load(routerId);
    final seen = {for (final e in existing) e.dedupeKey};
    final merged = [
      ...existing,
      for (final e in events)
        if (seen.add(e.dedupeKey)) e,
    ];
    merged.sort((a, b) => a.at.compareTo(b.at));
    final trimmed = merged.length <= maxEntries
        ? merged
        : merged.sublist(merged.length - maxEntries);

    try {
      await _storage.writeValue(
        storageKey(routerId),
        jsonEncode([for (final e in trimmed) e.toJson()]),
      );
    } catch (e, stack) {
      Logger.exception('Failed to save the event log', e, stack);
    }
    return trimmed;
  }

  Future<void> clear(String routerId) async {
    try {
      await _storage.deleteValue(storageKey(routerId));
    } catch (e, stack) {
      Logger.exception('Failed to clear the event log', e, stack);
    }
  }
}
