import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/models/firewall_config.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/firewall_planner.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/uci_mutation.dart';
import 'package:luci_mobile/state/router_session.dart';
import 'package:luci_mobile/utils/logger.dart';

/// Everything the firewall screens render.
@immutable
class FirewallState {
  const FirewallState({
    this.zones = const [],
    this.forwards = const [],
    this.rules = const [],
    this.routes = const [],
  });

  final List<FirewallZone> zones;
  final List<PortForward> forwards;
  final List<TrafficRule> rules;
  final List<StaticRoute> routes;

  /// The zone a port forward should arrive on, if one is obvious.
  String? get wanZone {
    for (final z in zones) {
      if (z.looksLikeWan) return z.name;
    }
    return zones.isEmpty ? null : zones.first.name;
  }

  List<String> get zoneNames => [for (final z in zones) z.name];
}

Future<Map<String, dynamic>> _configValues(
  IApiService api,
  RouterSession session,
  String config,
) async {
  final raw = await api.uciGetAll(
    session.ipAddress,
    session.sysauth,
    session.useHttps,
    config: config,
  );
  if (raw is! List || raw.length < 2) return const {};
  final data = raw[1];
  if (data is! Map) return const {};
  final values = data['values'];
  return values is Map
      ? Map<String, dynamic>.from(values)
      : Map<String, dynamic>.from(data);
}

final firewallProvider = FutureProvider<FirewallState>((ref) async {
  final session = ref.watch(sessionProvider);
  final api = ref.watch(apiServiceProvider);
  if (session == null || api == null) return const FirewallState();

  final firewall = await _configValues(api, session, 'firewall');
  // Routes live in the network config, not the firewall one. A failure there
  // should not blank the port-forward list.
  var network = const <String, dynamic>{};
  try {
    network = await _configValues(api, session, 'network');
  } catch (e, stack) {
    Logger.exception('Static routes unavailable', e, stack);
  }

  return FirewallState(
    zones: FirewallPlanner.zones(firewall),
    forwards: FirewallPlanner.portForwards(firewall),
    rules: FirewallPlanner.trafficRules(firewall),
    routes: FirewallPlanner.routes(network),
  );
}, retry: (_, _) => null);

final firewallMutationsProvider = Provider<FirewallMutations>(
  FirewallMutations.new,
);

class FirewallMutations {
  FirewallMutations(this.ref);

  final Ref ref;

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
