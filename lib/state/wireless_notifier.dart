import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/models/wireless_config.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/services/wireless_planner.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/uci_mutation.dart';

/// The router's wireless configuration, read from `uci.get wireless`.
///
/// Deliberately the *config* rather than `luci-rpc.getWirelessDevices`: this
/// screen edits what will be applied, and runtime state can differ from it
/// (a radio that failed to come up still has a config to fix).
final wirelessConfigProvider = FutureProvider<List<WirelessRadio>>((ref) async {
  final session = ref.watch(sessionProvider);
  final api = ref.watch(apiServiceProvider);
  if (session == null || api == null) return const [];

  return WirelessPlanner.parse(await uciConfigValues(api, session, 'wireless'));
}, retry: (_, _) => null);

/// Applies wireless edits.
final wirelessMutationsProvider = Provider<WirelessMutations>(
  WirelessMutations.new,
);

class WirelessMutations {
  WirelessMutations(this.ref);

  final Ref ref;

  /// Stages [ops] and applies them with the router's rollback protection.
  ///
  /// Wireless is the one config where applying can cut the path the change
  /// arrived on — renaming the SSID a phone is joined to disconnects it
  /// mid-apply. That is exactly what the rollback window is for, so the
  /// caller gets phase updates to show the countdown.
  Future<ApplyOutcome?> apply(
    List<UciOperation> ops, {
    BuildContext? context,
    void Function(ApplyPhase phase, Duration remaining)? onPhase,
  }) async {
    final outcome = await applyUciOperations(
      ref,
      ops,
      describe: 'wireless change',
      context: context,
      onPhase: onPhase,
    );
    if (ref.mounted) ref.invalidate(wirelessConfigProvider);
    return outcome;
  }
}
