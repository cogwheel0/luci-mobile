import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/client.dart';

/// Tests for connection type classification (GitHub issue #5).
///
/// Root cause: When a WiFi device disconnects but keeps its DHCP lease,
/// it's no longer in iwinfo.assoclist. The app then classifies it as "Wired"
/// instead of "Unknown", giving misleading information.

void main() {
  group('Connection type classification', () {
    test('device in wireless assoclist should be wireless', () {
      final lease = {
        'macaddr': 'aa:bb:cc:11:22:33',
        'ipaddr': '192.168.1.100',
        'hostname': 'iPhone-John',
      };
      final wirelessMacs = {'AA:BB:CC:11:22:33'};

      final client = Client.fromLease(lease);
      final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
      final isWireless = wirelessMacs.contains(macNorm);

      // If in assoclist, should be wireless regardless of heuristic
      final classified = client.copyWith(
        connectionType: isWireless
            ? ConnectionType.wireless
            : client.connectionType,
      );

      expect(classified.connectionType, ConnectionType.wireless);
    });

    test(
      'device NOT in assoclist should keep heuristic type, not forced wired',
      () {
        // A phone that disconnected from WiFi — hostname says "iphone"
        final lease = {
          'macaddr': 'aa:bb:cc:11:22:33',
          'ipaddr': '192.168.1.100',
          'hostname': 'iPhone-John',
        };
        final wirelessMacs = <String>{}; // empty — device left WiFi

        final client = Client.fromLease(lease);
        final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
        final isWireless = wirelessMacs.contains(macNorm);

        // OLD behavior: would force ConnectionType.wired (BUG)
        // NEW behavior: keep the heuristic from _determineConnectionType
        final classified = client.copyWith(
          connectionType: isWireless
              ? ConnectionType.wireless
              : client.connectionType,
        );

        // "iPhone" in hostname triggers wireless heuristic in _determineConnectionType
        expect(classified.connectionType, ConnectionType.wireless);
      },
    );

    test(
      'device with no wireless indicators and not in assoclist should be unknown',
      () {
        final lease = {
          'macaddr': '11:22:33:44:55:66',
          'ipaddr': '192.168.1.200',
          'hostname': 'generic-device',
        };
        final wirelessMacs = <String>{};

        final client = Client.fromLease(lease);
        final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
        final isWireless = wirelessMacs.contains(macNorm);

        final classified = client.copyWith(
          connectionType: isWireless
              ? ConnectionType.wireless
              : client.connectionType,
        );

        // No wireless indicators, not in assoclist → heuristic says unknown
        expect(classified.connectionType, ConnectionType.unknown);
      },
    );

    test('device with ethernet interface should stay wired', () {
      final lease = {
        'macaddr': '11:22:33:44:55:66',
        'ipaddr': '192.168.1.200',
        'hostname': 'Desktop-PC',
        'ifname': 'eth0',
      };
      final wirelessMacs = <String>{};

      final client = Client.fromLease(lease);
      final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
      final isWireless = wirelessMacs.contains(macNorm);

      final classified = client.copyWith(
        connectionType: isWireless
            ? ConnectionType.wireless
            : client.connectionType,
      );

      expect(classified.connectionType, ConnectionType.wired);
    });
  });
}
