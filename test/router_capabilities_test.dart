import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/router_capabilities.dart';

/// A fully-permitted root login on a stock modern build.
RouterCapabilities _stock({
  Set<String>? configs,
  Map<String, dynamic>? features,
  Map<String, Set<String>>? acl,
}) => RouterCapabilities(
  uciConfigs:
      configs ?? const {'dhcp', 'firewall', 'network', 'system', 'wireless'},
  features: features ?? const {'firewall4': true, 'wifi': true, 'ipv6': true},
  ubusAcl:
      acl ??
      const {
        'uci': {'*'},
        'system': {'*'},
        'iwinfo': {'*'},
        'luci-rpc': {'*'},
        'luci': {'*'},
        'rc': {'*'},
      },
  probedAt: null,
).copyWith(probedAt: DateTime.utc(2026, 1, 1));

void main() {
  _iwinfoDecoupling();

  group('probe lifecycle', () {
    test('an unprobed router reports notProbed, not unsupported', () {
      for (final f in RouterFeature.values) {
        final a = RouterCapabilities.unknown.of(f);
        expect(a.available, isFalse);
        expect(a.reason, UnavailableReason.notProbed, reason: f.name);
      }
    });

    // "Couldn't check" and "not supported" must never be conflated: a flaky
    // network would otherwise permanently hide features.
    test('a failed probe reports probeFailed, not missingPackage', () {
      final caps = RouterCapabilities(
        probeFailed: true,
        probedAt: DateTime.utc(2026),
      );
      expect(caps.of(RouterFeature.sqm).reason, UnavailableReason.probeFailed);
      expect(
        caps.of(RouterFeature.dhcpReservations).reason,
        UnavailableReason.probeFailed,
      );
    });
  });

  group('package gating', () {
    test('a stock router supports the Phase 1 write features', () {
      final caps = _stock();
      expect(caps.of(RouterFeature.uciApplyRollback).available, isTrue);
      expect(caps.of(RouterFeature.dhcpReservations).available, isTrue);
      expect(caps.of(RouterFeature.clientBlocking).available, isTrue);
      expect(caps.of(RouterFeature.hostHints).available, isTrue);
      expect(caps.of(RouterFeature.wirelessStations).available, isTrue);
    });

    test('an absent config reports the package to install', () {
      final caps = _stock();
      final sqm = caps.of(RouterFeature.sqm);
      expect(sqm.available, isFalse);
      expect(sqm.reason, UnavailableReason.missingPackage);
      expect(sqm.requiredPackage, 'sqm-scripts');

      expect(
        caps.of(RouterFeature.trafficAccounting).requiredPackage,
        'nlbwmon',
      );
      expect(caps.of(RouterFeature.adblock).requiredPackage, 'adblock');
      expect(caps.of(RouterFeature.upnp).requiredPackage, 'miniupnpd');
    });

    test('installed optional packages become available', () {
      final caps = _stock(
        configs: const {'dhcp', 'firewall', 'network', 'sqm', 'nlbwmon'},
      );
      expect(caps.of(RouterFeature.sqm).available, isTrue);
      expect(caps.of(RouterFeature.trafficAccounting).available, isTrue);
    });

    // A dumb AP has no dhcp config; reservations must hide rather than error.
    test('a router without a dhcp config cannot do reservations', () {
      final caps = _stock(configs: const {'network', 'wireless', 'system'});
      final r = caps.of(RouterFeature.dhcpReservations);
      expect(r.reason, UnavailableReason.missingPackage);
      expect(r.requiredPackage, 'dnsmasq');
    });

    test('a wired-only build hides wireless features', () {
      final caps = _stock(features: const {'firewall4': true, 'wifi': false});
      expect(
        caps.of(RouterFeature.wirelessStations).reason,
        UnavailableReason.missingPackage,
      );
      expect(
        caps.of(RouterFeature.wirelessScan).reason,
        UnavailableReason.missingPackage,
      );
    });

    test('no firewall config blocks client blocking', () {
      final caps = _stock(configs: const {'dhcp', 'network'});
      final b = caps.of(RouterFeature.clientBlocking);
      expect(b.reason, UnavailableReason.missingPackage);
      expect(b.requiredPackage, 'firewall4');
    });
  });

  group('permission gating', () {
    test('a denied ubus function reports noPermission', () {
      final caps = _stock(
        acl: const {
          'uci': {'get', 'changes'}, // read-only login
          'system': {'reboot'},
        },
      );
      expect(
        caps.of(RouterFeature.uciApplyRollback).reason,
        UnavailableReason.noPermission,
      );
      expect(
        caps.of(RouterFeature.dhcpReservations).reason,
        UnavailableReason.noPermission,
      );
      expect(caps.of(RouterFeature.reboot).available, isTrue);
    });

    // uci.apply needs *both* apply and confirm; granting only one is useless
    // because the change would always roll back.
    test('apply without confirm does not count as rollback support', () {
      final caps = _stock(
        acl: const {
          'uci': {'set', 'apply'},
        },
      );
      expect(
        caps.of(RouterFeature.uciApplyRollback).reason,
        UnavailableReason.noPermission,
      );
    });

    test('the wildcard grants every function on an object', () {
      final caps = _stock(
        acl: const {
          'uci': {'*'},
        },
      );
      expect(caps.allows('uci', 'apply'), isTrue);
      expect(caps.allows('uci', 'anything-at-all'), isTrue);
      expect(caps.allows('iwinfo', 'scan'), isFalse);
    });

    // A router that will not report its ACL should not have every write
    // hidden - the call itself will surface a permission error if denied.
    // rpcd matches ACL object names with fnmatch: the common "full access"
    // recipe grants `*`, and `network.*` covers `network.interface`.
    test('ACL object names are matched as globs', () {
      const caps = RouterCapabilities(
        uciConfigs: {'dhcp', 'firewall'},
        ubusAcl: {
          '*': {'*'},
        },
        probedAt: null,
      );
      expect(caps.allows('uci', 'set'), isTrue);
      expect(caps.allows('anything', 'at-all'), isTrue);

      const scoped = RouterCapabilities(
        ubusAcl: {
          'network.*': {'status', 'dump'},
          'uci': {'get'},
        },
      );
      expect(scoped.allows('network.interface', 'dump'), isTrue);
      expect(scoped.allows('network.interface', 'up'), isFalse);
      expect(scoped.allows('uci', 'set'), isFalse);
      expect(RouterCapabilities.globMatches('luci-rpc', 'luci-rpc'), isTrue);
      expect(RouterCapabilities.globMatches('luci?rpc', 'luci-rpc'), isTrue);
      expect(RouterCapabilities.globMatches('luci', 'luci-rpc'), isFalse);
    });

    test('an unknown ACL assumes permitted rather than guessing', () {
      final caps = RouterCapabilities(
        uciConfigs: const {'dhcp', 'firewall'},
        features: const {'firewall4': true, 'wifi': true},
        probedAt: DateTime.utc(2026),
      );
      expect(caps.allows('uci', 'apply'), isTrue);
      expect(caps.of(RouterFeature.uciApplyRollback).available, isTrue);
      expect(caps.of(RouterFeature.clientBlocking).available, isTrue);
    });

    test('an object absent from a known ACL is denied', () {
      final caps = _stock(
        acl: const {
          'uci': {'*'},
        },
      );
      expect(caps.allows('rc', 'init'), isFalse);
      expect(
        caps.of(RouterFeature.serviceControl).reason,
        UnavailableReason.noPermission,
      );
    });
  });

  group('feature map', () {
    test('reads booleans and numeric truthiness, null when absent', () {
      final caps = _stock(
        features: const {'firewall4': true, 'swconfig': 0, 'zram': 1},
      );
      expect(caps.feature('firewall4'), isTrue);
      expect(caps.feature('swconfig'), isFalse);
      expect(caps.feature('zram'), isTrue);
      expect(caps.feature('nonexistent'), isNull);
    });

    test('usesApk distinguishes apk from opkg builds', () {
      expect(_stock(features: const {'apk': true}).usesApk, isTrue);
      expect(_stock(features: const {'opkg': true}).usesApk, isFalse);
    });
  });
}

void _iwinfoDecoupling() {
  // Station details and scanning are separately authorised RPCs. Gating both
  // on both meant an account granted one lost the feature it was allowed to
  // use.
  group('wireless permissions are independent', () {
    RouterCapabilities withIwinfo(Set<String> granted) => RouterCapabilities(
      ubusAcl: {'iwinfo': granted},
      probedAt: DateTime(2026),
    );

    test('assoclist alone still unlocks station details', () {
      final caps = withIwinfo({'assoclist'});
      expect(caps.of(RouterFeature.wirelessStations).available, isTrue);
      expect(
        caps.of(RouterFeature.wirelessScan).reason,
        UnavailableReason.noPermission,
      );
    });

    test('scan alone still unlocks scanning', () {
      final caps = withIwinfo({'scan'});
      expect(caps.of(RouterFeature.wirelessScan).available, isTrue);
      expect(
        caps.of(RouterFeature.wirelessStations).reason,
        UnavailableReason.noPermission,
      );
    });

    test('neither granted leaves both unavailable', () {
      final caps = withIwinfo(const {});
      expect(caps.of(RouterFeature.wirelessScan).available, isFalse);
      expect(caps.of(RouterFeature.wirelessStations).available, isFalse);
    });
  });
}
