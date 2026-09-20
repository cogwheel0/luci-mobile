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
}

@immutable
class ApplyOutcome {
  const ApplyOutcome({
    required this.phase,
    required this.applied,
    this.reason,
    this.error,
  });

  final ApplyPhase phase;

  /// What was staged at the moment the apply began.
  final UciChangeSet applied;

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
    this.revertFailed = false,
  });

  final int failedIndex;
  final Object cause;
  final Set<String> revertedConfigs;

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
  Future<Map<int, String>> stage(
    RouterSession session,
    List<UciOperation> ops, {
    BuildContext? context,
  }) async {
    final generatedSections = <int, String>{};
    final touched = <String>{};

    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      try {
        touched.add(op.config);
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
        }
      } catch (e, stack) {
        Logger.exception('Failed to stage UCI operation $i', e, stack);
        var revertFailed = false;
        try {
          await revert(
            session,
            touched,
            context: context?.mounted == true ? context : null,
          );
        } catch (revertError, revertStack) {
          revertFailed = true;
          Logger.exception(
            'Failed to revert after staging error',
            revertError,
            revertStack,
          );
        }
        throw UciStagingException(
          failedIndex: i,
          cause: e,
          revertedConfigs: touched,
          revertFailed: revertFailed,
        );
      }
    }

    return generatedSections;
  }

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
    void Function(ApplyPhase phase, Duration remaining)? onPhase,
    BuildContext? context,
  }) async {
    UciChangeSet staged;
    try {
      staged = await pending(session, context: context);
    } catch (e, stack) {
      Logger.exception('Failed to read pending changes before apply', e, stack);
      staged = const UciChangeSet.empty();
    }

    onPhase?.call(ApplyPhase.applying, timeout);

    final rollback = mode == ApplyMode.checked;
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
      try {
        await revert(session, staged.configs, context: null);
      } catch (revertError, revertStack) {
        Logger.exception(
          'Failed to revert after apply error',
          revertError,
          revertStack,
        );
      }
      return ApplyOutcome(
        phase: ApplyPhase.failed,
        applied: staged,
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
            );
          }
          // Transport-level failure: the router may still be coming back.
          // Keep probing until the guard band.
        }
      }

      final backoff = _probeBackoff[attempt.clamp(0, _probeBackoff.length - 1)];
      attempt++;
      await _delay(backoff);
    }

    onPhase?.call(ApplyPhase.rolledBack, Duration.zero);
    return ApplyOutcome(
      phase: ApplyPhase.rolledBack,
      applied: staged,
      reason: RollbackReason.unreachable,
    );
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
      return e is RpcException && e.status == 6;
    }
  }

  /// Maps a confirm failure to a terminal reason, or null when the failure
  /// looks transient and probing should continue.
  static RollbackReason? _classifyConfirmFailure(Object error) {
    if (error is! RpcException) return null;
    switch (error.status) {
      case 6:
        return RollbackReason.sessionLost;
      case 5:
        return RollbackReason.deadlineMissed;
      default:
        return null;
    }
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
