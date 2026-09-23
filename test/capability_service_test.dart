import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/capability_service.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/state/router_session.dart';

const _session = RouterSession(
  routerId: 'r1',
  ipAddress: '192.168.1.1',
  sysauth: 'sid-abc',
  useHttps: false,
  token: 1,
);

class _ProbeApi extends MockApiService {
  final List<String> calls = <String>[];

  List<String>? configs = const ['dhcp', 'firewall', 'network', 'wireless'];
  Map<String, dynamic>? featureMap = const {'firewall4': true, 'wifi': true};
  Map<String, Set<String>>? acl = const {
    'uci': {'*'},
  };

  Object? configsError;
  Object? featuresError;
  Object? aclError;

  /// Configs this router actually has, for the per-config fallback.
  Set<String> presentConfigs = const {
    'dhcp',
    'firewall',
    'network',
    'wireless',
  };

  /// session.access answers, keyed "object.function". Missing means denied.
  Set<String> accessGrants = const {};
  bool accessErrors = false;

  /// Probes that throw, keyed "object.function".
  Set<String> accessErrorsFor = const {};

  int get accessCalls => calls.where((c) => c.startsWith('access ')).length;

  @override
  Future<List<String>> uciConfigs(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    calls.add('configs');
    if (configsError != null) throw configsError!;
    return configs!;
  }

  @override
  Future<dynamic> uciGetAll(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    calls.add('get $config');
    if (!presentConfigs.contains(config)) {
      throw RpcException(
        object: 'uci',
        method: 'get',
        status: 4,
        detail: config,
      );
    }
    return [
      0,
      {'values': <String, dynamic>{}},
    ];
  }

  @override
  Future<Map<String, dynamic>> luciGetFeatures(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    calls.add('features');
    if (featuresError != null) throw featuresError!;
    return featureMap!;
  }

  @override
  Future<Map<String, Set<String>>?> fetchSessionAcl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    calls.add('acl');
    if (aclError != null) throw aclError!;
    return acl;
  }

  @override
  Future<bool?> checkUbusAccess(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String function,
    BuildContext? context,
  }) async {
    calls.add('access $object.$function');
    if (accessErrors || accessErrorsFor.contains('$object.$function')) {
      throw Exception('denied');
    }
    return accessGrants.contains('$object.$function');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CapabilityService build(_ProbeApi api) =>
      CapabilityService(api, clock: () => DateTime.utc(2026, 1, 1));

  group('happy path', () {
    test('costs exactly three RPCs and no per-function probes', () async {
      final api = _ProbeApi();

      final caps = await build(api).probe(_session);

      expect(api.calls, ['configs', 'features', 'acl']);
      expect(api.accessCalls, 0);
      expect(caps.isProbed, isTrue);
      expect(caps.probeFailed, isFalse);
      expect(caps.uciConfigs, {'dhcp', 'firewall', 'network', 'wireless'});
      expect(caps.feature('firewall4'), isTrue);
      expect(caps.allows('uci', 'apply'), isTrue);
    });
  });

  group('degradation', () {
    // Only when *both* routes to the config list fail have we genuinely
    // learned nothing; reporting every package-gated feature as missing would
    // be worse than admitting that.
    test('the probe fails only when every config read also fails', () async {
      final api = _ProbeApi()
        ..configsError = Exception('timeout')
        ..presentConfigs = const {};

      final caps = await build(api).probe(_session);

      expect(caps.probeFailed, isTrue);
      expect(caps.of(RouterFeature.sqm).reason, UnavailableReason.probeFailed);
    });

    // rpcd-mod-ucode is absent on some builds; that must not fail the probe.
    test(
      'a missing luci.getFeatures still yields usable capabilities',
      () async {
        final api = _ProbeApi()
          ..featuresError = const RpcException(
            object: 'luci',
            method: 'getFeatures',
            status: 4,
          );

        final caps = await build(api).probe(_session);

        expect(caps.probeFailed, isFalse);
        expect(caps.features, isEmpty);
        expect(caps.feature('wifi'), isNull);
        // firewall gating falls back to the config being present.
        expect(caps.of(RouterFeature.clientBlocking).available, isTrue);
      },
    );

    test('a denied session.list falls back to session.access probes', () async {
      final api = _ProbeApi()
        ..acl = null
        ..accessGrants = const {
          'uci.set',
          'uci.apply',
          'uci.confirm',
          'uci.rollback',
          'system.reboot',
        };

      final caps = await build(api).probe(_session);

      expect(api.accessCalls, greaterThan(1));
      expect(caps.probeFailed, isFalse);
      expect(caps.of(RouterFeature.uciApplyRollback).available, isTrue);
      expect(caps.of(RouterFeature.reboot).available, isTrue);
      expect(
        caps.of(RouterFeature.serviceControl).reason,
        UnavailableReason.noPermission,
      );
    });

    // Measured against stock OpenWrt 24.10: a root session gets apply and
    // confirm but NOT rollback, and in that state an unconfirmed apply stayed
    // committed rather than reverting. Reporting rollback protection there
    // would have the app promise a safety net it does not have.
    test('apply+confirm without rollback is not rollback protection', () async {
      final api = _ProbeApi()
        ..acl = const {
          'uci': {'get', 'set', 'add', 'delete', 'changes', 'apply', 'confirm'},
        };

      final caps = await build(api).probe(_session);

      expect(caps.allows('uci', 'apply'), isTrue);
      expect(caps.allows('uci', 'confirm'), isTrue);
      expect(caps.allows('uci', 'rollback'), isFalse);
      expect(
        caps.of(RouterFeature.uciApplyRollback).reason,
        UnavailableReason.noPermission,
      );
      // The plain writes stay available - only the safety claim is withdrawn.
      expect(caps.of(RouterFeature.dhcpReservations).available, isTrue);
    });

    // Measured on stock OpenWrt 24.10: a root LuCI session is granted uci
    // get/set/add/delete/changes/apply/confirm but NOT `configs`. Failing the
    // whole probe on that would report every package-backed feature as
    // "couldn't check" on a default install.
    test('a denied uci.configs falls back to reading each config', () async {
      final api = _ProbeApi()
        ..configsError = const RpcException(
          object: 'uci',
          method: 'configs',
          status: 6,
        );

      final caps = await build(api).probe(_session);

      expect(caps.probeFailed, isFalse);
      expect(caps.uciConfigs, contains('dhcp'));
      expect(caps.uciConfigs, contains('firewall'));
      expect(caps.of(RouterFeature.dhcpReservations).available, isTrue);
      expect(caps.of(RouterFeature.clientBlocking).available, isTrue);
      // The mock has no sqm config, so that one is still correctly absent.
      expect(
        caps.of(RouterFeature.sqm).reason,
        UnavailableReason.missingPackage,
      );
    });

    test('a throwing session.list also falls back', () async {
      final api = _ProbeApi()
        ..aclError = Exception('nope')
        ..accessGrants = const {'uci.set'};

      final caps = await build(api).probe(_session);

      expect(api.accessCalls, greaterThan(1));
      expect(caps.allows('uci', 'set'), isTrue);
      expect(caps.allows('uci', 'apply'), isFalse);
    });

    // A probe that timed out is not a denial. Reading it as one on
    // `uci.rollback` would have the next change committed without rollback
    // protection over a blip.
    test('an unanswered access probe reads as unknown, not denied', () async {
      final api = _ProbeApi()
        ..acl = null
        ..accessGrants = const {'uci.set', 'uci.apply', 'uci.confirm'}
        ..accessErrorsFor = const {'uci.rollback'};

      final caps = await build(api).probe(_session);

      expect(caps.unprobedFunctions, {'uci.rollback'});
      expect(caps.allows('uci', 'rollback'), isTrue);
      final rollback = caps.of(RouterFeature.uciApplyRollback);
      expect(rollback.available, isTrue);
      // ...but not on the strength of a measurement, and a countdown to a
      // rollback must not promise one on a guess.
      expect(rollback.verified, isFalse);
      expect(caps.of(RouterFeature.reboot).verified, isTrue);
      // A measured denial still counts.
      expect(caps.allows('system', 'reboot'), isFalse);
    });

    // If not one access probe answers we know nothing about permissions, so
    // assume permitted rather than hiding every write.
    test('unanswerable access probes leave the ACL unknown', () async {
      final api = _ProbeApi()
        ..acl = null
        ..accessErrors = true;

      final caps = await build(api).probe(_session);

      expect(caps.probeFailed, isFalse);
      expect(caps.ubusAcl, isNull);
      expect(caps.allows('uci', 'apply'), isTrue);
      final rollback = caps.of(RouterFeature.uciApplyRollback);
      expect(rollback.available, isTrue);
      // Permitted by assumption is not permitted by measurement.
      expect(rollback.verified, isFalse);
    });
  });

  group('reviewer mode', () {
    test('the mock backend probes as a fully-capable router', () async {
      final caps = await CapabilityService(MockApiService()).probe(_session);

      expect(caps.probeFailed, isFalse);
      expect(caps.of(RouterFeature.uciApplyRollback).available, isTrue);
      expect(caps.of(RouterFeature.dhcpReservations).available, isTrue);
      expect(caps.of(RouterFeature.clientBlocking).available, isTrue);
      // Enough add-ons are present that the add-ons hub is not a screen of
      // greyed-out rows, which a reviewer reads as broken...
      expect(caps.of(RouterFeature.sqm).available, isTrue);
      expect(caps.of(RouterFeature.adblock).available, isTrue);
      expect(caps.of(RouterFeature.upnp).available, isTrue);
      expect(caps.of(RouterFeature.trafficAccounting).available, isTrue);
      // ...but one is deliberately absent, so the "install this" path is
      // demoed too.
      expect(
        caps.of(RouterFeature.ddns).reason,
        UnavailableReason.missingPackage,
      );
    });
  });
}
