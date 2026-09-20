import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/models/wireless_config.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/services/wireless_planner.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/feature_notifier.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/utils/logger.dart';

/// The router's wireless configuration, read from `uci.get wireless`.
///
/// Deliberately the *config* rather than `luci-rpc.getWirelessDevices`: this
/// screen edits what will be applied, and runtime state can differ from it
/// (a radio that failed to come up still has a config to fix).
final wirelessConfigProvider = FutureProvider<List<WirelessRadio>>((ref) async {
  final session = ref.watch(sessionProvider);
  final api = ref.watch(apiServiceProvider);
  if (session == null || api == null) return const [];

  final raw = await api.uciGetAll(
    session.ipAddress,
    session.sysauth,
    session.useHttps,
    config: 'wireless',
  );
  if (raw is! List || raw.length < 2) return const [];
  final data = raw[1];
  if (data is! Map) return const [];
  final values = data['values'] is Map
      ? Map<String, dynamic>.from(data['values'] as Map)
      : Map<String, dynamic>.from(data);
  return WirelessPlanner.parse(values);
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
    if (ops.isEmpty) return null;
    final service = ref.read(uciChangesetServiceProvider);
    if (service == null) return null;

    final appState = ref.read(appStateProvider);
    appState.beginCriticalSection();
    try {
      return await ref.read(sessionGuardProvider).run<ApplyOutcome>((
        session,
        ctx,
      ) async {
        await service.stage(session, ops, context: ctx);
        return service.apply(session, onPhase: onPhase);
      }, context: context?.mounted == true ? context : null);
    } on UciStagingException catch (e, stack) {
      Logger.exception('Staging wireless change failed', e, stack);
      return ApplyOutcome(
        phase: ApplyPhase.failed,
        applied: const UciChangeSet.empty(),
        error: e.cause,
      );
    } finally {
      await appState.endCriticalSection(refresh: false);
      if (ref.mounted) ref.invalidate(wirelessConfigProvider);
    }
  }
}
