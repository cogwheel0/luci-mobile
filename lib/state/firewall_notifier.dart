import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/models/firewall_config.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/firewall_planner.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/state/uci_mutation.dart';
import 'package:luci_mobile/utils/logger.dart';

/// Everything the firewall screens render.
@immutable
class FirewallState {
  const FirewallState({
    this.zones = const [],
    this.forwards = const [],
    this.rules = const [],
    this.routes = const [],
    this.sectionNames = const {},
  });

  final List<FirewallZone> zones;
  final List<PortForward> forwards;
  final List<TrafficRule> rules;
  final List<StaticRoute> routes;

  /// Every section in the firewall config, of any type — a new section has
  /// to avoid all of them, not just the ones this screen parses, because
  /// `uci.add` with an existing name silently re-sets that section. See
  /// [FirewallMutations.takenSectionNames] for the ones a new section must
  /// actually avoid.
  final Set<String> sectionNames;

  /// The zone a port forward should be sent to, if one is obvious.
  ///
  /// The first zone that does not face the internet, which on a stock
  /// router is `lan` and on a renamed one is whatever the user called it.
  String get lanZone {
    for (final z in zones) {
      if (!z.looksLikeWan) return z.name;
    }
    return zones.isEmpty ? 'lan' : zones.first.name;
  }

  /// The zone a port forward should arrive on, if one is obvious.
  String? get wanZone {
    for (final z in zones) {
      if (z.looksLikeWan) return z.name;
    }
    return zones.isEmpty ? null : zones.first.name;
  }

  List<String> get zoneNames => [for (final z in zones) z.name];
}

final firewallProvider = FutureProvider<FirewallState>((ref) async {
  final session = ref.watch(sessionProvider);
  final api = ref.watch(apiServiceProvider);
  if (session == null || api == null) return const FirewallState();

  final firewall = await uciConfigValues(api, session, 'firewall');
  // Routes live in the network config, not the firewall one. A failure there
  // should not blank the port-forward list.
  var network = const <String, dynamic>{};
  try {
    network = await uciConfigValues(api, session, 'network');
  } catch (e, stack) {
    Logger.exception('Static routes unavailable', e, stack);
  }

  return FirewallState(
    zones: FirewallPlanner.zones(firewall),
    forwards: FirewallPlanner.portForwards(firewall),
    rules: FirewallPlanner.trafficRules(firewall),
    routes: FirewallPlanner.routes(network),
    sectionNames: firewall.keys.toSet(),
  );
}, retry: (_, _) => null);

final firewallMutationsProvider = Provider<FirewallMutations>(
  FirewallMutations.new,
);

class FirewallMutations {
  FirewallMutations(this.ref);

  final Ref ref;

  /// The names a new section must avoid: [FirewallState.sectionNames] less
  /// this session's own uncommitted adds.
  ///
  /// `uci.get` shows those too, and a forward whose apply failed and could
  /// not be reverted must be re-added under its own name - which re-sets it
  /// - not as `_2` with the leftover left in the way of every apply that
  /// follows. Read here, when a forward is about to be created, rather
  /// than on every load of the screen.
  Future<Set<String>> takenSectionNames(FirewallState state) async {
    final session = ref.read(sessionProvider);
    final service = ref.read(uciChangesetServiceProvider);
    if (session == null || service == null) return state.sectionNames;
    UciChangeSet? pending;
    try {
      pending = await service.pending(session, config: 'firewall');
    } catch (e, stack) {
      Logger.exception('Pending firewall changes unavailable', e, stack);
    }
    return FirewallPlanner.takenSectionNames(state.sectionNames, pending);
  }

  Future<ApplyOutcome?> apply(
    List<UciOperation> ops, {
    BuildContext? context,
    void Function(ApplyPhase phase, Duration remaining)? onPhase,
  }) async {
    final outcome = await applyUciOperations(
      ref,
      ops,
      describe: 'firewall change',
      context: context,
      onPhase: onPhase,
    );
    if (ref.mounted) ref.invalidate(firewallProvider);
    return outcome;
  }
}
