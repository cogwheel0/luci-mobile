import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/apply_lock.dart';
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

  // Captured before the first await, not after. These operations were
  // planned against this router's config — section names and all — so if
  // the user switches routers while the capability probe or the apply lock
  // is awaited, they must not land on whichever router is selected by then.
  final queuedFor = ref.read(sessionProvider);
  if (queuedFor == null) return null;

  final (mode, verified) = await _applyMode(ref);
  // `uci.apply` is global, so the service needs to know which configs are
  // ours to tell somebody else's staged work apart from our own.
  final ours = {for (final op in ops) op.config};

  final appState = ref.read(appStateProvider);

  // Queue behind any apply already in flight: staging is shared per session,
  // so interleaving would let one operation commit the other's half-built
  // change set.
  return ref.read(applyLockProvider).run<ApplyOutcome?>(() async {
    if (!ref.mounted) return null;
    // The wait may have outlived the session the operation was queued on -
    // an expiry and re-login while another apply held the lock. The same
    // router's fresh session is the one to stage against; only a different
    // router means the operations no longer fit.
    final session = ref.read(sessionProvider);
    if (session == null || session.routerId != queuedFor.routerId) return null;

    appState.beginCriticalSection();
    try {
      // Not through the session guard: it would return null when the
      // session changed while the apply ran, and a change the router has
      // already confirmed does not become "failed" because a re-login
      // happened during the confirm window. The session was checked just
      // now; from here the outcome is the router's word.
      final ctx = context?.mounted == true ? context : null;
      final staged = await service.stage(session, ops, context: ctx);
      return await service.apply(
        session,
        mode: mode,
        ours: ours,
        baseline: staged.baseline,
        writtenKeys: staged.writtenKeys,
        ownedSections: staged.ownedSections,
        rollbackVerified: verified,
        onPhase: onPhase,
      );
    } on UciStagingException catch (e, stack) {
      Logger.exception('Staging $describe failed', e, stack);
      return ApplyOutcome(
        phase: ApplyPhase.failed,
        applied: const UciChangeSet.empty(),
        stillStaged: e.stillStaged,
        error: e.cause,
      );
    } finally {
      // Most changes only affect the screen that made them. A few — the
      // hostname is the obvious one — are shown on the dashboard too, and
      // invalidating the feature provider alone would leave it stale.
      //
      // Guarded, because this runs in a `finally`: a refresh that throws
      // would replace the outcome the caller is waiting for with the cleanup
      // error, turning a successful apply into a reported failure.
      try {
        await appState.endCriticalSection(refresh: refreshDashboard);
      } catch (e, stack) {
        Logger.exception('Resuming after $describe failed', e, stack);
      }
    }
  });
}

/// Whether to ask the router for rollback protection, and whether that
/// protection is known to be real.
///
/// Measured on stock OpenWrt 24.10: `uci.rollback` is denied even to root,
/// and an unconfirmed apply is committed anyway. Requesting a rollback the
/// router will not perform — and counting down to it in the UI — promises a
/// safety net that is not there, which is worse than admitting there is
/// none.
///
/// Only a *measured* denial drops the protection. A probe that failed or never
/// ran says nothing about the router, and treating it as "no rollback" would
/// commit irreversibly over a blip in connectivity. But rollback is then
/// requested without knowing it will happen, so the outcome carries
/// `verified: false` and an unconfirmed apply is reported as exactly that,
/// not as "rolled back".
Future<(ApplyMode, bool)> _applyMode(Ref ref) async {
  try {
    final caps = await ref.read(capabilitiesProvider.future);
    final rollback = caps.of(RouterFeature.uciApplyRollback);
    // Available on the strength of an unanswered probe is not measured.
    if (rollback.available) return (ApplyMode.checked, rollback.verified);
    return rollback.reason == UnavailableReason.noPermission
        ? (ApplyMode.unchecked, true)
        : (ApplyMode.checked, false);
  } catch (e, stack) {
    Logger.exception('Could not read rollback capability', e, stack);
    return (ApplyMode.checked, false);
  }
}
