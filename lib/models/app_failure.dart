import 'package:flutter/foundation.dart';

/// What went wrong, for a failure raised where there is no `BuildContext`.
///
/// `AppState` runs away from the widget tree, so it cannot word anything:
/// it says what failed and carries the error that caused it, and the
/// screen that shows the failure puts it into the user's language. Before
/// this, every one of these was an English sentence built in `AppState` and
/// displayed verbatim, whatever the device's locale.
enum AppFailureKind {
  /// Signing in was refused, or the router could not be reached.
  login,

  /// The dashboard's own read failed.
  fetch,

  /// Switching a radio on or off failed.
  wifiToggle,

  /// Restarting a radio failed.
  radioRestart,

  /// The radio is disabled, so there is nothing to restart.
  radioDisabledForRestart,

  /// The radio is disabled, so it cannot join a network.
  radioDisabledForConnect,

  /// Joining a wireless network failed.
  wifiConnect,

  /// Switching an interface on or off failed.
  interfaceToggle,

  /// Changing an interface failed.
  interfaceModify,

  /// Deleting an interface failed.
  interfaceDelete,

  /// The change was made, but reloading wireless afterwards was not.
  wirelessReload,
}

/// A failure the dashboard shows, in a form that can still be translated.
@immutable
class AppFailure {
  const AppFailure(this.kind, {this.subject, this.cause});

  final AppFailureKind kind;

  /// What it is about: a radio name, an SSID. Not translated - it is the
  /// router's own name for the thing.
  final String? subject;

  /// The error underneath, when there was one. Worded by `apiErrorText`.
  final Object? cause;

  @override
  String toString() =>
      'AppFailure(${kind.name}'
      '${subject == null ? '' : ', $subject'}'
      '${cause == null ? '' : ': $cause'})';
}
