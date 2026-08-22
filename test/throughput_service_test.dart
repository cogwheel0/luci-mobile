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
}
