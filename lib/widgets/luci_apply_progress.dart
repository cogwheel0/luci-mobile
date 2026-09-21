import 'dart:async';

import 'package:flutter/material.dart';

import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';

/// Live state of an in-flight apply, pushed in from the changeset service.
class ApplyProgress extends ChangeNotifier {
  ApplyPhase _phase = ApplyPhase.applying;
  Duration _remaining = Duration.zero;

  ApplyPhase get phase => _phase;
  Duration get remaining => _remaining;

  void update(ApplyPhase phase, Duration remaining) {
    if (phase == _phase && remaining == _remaining) return;
    _phase = phase;
    _remaining = remaining;
    notifyListeners();
  }
}

/// The dialog shown while a change is being applied.
///
/// The countdown is the point of this screen. `uci.apply` starts a timer on
/// the router; if the app cannot reach it again and confirm before that timer
/// expires, the router puts the old configuration back. Telling the user
/// exactly that — and how long is left — is what makes changing a router's
/// configuration from a phone feel defensible rather than frozen.
class LuciApplyProgressDialog extends StatelessWidget {
  const LuciApplyProgressDialog({super.key, required this.progress});

  final ApplyProgress progress;

  /// Shows the dialog and keeps it up until [work] settles.
  ///
  /// Returns whatever [work] produced.
  static Future<T> run<T>(
    BuildContext context, {
    required ApplyProgress progress,
    required Future<T> Function() work,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => LuciApplyProgressDialog(progress: progress),
      ).then((_) => dialogOpen = false),
    );
    try {
      return await work();
    } finally {
      if (dialogOpen && navigator.canPop()) navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Backing out mid-apply would leave the rollback unconfirmed and the
      // change silently reverted a minute later.
      canPop: false,
      child: AlertDialog(
        content: ListenableBuilder(
          listenable: progress,
          builder: (context, _) {
            final seconds = progress.remaining.inSeconds;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: LuciSpacing.md),
                    Expanded(
                      child: Text(
                        _title(context, progress.phase),
                        style: LuciTextStyles.cardTitle(context),
                      ),
                    ),
                  ],
                ),
                if (progress.phase == ApplyPhase.awaitingConfirm &&
                    seconds > 0) ...[
                  const SizedBox(height: LuciSpacing.md),
                  Text(
                    context.l10n.revertsInSeconds(seconds),
                    style: LuciTextStyles.cardSubtitle(context),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  static String _title(BuildContext context, ApplyPhase phase) =>
      switch (phase) {
        ApplyPhase.awaitingConfirm => context.l10n.confirmingChange,
        _ => context.l10n.applying,
      };
}

/// What to tell the user about an apply that has finished.
///
/// Shared by every configuration screen: when each kept its own copy, a new
/// outcome had to be remembered in five places, and the wording drifted.
String applyOutcomeMessage(BuildContext context, ApplyOutcome? outcome) {
  final l10n = context.l10n;
  if (outcome == null) return l10n.changeFailed;
  return switch (outcome.phase) {
    ApplyPhase.confirmed => l10n.changeApplied,
    ApplyPhase.rolledBack =>
      outcome.reason == RollbackReason.deadlineMissed
          ? l10n.changeUnconfirmed
          : l10n.changeRolledBack,
    // Naming the configs matters: the user has to go and deal with them in
    // LuCI, and "something is staged somewhere" is not actionable.
    _ when outcome.reason == RollbackReason.foreignChanges =>
      l10n.changeBlockedByOthers(outcome.foreign.configs.join(', ')),
    // A failure that could not clean up after itself leaves work on the
    // router. Saying only "failed" hides that there is something to undo.
    _ when outcome.stillStaged.isNotEmpty => l10n.changeLeftStaged(
      outcome.stillStaged.join(', '),
    ),
    _ => l10n.changeFailed,
  };
}
