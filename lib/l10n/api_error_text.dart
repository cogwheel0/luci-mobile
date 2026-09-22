import 'package:flutter/widgets.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/services/api_service.dart';

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
