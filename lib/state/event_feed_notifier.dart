import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/services/event_log.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';

final eventLogProvider = Provider<EventLog>(
  (ref) => EventLog(SecureStorageService()),
);

/// The feed for the active router.
final eventFeedProvider =
    AsyncNotifierProvider<EventFeedNotifier, List<RouterEvent>>(
      EventFeedNotifier.new,
      retry: (_, _) => null,
    );

class EventFeedNotifier extends AsyncNotifier<List<RouterEvent>> {
  RouterObservation? _previous;

  @override
  Future<List<RouterEvent>> build() async {
    final session = ref.watch(sessionProvider);
    if (session == null) return const [];
    // A new session means a new baseline: comparing across a router switch
    // would report the other router's clients as having left.
    _previous = null;
    return ref.read(eventLogProvider).load(session.routerId);
  }

  /// Folds a fresh poll into the feed.
  ///
  /// Called after the dashboard refreshes, so the feed costs no extra RPCs —
  /// it is entirely derived from data the app already had.
  Future<void> observe({
    required bool reachable,
    required Map<String, dynamic>? dashboardData,
    required List<Client> clients,
  }) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;

    var current = EventDeriver.observe(
      reachable: reachable,
      dashboardData: dashboardData,
      clients: clients,
    );
    // The dashboard data is stale while the router is away, so its uptime
    // is whatever was last reported - which is exactly the number a reboot
    // is detected against when the router comes back. Carry it explicitly
    // rather than trusting the stale payload.
    if (!reachable) current = current.withUptime(_previous?.uptime);
    final events = EventDeriver.diff(
      previous: _previous,
      current: current,
      routerId: session.routerId,
      at: DateTime.now(),
    );
    _previous = current;
    if (events.isEmpty) return;

    final merged = await ref
        .read(eventLogProvider)
        .append(session.routerId, events);
    if (!ref.mounted) return;
    state = AsyncValue.data(merged);
  }

  Future<void> clear() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    await ref.read(eventLogProvider).clear(session.routerId);
    if (!ref.mounted) return;
    state = const AsyncValue.data([]);
  }
}
