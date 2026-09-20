import 'package:luci_mobile/l10n/app_localizations.dart';

/// Resolves the string keys held in `AddonSpec` to translated text.
///
/// `AddonSpec` is `const` and holds no BuildContext, so its labels are keys.
/// This switch is hand-written rather than reflective so a key that has no
/// translation is a compile error, not a runtime blank.
extension AddonStrings on AppLocalizations {
  String string(String key) => switch (key) {
    'addonSqm' => addonSqm,
    'addonSqmSubtitle' => addonSqmSubtitle,
    'addonAdblock' => addonAdblock,
    'addonAdblockSubtitle' => addonAdblockSubtitle,
    'addonUpnp' => addonUpnp,
    'addonUpnpSubtitle' => addonUpnpSubtitle,
    'addonDdns' => addonDdns,
    'addonDdnsSubtitle' => addonDdnsSubtitle,
    'addonEnabled' => addonEnabled,
    'addonDownload' => addonDownload,
    'addonUpload' => addonUpload,
    'addonRateHelp' => addonRateHelp,
    'addonQdisc' => addonQdisc,
    'addonQdiscHelp' => addonQdiscHelp,
    'addonSqmScript' => addonSqmScript,
    'addonSafeSearch' => addonSafeSearch,
    'addonSafeSearchHelp' => addonSafeSearchHelp,
    'addonForceDns' => addonForceDns,
    'addonForceDnsHelp' => addonForceDnsHelp,
    'addonBlocklists' => addonBlocklists,
    'addonBlocklistsHelp' => addonBlocklistsHelp,
    'addonUpnpIgd' => addonUpnpIgd,
    'addonNatPmp' => addonNatPmp,
    'addonSecureMode' => addonSecureMode,
    'addonSecureModeHelp' => addonSecureModeHelp,
    'addonDomain' => addonDomain,
    'addonLookupHost' => addonLookupHost,
    'addonProvider' => addonProvider,
    'addonUsername' => addonUsername,
    'addonPassword' => addonPassword,
    // Unreachable for any key in AddonCatalog; the test pins that.
    _ => key,
  };
}
