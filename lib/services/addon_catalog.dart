import 'package:luci_mobile/models/addon_spec.dart';
import 'package:luci_mobile/models/router_capabilities.dart';

/// The add-ons the app knows how to configure.
///
/// Each spec is hand-written rather than derived from the config: the
/// generic UCI editor was ruled out, and only a curated field list can say
/// "Download speed (kbit/s)" instead of `download`, or know that
/// `qdisc` has three answers worth offering.
class AddonCatalog {
  const AddonCatalog._();

  static const sqm = AddonSpec(
    addon: Addon.sqm,
    config: 'sqm',
    sectionType: 'queue',
    titleKey: 'addonSqm',
    subtitleKey: 'addonSqmSubtitle',
    singleSection: false,
    nameOption: 'interface',
    fields: [
      AddonSwitch('enabled', labelKey: 'addonEnabled'),
      AddonNumber(
        'download',
        labelKey: 'addonDownload',
        helpKey: 'addonRateHelp',
        suffix: 'kbit/s',
        max: 10000000,
      ),
      AddonNumber(
        'upload',
        labelKey: 'addonUpload',
        helpKey: 'addonRateHelp',
        suffix: 'kbit/s',
        max: 10000000,
      ),
      AddonChoice(
        'qdisc',
        labelKey: 'addonQdisc',
        helpKey: 'addonQdiscHelp',
        values: ['cake', 'fq_codel', 'codel'],
      ),
      AddonChoice(
        'script',
        labelKey: 'addonSqmScript',
        values: ['piece_of_cake.qos', 'layer_cake.qos', 'simple.qos'],
      ),
    ],
  );

  static const adblock = AddonSpec(
    addon: Addon.adblock,
    config: 'adblock',
    sectionType: 'adblock',
    titleKey: 'addonAdblock',
    subtitleKey: 'addonAdblockSubtitle',
    fields: [
      AddonSwitch('adb_enabled', labelKey: 'addonEnabled'),
      AddonSwitch(
        'adb_safesearch',
        labelKey: 'addonSafeSearch',
        helpKey: 'addonSafeSearchHelp',
      ),
      AddonSwitch(
        'adb_dnsforce',
        labelKey: 'addonForceDns',
        helpKey: 'addonForceDnsHelp',
      ),
      AddonMultiChoice(
        'adb_feed',
        labelKey: 'addonBlocklists',
        helpKey: 'addonBlocklistsHelp',
        // The feeds shipped in adblock's default `adb_feed` set plus the
        // most-recommended extras. A full list would be hundreds of rows.
        values: [
          'adguard',
          'adguard_tracking',
          'certpl',
          'disconnect',
          'easylist',
          'easyprivacy',
          'hagezi_light',
          'hagezi_pro',
          'oisd_big',
          'oisd_small',
          'stevenblack',
          'yoyo',
        ],
      ),
    ],
  );

  static const upnp = AddonSpec(
    addon: Addon.upnp,
    config: 'upnpd',
    sectionType: 'upnpd',
    titleKey: 'addonUpnp',
    subtitleKey: 'addonUpnpSubtitle',
    fields: [
      AddonSwitch('enabled', labelKey: 'addonEnabled'),
      AddonSwitch('enable_upnp', labelKey: 'addonUpnpIgd'),
      AddonSwitch('enable_natpmp', labelKey: 'addonNatPmp'),
      AddonSwitch(
        'secure_mode',
        labelKey: 'addonSecureMode',
        helpKey: 'addonSecureModeHelp',
      ),
    ],
  );

  static const ddns = AddonSpec(
    addon: Addon.ddns,
    config: 'ddns',
    sectionType: 'service',
    titleKey: 'addonDdns',
    subtitleKey: 'addonDdnsSubtitle',
    singleSection: false,
    nameOption: 'domain',
    fields: [
      AddonSwitch('enabled', labelKey: 'addonEnabled'),
      AddonText('domain', labelKey: 'addonDomain'),
      AddonText('lookup_host', labelKey: 'addonLookupHost'),
      AddonText('service_name', labelKey: 'addonProvider'),
      AddonText('username', labelKey: 'addonUsername'),
      AddonText('password', labelKey: 'addonPassword', obscure: true),
    ],
  );

  static const all = [sqm, adblock, upnp, ddns];

  static AddonSpec? of(Addon addon) {
    for (final spec in all) {
      if (spec.addon == addon) return spec;
    }
    return null;
  }

  /// The capability that gates [addon].
  static RouterFeature feature(Addon addon) => switch (addon) {
    Addon.sqm => RouterFeature.sqm,
    Addon.adblock => RouterFeature.adblock,
    Addon.upnp => RouterFeature.upnp,
    Addon.ddns => RouterFeature.ddns,
    Addon.nlbwmon => RouterFeature.trafficAccounting,
  };
}
