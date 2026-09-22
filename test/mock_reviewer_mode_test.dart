import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/services/client_config_planner.dart';
import 'package:luci_mobile/services/mock_api_service.dart';

/// Reviewer mode is what App Store review sees. Every gap here ships as an
/// empty screen or a control that snaps back, so these are checked as
/// carefully as the real paths.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, dynamic>> uciValues(
    MockApiService api,
    String config,
  ) async {
    final raw = await api.uciGetAll('h', 't', false, config: config);
    return Map<String, dynamic>.from((raw as List)[1]['values'] as Map);
  }

  group('fixtures are params-aware', () {
    // The lookup used to key on object.method alone, so uci.get for *any*
    // config handed back the wireless one.
    test('uci.get serves the config that was asked for', () async {
      final api = MockApiService();

      final dhcp = await uciValues(api, 'dhcp');
      expect(dhcp.keys, contains('lan'));
      expect(
        uciSections(dhcp, 'host'),
        isNotEmpty,
        reason: 'dhcp fixture should contain static leases',
      );

      final firewall = await uciValues(api, 'firewall');
      expect(uciSections(firewall, 'zone'), isNotEmpty);
      expect(dhcp.keys, isNot(contains('radio0')));
    });

    // file.exec was mapped to the DHCP lease fixture, so every shell-out came
    // back as lease text.
    test(
      'file.exec does not return lease text for an unrelated command',
      () async {
        final api = MockApiService();
        final result = await api.call(
          'h',
          't',
          false,
          object: 'file',
          method: 'exec',
          params: {'command': '/sbin/logread'},
        );
        final data = (result as List)[1];
        final asText = data.toString();
        expect(asText, isNot(contains('192.168.1.100')));
      },
    );
  });

  group('station fixtures line up with the client list', () {
    // Previously the assoclist fixture used MACs that appeared in no DHCP
    // lease, so every client showed "no signal data".
    test('every associated station matches a real lease', () async {
      final api = MockApiService();

      final leaseResult = await api.call(
        'h',
        't',
        false,
        object: 'luci-rpc',
        method: 'getDHCPLeases',
      );
      final leases = ((leaseResult as List)[1]['dhcp_leases'] as List)
          .map((l) => (l['macaddr'] as String).toUpperCase())
          .toSet();
      expect(leases, isNotEmpty);

      var seen = 0;
      for (final device in ['wlan0', 'wlan1']) {
        final stations = await api.fetchStationDetails(
          'h',
          't',
          false,
          device: device,
        );
        expect(stations, isNotEmpty, reason: device);
        for (final mac in stations.keys) {
          expect(leases, contains(mac), reason: '$mac has no DHCP lease');
          seen++;
        }
      }
      expect(seen, greaterThan(10));
    });

    test('station rows carry the fields the detail page renders', () async {
      final api = MockApiService();
      final stations = await api.fetchStationDetails(
        'h',
        't',
        false,
        device: 'wlan1',
      );
      final s = stations.values.first;
      expect(s.signal, isNotNull);
      expect(s.noise, isNotNull);
      expect(s.snr, isNotNull);
      expect(s.rxRateKbps, isNotNull);
      expect(s.txBytes, isNotNull);
      expect(s.connectedSeconds, isNotNull);
      expect(s.qualityPercent, inInclusiveRange(0, 100));
    });

    test('host hints cover the leases', () async {
      final api = MockApiService();
      final hints = await api.fetchHostHints('h', 't', false);
      expect(hints, isNotEmpty);
      expect(hints.keys.first, matches(RegExp(r'^[0-9A-F:]{17}$')));
    });

    // Not every mock client is wireless, so the wired path is demoable too.
    test('some clients are wired', () async {
      final api = MockApiService();
      final wireless = <String>{};
      for (final macs in (await api.fetchAssociatedStations()).values) {
        wireless.addAll(macs.map((m) => m.toUpperCase()));
      }
      final leaseResult = await api.call(
        'h',
        't',
        false,
        object: 'luci-rpc',
        method: 'getDHCPLeases',
      );
      final leases = ((leaseResult as List)[1]['dhcp_leases'] as List)
          .map((l) => (l['macaddr'] as String).toUpperCase())
          .toSet();
      expect(leases.difference(wireless), isNotEmpty);
    });
  });

  group('writes round-trip through the overlay', () {
    // Without this a reviewer taps Block and watches the switch snap back.
    test('a set is visible on the next get', () async {
      final api = MockApiService();
      await uciValues(api, 'dhcp'); // seed

      await api.uciSet(
        'h',
        't',
        false,
        config: 'dhcp',
        section: 'lan',
        values: {'leasetime': '24h'},
      );

      final after = await uciValues(api, 'dhcp');
      expect((after['lan'] as Map)['leasetime'], '24h');
    });

    test('an add creates a readable section and reports its name', () async {
      final api = MockApiService();
      final result = await api.uciAdd(
        'h',
        't',
        false,
        config: 'dhcp',
        type: 'host',
        values: {'mac': 'AA:BB:CC:11:22:33', 'ip': '192.168.1.77'},
      );
      final section = (result as List)[1] as String;

      final after = await uciValues(api, 'dhcp');
      expect(after[section], isNotNull);
      final host = ClientConfigPlanner.findHost(after, 'aa:bb:cc:11:22:33');
      expect(host, isNotNull);
      expect(host!.ip, '192.168.1.77');
    });

    test('a delete removes the section', () async {
      final api = MockApiService();
      final before = await uciValues(api, 'firewall');
      final rule = ClientConfigPlanner.findBlockRule(
        before,
        'CC:DD:EE:98:76:54',
      );
      expect(rule, isNotNull, reason: 'fixture should ship one block rule');

      await api.uciDelete(
        'h',
        't',
        false,
        config: 'firewall',
        section: rule!.section,
      );

      final after = await uciValues(api, 'firewall');
      expect(
        ClientConfigPlanner.findBlockRule(after, 'CC:DD:EE:98:76:54'),
        isNull,
      );
    });

    test('revert restores the pre-write state', () async {
      final api = MockApiService();
      await uciValues(api, 'dhcp');
      await api.uciSet(
        'h',
        't',
        false,
        config: 'dhcp',
        section: 'lan',
        values: {'leasetime': '1h'},
      );
      await api.uciRevert('h', 't', false, config: 'dhcp');

      final after = await uciValues(api, 'dhcp');
      expect((after['lan'] as Map)['leasetime'], '12h');
    });

    test('staged changes are reported, then cleared by confirm', () async {
      final api = MockApiService();
      await uciValues(api, 'dhcp');
      await api.uciSet(
        'h',
        't',
        false,
        config: 'dhcp',
        section: 'lan',
        values: {'leasetime': '6h'},
      );

      expect(await api.uciChanges('h', 't', false), isNotEmpty);

      await api.uciApply('h', 't', false, rollback: true, timeoutSeconds: 90);
      expect(api.applyAwaitingConfirm, isTrue);

      await api.uciConfirm('h', 't', false);
      expect(api.applyAwaitingConfirm, isFalse);
      expect(await api.uciChanges('h', 't', false), isEmpty);
      // Confirm makes it the new baseline, so the value survives.
      final after = await uciValues(api, 'dhcp');
      expect((after['lan'] as Map)['leasetime'], '6h');
    });
  });
}
