import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/client.dart';

/// Tests for AP-mode client detection (GitHub issues #21, #52, #45, #32).
///
/// Root cause: The app relies exclusively on DHCP leases to populate clients.
/// On AP-mode routers where DHCP is disabled, the lease list is empty, so
/// "No Active Clients Found" is shown — even though wireless clients ARE
/// connected and visible via iwinfo.assoclist.
///
/// Fix: Use wireless association data as a fallback client source when
/// a wireless MAC is not present in the DHCP lease list.

void main() {
  group('Client.fromWirelessStation', () {
    test('creates a client from just a MAC address', () {
      final client = Client.fromWirelessStation('AA:BB:CC:DD:EE:FF');

      expect(client.macAddress, 'AA:BB:CC:DD:EE:FF');
      expect(client.connectionType, ConnectionType.wireless);
      expect(client.ipAddress, 'N/A');
      expect(client.hostname, 'Unknown');
    });

    test('handles lowercase MAC address', () {
      final client = Client.fromWirelessStation('aa:bb:cc:dd:ee:ff');

      expect(client.macAddress, 'aa:bb:cc:dd:ee:ff');
      expect(client.connectionType, ConnectionType.wireless);
    });

    test('has no lease time or active time', () {
      final client = Client.fromWirelessStation('AA:BB:CC:DD:EE:FF');

      expect(client.leaseTime, isNull);
      expect(client.activeTime, isNull);
      expect(client.expiresAt, isNull);
    });
  });

  group('AP-mode client merging logic', () {
    test('wireless MACs not in DHCP produce fallback clients', () {
      // Simulate: DHCP leases are empty (AP mode), but wireless has stations
      final dhcpLeases = <Map<String, dynamic>>[];
      final wirelessMacs = {'AA:BB:CC:11:22:33', 'AA:BB:CC:44:55:66'};

      final clients = _buildMergedClientList(dhcpLeases, wirelessMacs);

      expect(clients, hasLength(2));
      expect(
        clients.every((c) => c.connectionType == ConnectionType.wireless),
        isTrue,
      );
      expect(
        clients.map((c) => c.macAddress.toUpperCase()).toSet(),
        wirelessMacs,
      );
    });

    test('wireless MACs already in DHCP are not duplicated', () {
      final dhcpLeases = <Map<String, dynamic>>[
        {
          'macaddr': 'aa:bb:cc:11:22:33',
          'ipaddr': '192.168.1.100',
          'hostname': 'iPhone-John',
        },
      ];
      final wirelessMacs = {'AA:BB:CC:11:22:33'};

      final clients = _buildMergedClientList(dhcpLeases, wirelessMacs);

      expect(clients, hasLength(1));
      expect(clients.first.hostname, 'iPhone-John');
      expect(clients.first.ipAddress, '192.168.1.100');
      expect(clients.first.connectionType, ConnectionType.wireless);
    });

    test('mix of DHCP and wireless-only clients', () {
      final dhcpLeases = <Map<String, dynamic>>[
        {
          'macaddr': 'aa:bb:cc:11:22:33',
          'ipaddr': '192.168.1.100',
          'hostname': 'iPhone-John',
        },
        {
          'macaddr': 'dd:ee:ff:11:22:33',
          'ipaddr': '192.168.1.200',
          'hostname': 'Desktop-PC',
        },
      ];
      // One MAC overlaps with DHCP, one is wireless-only
      final wirelessMacs = {'AA:BB:CC:11:22:33', 'AA:BB:CC:99:88:77'};

      final clients = _buildMergedClientList(dhcpLeases, wirelessMacs);

      // 2 from DHCP + 1 wireless-only = 3
      expect(clients, hasLength(3));

      final wirelessClients = clients
          .where((c) => c.connectionType == ConnectionType.wireless)
          .toList();
      expect(wirelessClients, hasLength(2));

      final wiredClients = clients
          .where((c) => c.connectionType == ConnectionType.wired)
          .toList();
      expect(wiredClients, hasLength(1));
      expect(wiredClients.first.hostname, 'Desktop-PC');
    });

    test('empty DHCP and empty wireless returns no clients', () {
      final clients = _buildMergedClientList([], {});
      expect(clients, isEmpty);
    });
  });
}

/// Simulates the merged client list logic that will be in app_state.dart.
/// This is the pattern we're implementing: DHCP leases + wireless fallback.
List<Client> _buildMergedClientList(
  List<Map<String, dynamic>> dhcpLeases,
  Set<String> wirelessMacs,
) {
  final normalizedWireless = wirelessMacs
      .map((m) => m.toUpperCase().replaceAll('-', ':'))
      .toSet();

  // Build clients from DHCP leases (existing behavior)
  final clients = <String, Client>{};
  for (final lease in dhcpLeases) {
    final client = Client.fromLease(lease);
    final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
    final isWireless = normalizedWireless.contains(macNorm);
    clients[macNorm] = client.copyWith(
      connectionType: isWireless
          ? ConnectionType.wireless
          : ConnectionType.wired,
    );
  }

  // Add wireless-only clients not in DHCP (the fix for AP mode)
  for (final mac in normalizedWireless) {
    if (!clients.containsKey(mac)) {
      clients[mac] = Client.fromWirelessStation(mac);
    }
  }

  // Sort: wireless > wired > unknown, then by hostname
  final list = clients.values.toList();
  list.sort((a, b) {
    int typeOrder(ConnectionType t) {
      switch (t) {
        case ConnectionType.wireless:
          return 0;
        case ConnectionType.wired:
          return 1;
        default:
          return 2;
      }
    }

    final cmpType = typeOrder(
      a.connectionType,
    ).compareTo(typeOrder(b.connectionType));
    if (cmpType != 0) return cmpType;
    return a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase());
  });
  return list;
}
