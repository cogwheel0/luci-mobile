import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/throughput_service.dart';

void main() {
  // _asNum is private; exercise it through the public updateThroughput path
  // by feeding device stats and observing the resulting rates.
  group('ThroughputService non-finite counter handling', () {
    test('string counters are parsed', () {
      final service = ThroughputService();
      service.updateThroughput(
        {
          'eth0': {'rx_bytes': '100', 'tx_bytes': '50'},
        },
        {'eth0'},
      );
      // First sample only seeds the baseline - rates must stay zero.
      expect(service.currentRxRate, 0.0);
      expect(service.currentTxRate, 0.0);
    });

    test('non-finite second sample yields zero, not NaN', () async {
      final service = ThroughputService();
      // Seed baseline with finite values.
      service.updateThroughput(
        {
          'eth0': {'rx_bytes': 1000, 'tx_bytes': 500},
        },
        {'eth0'},
      );

      // The rate calculation only runs once at least _minElapsedSeconds
      // (0.1s) have passed between samples.
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Feed non-finite garbage as the second sample: both counters fall
      // back to 0, so the computed delta is negative and clamps to a
      // finite 0.0 rate instead of poisoning history with NaN.
      service.updateThroughput(
        {
          'eth0': {'rx_bytes': 'NaN', 'tx_bytes': 'Infinity'},
        },
        {'eth0'},
      );

      expect(service.currentRxRate, 0.0);
      expect(service.currentTxRate, 0.0);
      for (final rate in service.rxHistory) {
        expect(rate.isFinite, isTrue);
      }
      for (final rate in service.txHistory) {
        expect(rate.isFinite, isTrue);
      }
    });

    test('non-finite num counters do not poison rates', () async {
      final service = ThroughputService();
      service.updateThroughput(
        {
          'eth0': {'rx_bytes': 1000, 'tx_bytes': 1000},
        },
        {'eth0'},
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));

      service.updateThroughput(
        {
          'eth0': {'rx_bytes': double.nan, 'tx_bytes': double.infinity},
        },
        {'eth0'},
      );

      expect(service.currentRxRate, 0.0);
      expect(service.currentTxRate, 0.0);
      for (final rate in service.rxHistory) {
        expect(rate.isFinite, isTrue);
      }
      for (final rate in service.txHistory) {
        expect(rate.isFinite, isTrue);
      }
    });

    test('malformed stats value falls back to direct counters', () async {
      final service = ThroughputService();
      // Seed baseline with valid direct counters.
      service.updateThroughput(
        {
          'eth0': {'rx_bytes': 1000, 'tx_bytes': 500},
        },
        {'eth0'},
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Firmware returning a non-map `stats` value must not throw; the
      // direct counters still drive the rate calculation.
      service.updateThroughput(
        {
          'eth0': {
            'stats': 'unavailable',
            'rx_bytes': 21000,
            'tx_bytes': 10500,
          },
        },
        {'eth0'},
      );

      expect(service.currentRxRate, greaterThan(0));
      expect(service.currentRxRate.isFinite, isTrue);
      expect(service.currentTxRate, greaterThan(0));
      expect(service.currentTxRate.isFinite, isTrue);
    });

    test('finite string counters produce positive finite rates', () async {
      final service = ThroughputService();
      service.updateThroughput(
        {
          'eth0': {'rx_bytes': '1000', 'tx_bytes': '500'},
        },
        {'eth0'},
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));

      service.updateThroughput(
        {
          'eth0': {'rx_bytes': '25000', 'tx_bytes': '12500'},
        },
        {'eth0'},
      );

      expect(service.currentRxRate, greaterThan(0));
      expect(service.currentRxRate.isFinite, isTrue);
      expect(service.currentTxRate, greaterThan(0));
      expect(service.currentTxRate.isFinite, isTrue);
    });
  });

  // #81: the combined graph added up LAN and WAN together, so both lines
  // were roughly download + upload and neither said which way traffic went.
  group('which way traffic goes', () {
    final dump = {
      'interface': [
        {'interface': 'loopback', 'l3_device': 'lo', 'device': 'lo'},
        {'interface': 'lan', 'l3_device': 'br-lan', 'device': 'br-lan'},
        {
          'interface': 'wan',
          'device': 'eth0.2',
          'l3_device': 'pppoe-wan',
          'route': [
            {'target': '0.0.0.0', 'mask': 0},
          ],
        },
        {
          'interface': 'wan6',
          'device': '@wan',
          'l3_device': 'pppoe-wan',
          'route': [
            {'target': '::', 'mask': 0},
          ],
        },
        {'interface': 'guest', 'l3_device': 'br-guest'},
      ],
    };

    test('the combined graph counts the internet-facing device once', () {
      // Not br-lan, and not eth0.2 as well: the PPPoE session on it is the
      // same traffic again.
      expect(ThroughputService.combinedThroughputDevices(dump), {'pppoe-wan'});
    });

    test('a WAN that is down is still found by name', () {
      final down = {
        'interface': [
          {'interface': 'lan', 'l3_device': 'br-lan'},
          {'interface': 'wan', 'device': 'eth1'},
        ],
      };
      expect(ThroughputService.combinedThroughputDevices(down), {'eth1'});
    });

    test('with no internet side to go by, every interface counts', () {
      final ap = {
        'interface': [
          {'interface': 'loopback', 'l3_device': 'lo'},
          {'interface': 'lan', 'l3_device': 'br-lan'},
          {'interface': 'iot', 'l3_device': 'br-iot'},
        ],
      };
      expect(ThroughputService.combinedThroughputDevices(ap), {
        'br-lan',
        'br-iot',
      });
      expect(ThroughputService.isClientFacing(ap, 'br-lan'), isFalse);
    });

    test('LAN and guest devices face the clients; WAN ones do not', () {
      expect(ThroughputService.isClientFacing(dump, 'br-lan'), isTrue);
      expect(ThroughputService.isClientFacing(dump, 'br-guest'), isTrue);
      // Either name of the WAN: preferences may hold the physical device.
      expect(ThroughputService.isClientFacing(dump, 'pppoe-wan'), isFalse);
      expect(ThroughputService.isClientFacing(dump, 'eth0.2'), isFalse);
    });

    // A wrong swap is as bad as the bug: without positive evidence that a
    // device faces clients, its lines are left as the router sees them.
    group('nothing is swapped on a guess', () {
      final multi = {
        'interface': [
          {
            'interface': 'wan',
            'l3_device': 'eth1',
            'route': [
              {'target': '0.0.0.0', 'mask': 0},
            ],
          },
          // A secondary uplink routing one subnet, under a name that says
          // nothing.
          {
            'interface': 'lte',
            'l3_device': 'wwan0',
            'route': [
              {'target': '10.20.0.0', 'mask': 16},
            ],
          },
          {
            'interface': 'vpn',
            'l3_device': 'wg0',
            'route': [
              {'target': '172.16.0.0', 'mask': 12},
            ],
          },
          {'interface': 'wanb', 'l3_device': 'eth2'},
          {'interface': 'lan', 'l3_device': 'br-lan'},
        ],
      };

      test('an uplink or VPN without the default route', () {
        expect(ThroughputService.isClientFacing(multi, 'wwan0'), isFalse);
        expect(ThroughputService.isClientFacing(multi, 'wg0'), isFalse);
        expect(ThroughputService.isClientFacing(multi, 'eth2'), isFalse);
        expect(ThroughputService.isClientFacing(multi, 'br-lan'), isTrue);
      });

      test('a device the dump does not list', () {
        expect(ThroughputService.isClientFacing(dump, 'phy0-ap0'), isFalse);
        expect(ThroughputService.isClientFacing(dump, 'radio0'), isFalse);
      });

      // The poll between full fetches reuses the dump, so a standby WAN
      // with no route yet must already be counted for failover to show.
      test('a standby WAN is counted before it takes over', () {
        expect(
          ThroughputService.combinedThroughputDevices(multi),
          containsAll(['eth1', 'eth2']),
        );
        expect(
          ThroughputService.combinedThroughputDevices(multi),
          isNot(contains('br-lan')),
        );
      });
    });

    test('only the chosen devices are added up', () async {
      final service = ThroughputService();
      final devices = ThroughputService.combinedThroughputDevices(dump);
      service.updateThroughput({
        'pppoe-wan': {'rx_bytes': 0, 'tx_bytes': 0},
        'br-lan': {'rx_bytes': 0, 'tx_bytes': 0},
      }, devices);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      // 1 MB downloaded: received on the WAN, sent on to the LAN.
      service.updateThroughput({
        'pppoe-wan': {'rx_bytes': 1000000, 'tx_bytes': 0},
        'br-lan': {'rx_bytes': 0, 'tx_bytes': 1000000},
      }, devices);
      expect(service.currentRxRate, greaterThan(0));
      expect(service.currentTxRate, 0);
    });
  });
}
