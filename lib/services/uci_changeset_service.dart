import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/router_liveness_probe.dart';
import 'package:luci_mobile/state/router_session.dart';
import 'package:luci_mobile/utils/logger.dart';

/// How an apply is committed.
enum ApplyMode {
  /// `uci.apply {rollback: true}` - the router reverts by itself unless the
  /// app confirms in time. The default, and the only safe choice for changes
  /// that could sever this client's own connectivity.
  checked,

  /// `uci.apply {rollback: false}` - committed immediately and irreversibly.
  /// Only for routers whose ACL denies `uci.confirm`, and only after telling
  /// the user.
  unchecked,
}

enum ApplyPhase {
  idle,
  applying,
  awaitingConfirm,
  confirmed,
  rolledBack,
  failed,
}

/// Why a rollback-protected apply did not get confirmed.
enum RollbackReason {
  /// The router never became reachable again within the window.
  unreachable,

  /// The router answered, but rejected `uci.confirm` - almost always because
  /// the session that called `uci.apply` no longer exists.
  sessionLost,

  /// The router's rollback timer had already fired when confirm arrived.
  deadlineMissed,

  /// The router refused the apply outright.
  routerRejected,

  /// The session had unrelated changes staged, and `uci.apply` commits the
  /// whole session — so going ahead would have committed those too.
  foreignChanges,

  /// What was staged could not be read, so nothing was applied: committing
  /// blind could have taken unrelated changes along.
  stateUnknown,
}

@immutable
class ApplyOutcome {
  const ApplyOutcome({
    required this.phase,
    required this.applied,
    this.foreign = const UciChangeSet.empty(),
    this.stillStaged = const {},
    this.reason,
    this.error,
    this.rollbackVerified = true,
  });

  final ApplyPhase phase;

  /// False when rollback was requested without a measured `uci.rollback`
  /// grant. Measured on stock OpenWrt 24.10: without it, an unconfirmed
  /// apply stays committed - so a [ApplyPhase.rolledBack] outcome then only
  /// means "could not confirm", and must be worded that way.
  final bool rollbackVerified;

  /// What was staged at the moment the apply began.
  final UciChangeSet applied;

  /// Staged changes this operation did not make, when that is why it was
  /// refused.
  final UciChangeSet foreign;

  /// Configs left staged on the router by a failure, so the message can say
  /// which ones need discarding.
  final Set<String> stillStaged;

  final RollbackReason? reason;
  final Object? error;

  bool get succeeded => phase == ApplyPhase.confirmed;
}

/// Thrown when staging fails partway through a batch. The service has already
/// reverted every config it touched by the time this surfaces.
class UciStagingException implements Exception {
  const UciStagingException({
    required this.failedIndex,
    required this.cause,
    required this.revertedConfigs,
    this.stillStaged = const {},
    this.revertFailed = false,
  });

  final int failedIndex;
  final Object cause;
  final Set<String> revertedConfigs;

  /// Configs this operation touched but did not clean up — either they were
  /// already dirty, or the revert itself failed. The user has to deal with
  /// them, so the names have to survive as far as the message.
  final Set<String> stillStaged;

  /// True when the cleanup revert itself failed, meaning changes may still be
  /// staged on the router.
  final bool revertFailed;

  @override
  String toString() => 'UciStagingException(op $failedIndex: $cause)';
}

/// Stages UCI changes and commits them using the router's own
/// apply-with-rollback protocol.
///
/// The point of this class is that a phone can apply a configuration change
/// that breaks its own path to the router. `uci.apply {rollback: true}` starts
/// a timer on the router; if [UciChangesetService.apply] cannot reach the
/// router again and call `uci.confirm` before it expires, the router restores
/// the previous configuration without any help from the app.
///
/// Nothing is committed until [apply] runs, so a failure part-way through
/// [stage] is undone with `uci.revert` and never reaches a running service.
class UciChangesetService {
  UciChangesetService(
    this._api, {
    IRouterLivenessProbe probe = const RouterLivenessProbe(),
    DateTime Function() clock = DateTime.now,
    Future<void> Function(Duration) delay = _defaultDelay,
  }) : _probe = probe,
       _clock = clock,
       _delay = delay;

  final IApiService _api;
  final IRouterLivenessProbe _probe;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;

  static Future<void> _defaultDelay(Duration d) => Future<void>.delayed(d);

  /// Default rollback window.
  ///
  /// LuCI's web UI uses 10 seconds, which assumes a browser on the same LAN.
  /// A phone may have to re-associate to a renamed SSID, pick up a new lease,
  /// or fall back to a second address before it can confirm.
  static const Duration defaultTimeout = Duration(seconds: 90);

  /// Stop confirming this long before the router's timer fires. A confirm that
  /// lands after the deadline returns "no data" and the change is already gone;
  /// reporting success there would be the worst possible outcome.
  static const Duration _confirmGuardBand = Duration(seconds: 5);

  static const List<Duration> _probeBackoff = [
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 12),
  ];

  /// Reads what is currently staged on the router.
  ///
  /// This includes changes staged by other clients - an open LuCI browser tab,
  /// another admin - because `uci.apply` is global and will commit them too.
  Future<UciChangeSet> pending(
    RouterSession session, {
    String? config,
    BuildContext? context,
  }) async {
    final raw = await _api.uciChanges(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      config: config,
      context: context,
    );
    return UciChangeSet.fromWire(raw, fetchedAt: _clock());
  }

  /// Runs [ops] in order without committing anything.
  ///
  /// Returns the section id the router generated for each [UciAdd], keyed by
  /// the operation's index in [ops], so later operations in the same batch can
  /// reference an anonymous section.
  ///
  /// On failure every config touched so far is reverted and a
  /// [UciStagingException] is thrown.
  Future<
    ({
      Map<int, String> sections,
      UciChangeSet? baseline,
      Set<String> writtenKeys,
      Set<String> ownedSections,
    })
  >
  stage(
    RouterSession session,
    List<UciOperation> ops, {
    BuildContext? context,
  }) async {
    final generatedSections = <int, String>{};
    final touched = <String>{};
    // What this batch wrote - row keys, and the sections it created, adopted
    // or edited while they were uncommitted adds - so that apply can tell a
    // row we just (re-)staged from one left behind earlier.
    final writtenKeys = <String>{};
    final ownedSections = <String>{};

    // `uci.revert` is config-wide, so cleaning up after a failed batch would
    // also discard anything already staged in the same config — typically
    // leftovers from an earlier operation in this session that the user has
    // not applied yet. Capture what was pending first and leave those
    // configs alone.
    //
    // Measured on OpenWrt 24.10.4: rpcd keeps staging *per session*, so this
    // is not about another admin's work — a second rpcd session's edits and
    // CLI-staged edits are both invisible here, and unaffected by our apply.
    UciChangeSet? baseline;
    Set<String>? preExisting;
    try {
      baseline = await pending(session, context: context);
      preExisting = baseline.configs;
    } catch (e, stack) {
      Logger.exception(
        'Could not read pending changes before staging',
        e,
        stack,
      );
      // Null means "we do not know what else is staged". Cleanup then
      // reverts nothing: leaving our own half-staged change behind is
      // recoverable — it shows up as unsaved and can be discarded — whereas
      // silently dropping an edit the user still wanted is not.
      baseline = null;
      preExisting = null;
    }

    // Sections this batch has created, adopted or deleted: never a leftover
    // for a later operation in the same batch to adopt or sweep again.
    final consumed = <String>{};
    void own(String config, String section) =>
        ownedSections.add(UciChange.sectionIdOf(config, section));
    // An option written to a section that is still an uncommitted add: the
    // whole section is ours, its `add` row and earlier options included.
    void wrote(UciOperation op, String section) {
      writtenKeys.addAll(op.writtenKeys);
      if (baseline?.hasAdd(op.config, section) ?? false) {
        own(op.config, section);
      }
    }

    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      // Before anything else, so an adopted section is still reported as
      // left staged if a later operation in the batch fails.
      touched.add(op.config);

      // A failed apply whose cleanup revert was denied leaves our own rows
      // staged. A retry simply overwrites a named row, but an anonymous add
      // cannot be overwritten — the router names the section — so retrying
      // would pile a duplicate on top and then be refused for the leftover.
      // Staging is per session, so an uncommitted add of this type can only
      // be this app's earlier attempt: identical values mean the same edit,
      // and it is adopted; different values mean a corrected retry, and the
      // leftover is deleted first. `uci.delete` of an uncommitted section is
      // what the stock ACL does grant, unlike `uci.revert`.
      if (op is UciAdd &&
          op.name == null &&
          op.identity.isNotEmpty &&
          baseline != null) {
        final adopted = _identicalStagedAdd(baseline, op, spare: consumed);
        if (adopted != null) {
          Logger.info('Reusing staged ${op.config} section $adopted');
          generatedSections[i] = adopted;
          consumed.add(adopted);
          own(op.config, adopted);
          continue;
        }
        try {
          // Owned even after the delete: libuci keeps the earlier rows in
          // the delta alongside the removal, and they are ours.
          await _sweepLeftoverAdds(
            session,
            baseline,
            op,
            spare: consumed,
            onSwept: (swept) {
              consumed.add(swept);
              own(op.config, swept);
            },
            context: context?.mounted == true ? context : null,
          );
        } catch (e, stack) {
          // Not fatal here: the apply will refuse and name the config.
          Logger.exception('Could not clear a leftover staged add', e, stack);
        }
      }

      try {
        switch (op) {
          case UciSet():
            await _api.uciSet(
              session.ipAddress,
              session.sysauth,
              session.useHttps,
              config: op.config,
              section: op.section,
              values: op.values,
              context: context?.mounted == true ? context : null,
            );
            wrote(op, op.section);
          case UciSetList():
            await _api.uciSet(
              session.ipAddress,
              session.sysauth,
              session.useHttps,
              config: op.config,
              section: op.section,
              values: {op.option: op.values},
              context: context?.mounted == true ? context : null,
            );
            wrote(op, op.section);
          case UciAdd():
            final result = await _api.uciAdd(
              session.ipAddress,
              session.sysauth,
              session.useHttps,
              config: op.config,
              type: op.type,
              values: op.values,
              name: op.name,
              context: context?.mounted == true ? context : null,
            );
            final section = op.name ?? parseUciAddSection(result);
            if (section == null) {
              throw const RpcException(
                object: 'uci',
                method: 'add',
                detail: 'router did not return a section name',
              );
            }
            generatedSections[i] = section;
            consumed.add(section);
            own(op.config, section);
          case UciRemove():
            await _api.uciDelete(
              session.ipAddress,
              session.sysauth,
              session.useHttps,
              config: op.config,
              section: op.section,
              option: op.option,
              context: context?.mounted == true ? context : null,
            );
            wrote(op, op.section);
        }
      } catch (e, stack) {
        Logger.exception('Failed to stage UCI operation $i', e, stack);
        final backedOut = await _backOut(session, touched, preExisting);
        throw UciStagingException(
          failedIndex: i,
          cause: e,
          revertedConfigs: backedOut.reverted,
          stillStaged: backedOut.stillStaged,
          revertFailed: backedOut.revertFailed,
        );
      }
    }

    return (
      sections: generatedSections,
      baseline: baseline,
      writtenKeys: writtenKeys,
      ownedSections: ownedSections,
    );
  }

  /// Deletes the uncommitted adds in the baseline that are earlier,
  /// corrected-since attempts at [op] - the same type, about the same thing
  /// by [UciAdd.identity] - calling [onSwept] after each delete, so a
  /// failure part-way leaves what was already deleted accounted for.
  ///
  /// A leftover about something else is somebody's other edit and is left
  /// alone; the apply will name it. [spare] are sections this batch has
  /// already created or adopted, which are never leftovers.
  Future<void> _sweepLeftoverAdds(
    RouterSession session,
    UciChangeSet baseline,
    UciAdd op, {
    required Iterable<String> spare,
    required void Function(String section) onSwept,
    BuildContext? context,
  }) async {
    final identity = op.identity;
    if (identity.isEmpty) return;
    final wanted = {
      for (final option in identity) option: op.values[option]?.toString(),
    };
    final primary = wanted[identity.first];
    if (primary == null || primary.isEmpty) return;
    final rows = baseline.forConfig(op.config);
    for (final section in baseline.addedSections(op.config, op.type)) {
      if (spare.contains(section)) continue;
      final staged = _stagedOptions(rows, section);
      final same = identity.every((option) => staged[option] == wanted[option]);
      if (!same) continue;
      Logger.info('Deleting leftover staged ${op.config} section $section');
      await _api.uciDelete(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        config: op.config,
        section: section,
        context: context?.mounted == true ? context : null,
      );
      onSwept(section);
    }
  }

  /// The section of a staged anonymous add in [baseline] whose type and
  /// values are exactly [op]'s, or null.
  static String? _identicalStagedAdd(
    UciChangeSet baseline,
    UciAdd op, {
    required Set<String> spare,
  }) {
    final rows = baseline.forConfig(op.config);
    final wanted = {
      for (final e in op.values.entries)
        if (e.value != null) e.key: _valueKey(e.value),
    };
    for (final section in baseline.addedSections(op.config, op.type)) {
      if (spare.contains(section)) continue;
      final staged = _stagedValues(
        rows,
        section,
      ).map((k, v) => MapEntry(k, _valueKey(v)));
      if (mapEquals(staged, wanted)) return section;
    }
    return null;
  }

  /// A comparable form of an option value: a list, as staged by one
  /// `list-add` row per entry, in the order given; anything else as text.
  static String _valueKey(Object value) =>
      value is List ? value.map((e) => e.toString()).join('\x00') : '$value';

  /// The options staged on [section]: a `set` row's value, last one wins,
  /// or the entries of the `list-add` rows for a list option.
  static Map<String, Object> _stagedValues(
    List<UciChange> rows,
    String section,
  ) {
    final out = <String, Object>{};
    for (final r in rows) {
      if (r.section != section || r.option == null) continue;
      switch (r.op) {
        case UciOp.set:
          out[r.option!] = r.value ?? '';
        case UciOp.listAdd:
          final existing = out[r.option!];
          final list = existing is List<String> ? existing : <String>[];
          out[r.option!] = list..add(r.value ?? '');
        case UciOp.remove:
          out.remove(r.option!);
        default:
          break;
      }
    }
    return out;
  }

  /// The `set` options staged on [section], as text.
  static Map<String, String> _stagedOptions(
    List<UciChange> rows,
    String section,
  ) => {
    for (final e in _stagedValues(rows, section).entries)
      if (e.value is String) e.key: e.value as String,
  };

  /// Discards staged changes for [configs].
  ///
  /// `uci.revert` is not granted by the stock `luci-base` ACL, so this can
  /// fail for a non-root login. Callers that use it for cleanup should treat
  /// a failure as "changes are still staged", not as a crash.
  Future<void> revert(
    RouterSession session,
    Iterable<String> configs, {
    BuildContext? context,
  }) async {
    for (final config in configs) {
      await _api.uciRevert(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        config: config,
        context: context?.mounted == true ? context : null,
      );
    }
  }

  /// Commits everything staged, then confirms before the router's rollback
  /// timer fires.
  ///
  /// [onPhase] is called as the flow advances, with the time left before the
  /// router reverts, so the UI can show a live countdown.
  ///
  /// The caller is responsible for suspending other router traffic for the
  /// duration - `AppState.beginCriticalSection` exists for this. rpcd binds
  /// the pending rollback to the session that called `uci.apply`, so a
  /// concurrent re-login makes `uci.confirm` fail and the change revert.
  Future<ApplyOutcome> apply(
    RouterSession session, {
    ApplyMode mode = ApplyMode.checked,
    Duration timeout = defaultTimeout,
    Set<String>? ours,
    UciChangeSet? baseline,
    Set<String> writtenKeys = const {},
    Set<String> ownedSections = const {},
    bool rollbackVerified = true,
    void Function(ApplyPhase phase, Duration remaining)? onPhase,
    BuildContext? context,
  }) async {
    UciChangeSet staged;
    try {
      staged = await pending(session, context: context);
    } catch (e, stack) {
      Logger.exception('Failed to read pending changes before apply', e, stack);
      // Applying blind would commit whatever is staged - including the
      // unrelated rows the guard below exists to refuse - and a failure
      // after that would have nothing to revert or report. Back out our own
      // staging instead, and say what could not be cleared.
      final backedOut = await _backOut(
        session,
        ours ?? const <String>{},
        baseline?.configs,
      );
      onPhase?.call(ApplyPhase.failed, Duration.zero);
      return ApplyOutcome(
        phase: ApplyPhase.failed,
        applied: const UciChangeSet.empty(),
        stillStaged: backedOut.stillStaged,
        reason: RollbackReason.stateUnknown,
        error: e,
      );
    }

    // `uci.apply` commits everything this session has staged, not just the
    // configs this operation touched. A change left pending by an earlier
    // operation — a failed batch, an edit the user backed out of — would ride
    // along silently. Refusing and naming the configs is recoverable.
    //
    // Measured on OpenWrt 24.10.4: staging is per rpcd session, so this
    // cannot pick up another client's work; `uci.changes` does not report it
    // and our apply leaves it pending.
    //
    // [writtenKeys] and [ownedSections] are what this operation itself just
    // wrote. Baseline rows they cover are our own earlier attempt at the
    // same edit — re-trying one whose failed apply was left staged must not
    // be refused as somebody else's work.
    if (ours != null) {
      final foreign = staged.foreignTo(
        ours,
        baseline: baseline,
        writtenKeys: writtenKeys,
        ownedSections: ownedSections,
      );
      if (foreign.isNotEmpty) {
        Logger.warning(
          'Refusing to apply: unrelated changes still staged in '
          '${foreign.configs.join(", ")}',
        );
        // Our own rows must not stay behind as well: the next apply would
        // find them in its baseline and refuse for them too. Configs that
        // were clean before staging are reverted; the rest, which hold the
        // foreign rows, are left and named.
        final backedOut = await _backOut(session, ours, baseline?.configs);
        onPhase?.call(ApplyPhase.failed, Duration.zero);
        return ApplyOutcome(
          phase: ApplyPhase.failed,
          applied: const UciChangeSet.empty(),
          foreign: foreign,
          stillStaged: backedOut.stillStaged,
          reason: RollbackReason.foreignChanges,
        );
      }
    }

    final rollback = mode == ApplyMode.checked;
    // A rollback that was asked for is counted down, whether or not the
    // grant was measured: the router may well honour it, and a revert
    // arriving with no warning is worse than a countdown that turns out to
    // have been unnecessary. What is *not* claimed on an unmeasured grant
    // is that the revert happened - see [ApplyOutcome.rollbackVerified].
    onPhase?.call(ApplyPhase.applying, rollback ? timeout : Duration.zero);
    try {
      await _api.uciApply(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        rollback: rollback,
        timeoutSeconds: rollback ? timeout.inSeconds : 0,
        context: context?.mounted == true ? context : null,
      );
    } catch (e, stack) {
      Logger.exception('uci.apply failed', e, stack);
      // `uci.revert` is not granted by the stock ACL and reverts one config
      // at a time, so it can be refused outright or stop partway. Whatever
      // it did not clear is still on the router, and the message has to be
      // able to name it rather than just saying "failed".
      final unreverted = await _revertEach(session, staged.configs);
      onPhase?.call(ApplyPhase.failed, Duration.zero);
      return ApplyOutcome(
        phase: ApplyPhase.failed,
        applied: staged,
        stillStaged: unreverted,
        reason: RollbackReason.routerRejected,
        error: e,
      );
    }

    if (!rollback) {
      onPhase?.call(ApplyPhase.confirmed, Duration.zero);
      return ApplyOutcome(phase: ApplyPhase.confirmed, applied: staged);
    }

    final startedAt = _clock();
    final deadline = startedAt.add(timeout);
    final hardStop = deadline.subtract(_confirmGuardBand);

    Duration remaining() {
      final left = deadline.difference(_clock());
      return left.isNegative ? Duration.zero : left;
    }

    onPhase?.call(ApplyPhase.awaitingConfirm, remaining());

    // A probe of an unreachable router blocks for its whole timeout, and
    // the backoff after it for longer still. The countdown is meant to
    // explain exactly that wait, so it ticks on its own rather than once
    // per probe.
    final ticker = onPhase == null
        ? null
        : Timer.periodic(const Duration(seconds: 1), (_) {
            onPhase(ApplyPhase.awaitingConfirm, remaining());
          });
    try {
      return await _confirmWithin(
        session,
        staged: staged,
        hardStop: hardStop,
        remaining: remaining,
        onPhase: onPhase,
        rollbackVerified: rollbackVerified,
      );
    } finally {
      ticker?.cancel();
    }
  }

  /// Probes and confirms until [hardStop].
  Future<ApplyOutcome> _confirmWithin(
    RouterSession session, {
    required UciChangeSet staged,
    required DateTime hardStop,
    required Duration Function() remaining,
    required void Function(ApplyPhase phase, Duration remaining)? onPhase,
    required bool rollbackVerified,
  }) async {
    // Give the router a moment to finish reloading services before the first
    // probe; LuCI waits a second for the same reason.
    await _delay(const Duration(seconds: 1));

    var attempt = 0;
    while (_clock().isBefore(hardStop)) {
      onPhase?.call(ApplyPhase.awaitingConfirm, remaining());

      if (await _sessionSurvives(session)) {
        try {
          await _api.uciConfirm(
            session.ipAddress,
            session.sysauth,
            session.useHttps,
          );
          onPhase?.call(ApplyPhase.confirmed, Duration.zero);
          return ApplyOutcome(phase: ApplyPhase.confirmed, applied: staged);
        } catch (e, stack) {
          Logger.exception('uci.confirm failed', e, stack);
          final reason = _classifyConfirmFailure(e);
          if (reason != null) {
            onPhase?.call(ApplyPhase.rolledBack, Duration.zero);
            return ApplyOutcome(
              phase: ApplyPhase.rolledBack,
              applied: staged,
              reason: reason,
              error: e,
              rollbackVerified: rollbackVerified,
            );
          }
          // Transport-level failure: the router may still be coming back.
          // Keep probing until the guard band.
        }
      }

      final backoff = _probeBackoff[attempt.clamp(0, _probeBackoff.length - 1)];
      attempt++;
      // Never sleep past the guard band: a failed probe near the end would
      // otherwise hold the caller well beyond the confirmation window before
      // reporting the rollback.
      final left = hardStop.difference(_clock());
      if (left <= Duration.zero) break;
      await _delay(backoff < left ? backoff : left);
    }

    onPhase?.call(ApplyPhase.rolledBack, Duration.zero);
    return ApplyOutcome(
      phase: ApplyPhase.rolledBack,
      applied: staged,
      reason: RollbackReason.unreachable,
      rollbackVerified: rollbackVerified,
    );
  }

  /// Backs out this app's own staging after a failure.
  ///
  /// Only configs that were clean before we started are reverted: a config
  /// that was already dirty belongs to whoever dirtied it, and `uci.revert`
  /// is config-wide. With [preExisting] unknown nothing is reverted, since a
  /// revert could discard an edit the user still wanted. Whatever was left,
  /// by policy or by refusal, is [stillStaged].
  Future<({Set<String> reverted, Set<String> stillStaged, bool revertFailed})>
  _backOut(
    RouterSession session,
    Set<String> touched,
    Set<String>? preExisting,
  ) async {
    final safeToRevert = preExisting == null
        ? const <String>{}
        : touched.difference(preExisting);
    final leftStaged = touched.difference(safeToRevert);
    if (leftStaged.isNotEmpty) {
      Logger.warning(
        'Leaving ${leftStaged.join(", ")} staged: it had unsaved changes '
        'before this operation began',
      );
    }
    final unreverted = await _revertEach(session, safeToRevert);
    return (
      reverted: safeToRevert.difference(unreverted),
      stillStaged: leftStaged.union(unreverted),
      revertFailed: unreverted.isNotEmpty,
    );
  }

  /// Reverts [configs] one at a time and returns the ones that refused.
  ///
  /// One at a time, because `revert` stops at the first refusal and
  /// reporting every config as still staged would over-report the ones it
  /// had already cleared.
  Future<Set<String>> _revertEach(
    RouterSession session,
    Iterable<String> configs,
  ) async {
    final unreverted = <String>{};
    for (final config in configs) {
      try {
        await revert(session, {config}, context: null);
      } catch (revertError, revertStack) {
        unreverted.add(config);
        Logger.exception(
          'Failed to revert $config after apply error',
          revertError,
          revertStack,
        );
      }
    }
    return unreverted;
  }

  /// Two-stage reachability check: HTTP liveness first (cheap, no
  /// credentials), then an authenticated round-trip proving the session that
  /// called `uci.apply` is still valid.
  Future<bool> _sessionSurvives(RouterSession session) async {
    if (!await _probe.isReachable(session.ipAddress, session.useHttps)) {
      return false;
    }
    try {
      await _api.uciChanges(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
      );
      return true;
    } catch (e) {
      // A permission error here means the session is gone; let the confirm
      // attempt surface it with a precise reason rather than guessing.
      return e is RpcException && e.isAccessDenied;
    }
  }

  /// Maps a confirm failure to a terminal reason, or null when the failure
  /// looks transient and probing should continue.
  static RollbackReason? _classifyConfirmFailure(Object error) {
    if (error is! RpcException) return null;
    if (error.isAccessDenied) return RollbackReason.sessionLost;
    return error.status == 5 ? RollbackReason.deadlineMissed : null;
  }
}

/// Extracts the section id rpcd generated for an anonymous `uci.add`.
String? parseUciAddSection(dynamic envelope) {
  if (envelope is! List || envelope.length < 2) return null;
  final data = envelope[1];
  if (data is Map && data['section'] != null) return data['section'].toString();
  // The mock and some rpcd versions return the bare section name.
  if (data is String && data.isNotEmpty) return data;
  return null;
}
