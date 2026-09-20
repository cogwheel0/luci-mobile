import 'package:flutter/widgets.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router_capabilities.dart';

/// Turns a capability verdict into something a user can act on.
///
/// The four reasons are genuinely different and must not be collapsed into
/// one "unavailable" message: a missing package tells the user what to
/// install, a permission problem tells them to sign in differently, and a
/// failed probe tells them we simply do not know yet. Saying "requires an
/// administrator account" when the router has no Wi-Fi hardware sends someone
/// looking for a problem that does not exist.
extension FeatureAvailabilityText on FeatureAvailability {
  /// Why this feature is not on offer, or null when it is.
  String? explain(BuildContext context) {
    if (available) return null;
    final l10n = context.l10n;
    return switch (reason) {
      UnavailableReason.missingPackage => l10n.requiresPackage(
        requiredPackage ?? '?',
      ),
      UnavailableReason.noPermission => l10n.requiresAdministrator,
      UnavailableReason.probeFailed => l10n.capabilityCheckFailed,
      UnavailableReason.notProbed => null,
      null => null,
    };
  }

  /// The subtitle for a hub entry: the reason when gated, [whenAvailable]
  /// otherwise.
  String subtitle(BuildContext context, String whenAvailable) =>
      explain(context) ?? whenAvailable;
}
