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

    test('NaN/Infinity string counters do not poison rates', () {
      final service = ThroughputService();
      // Seed baseline with finite values.
      service.updateThroughput(
        {
          'eth0': {'rx_bytes': 100, 'tx_bytes': 100},
        },
        {'eth0'},
      );

      // Feed non-finite garbage as a later sample.
      service.updateThroughput(
        {
          'eth0': {'rx_bytes': 'NaN', 'tx_bytes': 'Infinity'},
        },
        {'eth0'},
      );

      expect(service.currentRxRate.isFinite, isTrue);
      expect(service.currentTxRate.isFinite, isTrue);
      for (final rate in service.rxHistory) {
        expect(rate.isFinite, isTrue);
      }
      for (final rate in service.txHistory) {
        expect(rate.isFinite, isTrue);
      }
    });

    test('non-finite num counters do not poison rates', () {
      final service = ThroughputService();
      service.updateThroughput(
        {
          'eth0': {'rx_bytes': 100, 'tx_bytes': 100},
        },
        {'eth0'},
      );

      service.updateThroughput(
        {
          'eth0': {'rx_bytes': double.nan, 'tx_bytes': double.infinity},
        },
        {'eth0'},
      );

      expect(service.currentRxRate.isFinite, isTrue);
      expect(service.currentTxRate.isFinite, isTrue);
    });
  });
}
