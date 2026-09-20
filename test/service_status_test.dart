import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/service_status.dart';

void main() {
  group('reading rc.list entries', () {
    test('a daemon reports both flags', () {
      final s = ServiceStatus.fromJson('dnsmasq', const {
        'start': 19,
        'enabled': true,
        'running': true,
      });
      expect(s.name, 'dnsmasq');
      expect(s.enabled, isTrue);
      expect(s.running, isTrue);
      expect(s.start, 19);
    });

    // Measured on OpenWrt 24.10: `boot` and `done` carry no `running` key.
    // Reading that as false would label a boot script that completed fine as
    // stopped, so it has to stay distinguishable.
    test('a one-shot script reports unknown run state, not stopped', () {
      final s = ServiceStatus.fromJson('boot', const {
        'start': 10,
        'stop': 90,
        'enabled': true,
      });
      expect(s.running, isNull);
      expect(s.enabled, isTrue);
      expect(s.stop, 90);
    });

    test('an explicitly stopped service stays false', () {
      expect(
        ServiceStatus.fromJson('cron', const {
          'enabled': true,
          'running': false,
        }).running,
        isFalse,
      );
    });

    test('a service with no boot flag is not enabled', () {
      expect(ServiceStatus.fromJson('x', const {}).enabled, isFalse);
    });
  });
}
