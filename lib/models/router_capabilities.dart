import 'package:flutter/foundation.dart';

/// Something the app can offer only if the router supports it.
enum RouterFeature {
  /// `uci.apply` + `uci.confirm` — the rollback-protected commit path.
  uciApplyRollback,

  /// Static DHCP leases: `dhcp` config plus write access.
  dhcpReservations,

  /// Blocking a client with a `firewall` rule.
  clientBlocking,

  /// Per-station signal and rates from `iwinfo.assoclist`.
  wirelessStations,

  /// `luci-rpc.getHostHints` — hostname/IP hints for clients.
  hostHints,

  /// `system.reboot`.
  reboot,

  /// `iwinfo.scan`.
  wirelessScan,

  /// init.d control via the `rc` ubus object.
  serviceControl,

  /// Hostname and timezone in the `system` config.
  systemSettings,

  /// Waking a device with `etherwake`.
  wakeOnLan,

  /// `luci.getRealtimeStats` — load/traffic/conntrack series.
  realtimeStats,

  /// Per-client traffic accounting (nlbwmon).
  trafficAccounting,

  sqm,
  ddns,
  adblock,
  upnp,
  wireguardServer,
  openvpnServer,
}

/// Why a feature is not offered. The distinction matters: a missing package is
/// not a defect, a denied permission is the user's account, and a failed probe
/// is neither — it means we do not know yet.
enum UnavailableReason {
  /// Capabilities have not been read yet.
  notProbed,

  /// The probe itself failed. Show "couldn't check", never "not supported".
  probeFailed,

  /// The router does not have the package configured.
  missingPackage,

  /// This login is not allowed to perform the operation.
  noPermission,
}

@immutable
class FeatureAvailability {
  const FeatureAvailability.available({this.verified = true})
    : available = true,
      reason = null,
      requiredPackage = null;

  const FeatureAvailability.unavailable(this.reason, {this.requiredPackage})
    : available = false,
      verified = true;

  final bool available;
  final UnavailableReason? reason;

  /// False when [available] rests on a permission that could not be
  /// probed. The feature is offered - hiding every write behind a guess
  /// would be worse - but nothing that *promises* on the strength of it
  /// (a rollback countdown, say) may take the promise as measured.
  final bool verified;

  /// The package to install, when [reason] is [UnavailableReason.missingPackage].
  final String? requiredPackage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureAvailability &&
          other.available == available &&
          other.verified == verified &&
          other.reason == reason &&
          other.requiredPackage == requiredPackage;

  @override
  int get hashCode => Object.hash(available, verified, reason, requiredPackage);

  @override
  String toString() => available
      ? 'FeatureAvailability.available(${verified ? '' : 'verified: false'})'
      : 'FeatureAvailability.unavailable(${reason?.name}'
            '${requiredPackage == null ? '' : ', $requiredPackage'})';
}

/// What one router supports, as read once per session.
///
/// [of] is a pure function of this data, so the rules are unit-testable
/// without any I/O.
@immutable
class RouterCapabilities {
  const RouterCapabilities({
    this.uciConfigs = const <String>{},
    this.features = const <String, dynamic>{},
    this.ubusAcl,
    this.unprobedFunctions = const <String>{},
    this.probeFailed = false,
    this.probedAt,
  });

  /// Nothing read yet — every feature reports [UnavailableReason.notProbed].
  static const RouterCapabilities unknown = RouterCapabilities();

  /// Every config present on the router (`uci.configs`). A cheap proxy for
  /// "is this package installed".
  final Set<String> uciConfigs;

  /// The raw `luci.getFeatures` map (`firewall4`, `ipv6`, `wifi`, `opkg`, …).
  final Map<String, dynamic> features;

  /// ubus object -> permitted functions, where `*` means all. Null when the
  /// router would not tell us, in which case permission checks are treated as
  /// "probably allowed" rather than blocking the UI on a guess.
  final Map<String, Set<String>>? ubusAcl;

  /// `object.function` pairs the per-function fallback could not get an
  /// answer for. Only ever populated alongside a fallback-built [ubusAcl],
  /// where an absent function would otherwise read as a measured denial —
  /// and a measured denial of `uci.rollback` is what makes the app commit
  /// without rollback protection.
  final Set<String> unprobedFunctions;

  /// True when the probe could not be completed.
  final bool probeFailed;

  final DateTime? probedAt;

  bool get isProbed => probedAt != null || probeFailed;

  /// Whether this login may call `object.function`.
  ///
  /// Returns true when the ACL is unknown: a router that will not report its
  /// ACL should not have every write hidden. The call itself will surface a
  /// permission error if it really is denied.
  ///
  /// rpcd matches the object names in an ACL with `fnmatch`, so a grant on
  /// `network.*` covers `network.interface`, and the common "full access"
  /// recipe grants `*`. Function names are matched the same way.
  bool allows(String object, String function) {
    final acl = ubusAcl;
    if (acl == null) return true;
    if (unprobedFunctions.contains('$object.$function')) return true;
    for (final entry in acl.entries) {
      if (!globMatches(entry.key, object)) continue;
      if (entry.value.any((fn) => globMatches(fn, function))) return true;
    }
    return false;
  }

  /// `fnmatch`-style matching: `*` for any run, `?` for one character.
  ///
  /// Called for every ACL entry on every feature check, which happens on
  /// every rebuild that watches capabilities; so the plain cases return at
  /// once and a pattern is compiled once, not per call.
  @visibleForTesting
  static bool globMatches(String pattern, String value) {
    if (pattern == '*') return true;
    if (!pattern.contains('*') && !pattern.contains('?')) {
      return pattern == value;
    }
    return _globs
        .putIfAbsent(pattern, () {
          final regex = StringBuffer('^');
          for (final ch in pattern.split('')) {
            regex.write(switch (ch) {
              '*' => '.*',
              '?' => '.',
              _ => RegExp.escape(ch),
            });
          }
          regex.write(r'$');
          return RegExp(regex.toString());
        })
        .hasMatch(value);
  }

  static final Map<String, RegExp> _globs = {};

  /// A boolean out of `luci.getFeatures`, or null when it was not reported.
  bool? feature(String name) {
    final value = features[name];
    if (value is bool) return value;
    if (value is num) return value != 0;
    return null;
  }

  bool get hasFirewall =>
      uciConfigs.contains('firewall') &&
      (feature('firewall4') ?? feature('firewall') ?? true);

  bool get usesApk => feature('apk') ?? false;

  FeatureAvailability of(RouterFeature target) {
    if (!isProbed) {
      return const FeatureAvailability.unavailable(UnavailableReason.notProbed);
    }
    if (probeFailed) {
      return const FeatureAvailability.unavailable(
        UnavailableReason.probeFailed,
      );
    }

    switch (target) {
      case RouterFeature.uciApplyRollback:
        // `rollback` is included deliberately. Measured on stock OpenWrt
        // 24.10: `apply` and `confirm` are granted but `rollback` is not, and
        // in that configuration an unconfirmed apply was NOT reverted when the
        // timer expired - it stayed committed. Treating apply+confirm alone as
        // "rollback protected" would have the app promise a safety net it
        // cannot demonstrate.
        return _requireUbus('uci', const ['apply', 'confirm', 'rollback']);

      case RouterFeature.dhcpReservations:
        return _requireConfig('dhcp', 'dnsmasq', write: true);

      case RouterFeature.clientBlocking:
        if (!hasFirewall) {
          return const FeatureAvailability.unavailable(
            UnavailableReason.missingPackage,
            requiredPackage: 'firewall4',
          );
        }
        return _requireUbus('uci', const ['set']);

      // Station details and scanning are separately authorised RPCs. Gating
      // both on both meant an account granted just one lost the feature it
      // was actually allowed to use.
      case RouterFeature.wirelessStations:
      case RouterFeature.wirelessScan:
        if (feature('wifi') == false) {
          return const FeatureAvailability.unavailable(
            UnavailableReason.missingPackage,
            requiredPackage: 'wpad',
          );
        }
        return _requireUbus('iwinfo', [
          target == RouterFeature.wirelessScan ? 'scan' : 'assoclist',
        ]);

      case RouterFeature.hostHints:
        return _requireUbus('luci-rpc', const ['getHostHints']);

      case RouterFeature.reboot:
        return _requireUbus('system', const ['reboot']);

      case RouterFeature.serviceControl:
        return _requireUbus('rc', const ['init']);

      case RouterFeature.wakeOnLan:
        // `luci-app-wol` is what grants `file.exec` on the etherwake path;
        // the `etherwake` binary alone is not reachable over rpcd.
        return _requireConfig('etherwake', 'luci-app-wol');

      case RouterFeature.systemSettings:
        // `system` is part of the base install, so the only real question is
        // whether this login may write it.
        return _requireUbus('uci', const ['set']);

      case RouterFeature.realtimeStats:
        return _requireUbus('luci', const ['getRealtimeStats']);

      case RouterFeature.trafficAccounting:
        return _requireConfig('nlbwmon', 'nlbwmon');
      case RouterFeature.sqm:
        return _requireConfig('sqm', 'sqm-scripts', write: true);
      case RouterFeature.ddns:
        return _requireConfig('ddns', 'ddns-scripts', write: true);
      case RouterFeature.adblock:
        return _requireConfig('adblock', 'adblock', write: true);
      case RouterFeature.upnp:
        return _requireConfig('upnpd', 'miniupnpd', write: true);
      case RouterFeature.wireguardServer:
        return _requireConfig('network', 'wireguard-tools', write: true);
      case RouterFeature.openvpnServer:
        return _requireConfig('openvpn', 'openvpn-openssl', write: true);
    }
  }

  FeatureAvailability _requireConfig(
    String config,
    String package, {
    bool write = false,
  }) {
    if (!uciConfigs.contains(config)) {
      return FeatureAvailability.unavailable(
        UnavailableReason.missingPackage,
        requiredPackage: package,
      );
    }
    if (write) return _requireUbus('uci', const ['set']);
    return const FeatureAvailability.available();
  }

  FeatureAvailability _requireUbus(String object, List<String> functions) {
    // No ACL at all: permitted by assumption, and known to be one.
    var verified = ubusAcl != null;
    for (final fn in functions) {
      if (!allows(object, fn)) {
        return const FeatureAvailability.unavailable(
          UnavailableReason.noPermission,
        );
      }
      if (unprobedFunctions.contains('$object.$fn')) verified = false;
    }
    return FeatureAvailability.available(verified: verified);
  }

  RouterCapabilities copyWith({
    Set<String>? uciConfigs,
    Map<String, dynamic>? features,
    Map<String, Set<String>>? ubusAcl,
    Set<String>? unprobedFunctions,
    bool? probeFailed,
    DateTime? probedAt,
  }) => RouterCapabilities(
    uciConfigs: uciConfigs ?? this.uciConfigs,
    features: features ?? this.features,
    ubusAcl: ubusAcl ?? this.ubusAcl,
    unprobedFunctions: unprobedFunctions ?? this.unprobedFunctions,
    probeFailed: probeFailed ?? this.probeFailed,
    probedAt: probedAt ?? this.probedAt,
  );
}
