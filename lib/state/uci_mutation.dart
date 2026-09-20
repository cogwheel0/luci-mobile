import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/feature_notifier.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/utils/logger.dart';

/// Stages and applies [ops] on the selected router.
///
/// Every configuration screen goes through here rather than repeating the
/// stage/apply dance. That is not just tidiness: when each screen owned its
/// own copy, a rule added to the changeset service had to be remembered in
/// five places, and the rollback capability gate was missed in all of them.
Future<ApplyOutcome?> applyUciOperations(
  Ref ref,
  List<UciOperation> ops, {
  required String describe,
  BuildContext? context,
  void Function(ApplyPhase phase, Duration remaining)? onPhase,
  bool refreshDashboard = false,
}) async {
  if (ops.isEmpty) return null;
  final service = ref.read(uciChangesetServiceProvider);
  if (service == null) return null;

  final mode = await _applyMode(ref);
  // `uci.apply` is global, so the service needs to know which configs are
  // ours to tell somebody else's staged work apart from our own.
  final ours = {for (final op in ops) op.config};

  final appState = ref.read(appStateProvider);
  appState.beginCriticalSection();
  try {
    return await ref.read(sessionGuardProvider).run<ApplyOutcome>((
      session,
      ctx,
    ) async {
      await service.stage(session, ops, context: ctx);
      return service.apply(session, mode: mode, ours: ours, onPhase: onPhase);
    }, context: context?.mounted == true ? context : null);
  } on UciStagingException catch (e, stack) {
    Logger.exception('Staging $describe failed', e, stack);
    return ApplyOutcome(
      phase: ApplyPhase.failed,
      applied: const UciChangeSet.empty(),
      error: e.cause,
    );
  } finally {
    // Most changes only affect the screen that made them. A few — the
    // hostname is the obvious one — are shown on the dashboard too, and
    // invalidating the feature provider alone would leave it stale.
    await appState.endCriticalSection(refresh: refreshDashboard);
  }
}

/// Whether to ask the router for rollback protection.
///
/// Measured on stock OpenWrt 24.10: `uci.rollback` is denied even to root,
/// and an unconfirmed apply is committed anyway. Requesting a rollback the
/// router will not perform — and counting down to it in the UI — promises a
/// safety net that is not there, which is worse than admitting there is
/// none.
Future<ApplyMode> _applyMode(Ref ref) async {
  try {
    final caps = await ref.read(capabilitiesProvider.future);
    return caps.of(RouterFeature.uciApplyRollback).available
        ? ApplyMode.checked
        : ApplyMode.unchecked;
  } catch (e, stack) {
    Logger.exception('Could not read rollback capability', e, stack);
    // Unknown capabilities already read as "probably allowed" elsewhere;
    // asking for rollback costs nothing if the router ignores it.
    return ApplyMode.checked;
  }
}
