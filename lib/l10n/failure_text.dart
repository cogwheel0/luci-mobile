import 'package:flutter/widgets.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/app_failure.dart';
import 'package:luci_mobile/services/api_service.dart';

/// The wording for failures raised where there is no `BuildContext`.
///
/// What failed is decided next to the code that failed - `describeApiError`
/// with the wire protocol, [AppFailure] in `AppState`. How to say it
/// lives here, with the other strings, so every locale gets it.

/// What to tell the user about a router call that failed, in their language.
///
/// The classification lives with the wire protocol, in `describeApiError`;
/// this is only the wording. Two things stay untranslated because nothing
/// else is true: the `object.method` that failed, and any explanation the
/// router itself gave.
String apiErrorText(BuildContext context, Object error) {
  final l10n = context.l10n;
  final info = describeApiError(error);
  return switch (info.kind) {
    ApiErrorKind.sessionRejected => l10n.errorSessionRejected,
    ApiErrorKind.noPermission => l10n.errorNoPermission(info.call ?? '?'),
    ApiErrorKind.missingPackage => l10n.errorMissingPackage(
      info.call ?? '?',
      info.package ?? '?',
    ),
    ApiErrorKind.httpStatus => l10n.errorHttpStatus(info.status ?? 0),
    ApiErrorKind.unreachable => l10n.errorUnreachable,
    ApiErrorKind.rpcFailed =>
      info.detail == null || info.detail!.isEmpty
          ? l10n.errorRpcFailed(info.call ?? '?')
          : l10n.errorRpcFailedBecause(info.call ?? '?', info.detail!),
    // The exception's own message is the only thing there is to show.
    ApiErrorKind.other => info.detail ?? l10n.errorUnreachable,
  };
}

/// What to tell the user about a [AppFailure].
///
/// The sentence says what the app was doing; the cause, when there is one,
/// says what the router answered. Both are needed: "Could not restart the
/// radio" alone does not say why, and the router's answer alone does not
/// say what it was answering.
String appFailureText(BuildContext context, AppFailure failure) {
  final l10n = context.l10n;
  final subject = failure.subject ?? '?';
  final sentence = switch (failure.kind) {
    AppFailureKind.login => l10n.appFailureLogin,
    AppFailureKind.fetch => l10n.appFailureFetch,
    AppFailureKind.wifiToggle => l10n.appFailureWifiToggle,
    AppFailureKind.radioRestart => l10n.appFailureRadioRestart,
    AppFailureKind.radioDisabledForRestart =>
      l10n.appFailureRadioDisabledForRestart(subject),
    AppFailureKind.radioDisabledForConnect =>
      l10n.appFailureRadioDisabledForConnect(subject),
    AppFailureKind.wifiConnect => l10n.appFailureWifiConnect(subject),
    AppFailureKind.interfaceToggle => l10n.appFailureInterfaceToggle,
    AppFailureKind.interfaceModify => l10n.appFailureInterfaceModify,
    AppFailureKind.interfaceDelete => l10n.appFailureInterfaceDelete,
    AppFailureKind.wirelessReload => l10n.appFailureWirelessReload,
  };
  final cause = failure.cause;
  if (cause == null) return sentence;
  return '$sentence ${apiErrorText(context, cause)}';
}
