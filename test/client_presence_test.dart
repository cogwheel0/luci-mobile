import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/services/client_presence.dart';

const _neigh = '''
192.168.1.20 dev br-lan lladdr aa:bb:cc:00:00:20 REACHABLE
192.168.1.21 dev br-lan lladdr AA:BB:CC:00:00:21 STALE
192.168.1.22 dev br-lan lladdr aa:bb:cc:00:00:22 DELAY
192.168.1.23 dev br-lan  FAILED
192.168.1.24 dev br-lan lladdr aa:bb:cc:00:00:24 PERMANENT
192.168.1.25 dev br-lan  INCOMPLETE
10.0.0.1 dev eth1 lladdr 11:22:33:44:55:66 router REACHABLE
''';

void main() {
  group('neighbour table', () {
    test('states and addresses are read from ip neigh output', () {
      final table = ClientPresence.parseNeighbours(_neigh);
      expect(table, hasLength(7));
      expect(table.first.mac, 'AA:BB:CC:00:00:20');
      expect(table.first.state, NeighbourState.present);
      expect(table[1].state, NeighbourState.unconfirmed);
      expect(table[2].state, NeighbourState.present);
      // An entry that never resolved has no MAC.
      expect(table[3].mac, isNull);
      expect(table[3].state, NeighbourState.gone);
      expect(table[4].state, NeighbourState.present);
      expect(table[5].state, NeighbourState.gone);
      // Flags between the address and the state are skipped.
      expect(table[6].state, NeighbourState.present);
    });

    test('noise is skipped', () {
      expect(ClientPresence.parseNeighbours(''), isEmpty);
      expect(ClientPresence.parseNeighbours('garbage\n\n'), isEmpty);
    });

    test('the command is the form LuCI grants', () {
      final (command, params) = ClientPresence.neighbourCommand;
      expect('$command ${params.join(' ')}', '/sbin/ip -4 neigh show');
    });
  });

  // #5: a phone that left keeps its lease for hours, and was listed as if
  // it were still there - as a wired client.
  group('presence', () {
    final presence = ClientPresence(
      neighbours: ClientPresence.parseNeighbours(_neigh),
    );

    test('associated to an AP is connected, whatever the table says', () {
      expect(
        presence.isOnline(mac: 'aa:bb:cc:00:00:99', ip: null, associated: true),
        isTrue,
      );
    });

    test('answered lately is connected', () {
      expect(
        presence.isOnline(
          mac: 'aa:bb:cc:00:00:20',
          ip: '192.168.1.20',
          associated: false,
        ),
        isTrue,
      );
    });

    test('stopped answering, or not in the table, is not', () {
      // FAILED has no MAC: matched by the lease address.
      expect(
        presence.isOnline(
          mac: 'aa:bb:cc:00:00:23',
          ip: '192.168.1.23',
          associated: false,
        ),
        isFalse,
      );
      expect(
        presence.isOnline(
          mac: 'aa:bb:cc:00:00:77',
          ip: '192.168.1.77',
          associated: false,
        ),
        isFalse,
      );
    });

    // An idle printer and a phone that just left both look STALE.
    test('not confirmed lately is unknown', () {
      expect(
        presence.isOnline(
          mac: 'aa:bb:cc:00:00:21',
          ip: '192.168.1.21',
          associated: false,
        ),
        isNull,
      );
    });

    // The lease address now answering under another MAC is someone else.
    test('an address held by another device is not this client', () {
      expect(
        presence.isOnline(
          mac: 'aa:bb:cc:00:00:99',
          ip: '192.168.1.20',
          associated: false,
        ),
        isFalse,
      );
    });

    test('with no table to ask, presence is unknown', () {
      expect(
        const ClientPresence().isOnline(
          mac: 'aa:bb:cc:00:00:20',
          ip: '192.168.1.20',
          associated: false,
        ),
        isNull,
      );
    });
  });

  // #75: names set in /etc/ethers reach the router's host hints, not the
  // DHCP leases.
  group('names', () {
    const presence = ClientPresence(
      hostHints: {
        'AA:BB:CC:00:00:20': {'name': 'printer'},
        'AA:BB:CC:00:00:21': {'name': '  '},
      },
    );

    test('the router name is found by MAC in any spelling', () {
      expect(presence.nameFor('aa-bb-cc-00-00-20'), 'printer');
      expect(presence.nameFor('aa:bb:cc:00:00:21'), isNull);
      expect(presence.nameFor('aa:bb:cc:00:00:99'), isNull);
    });

    test('a lease without a name takes the router name', () {
      final lease = {
        'macaddr': 'aa:bb:cc:00:00:20',
        'ipaddr': '192.168.1.20',
        'hostname': '*',
      };
      final client = Client.fromLease({...lease, ...presence.annotate(lease)});
      expect(client.hostname, 'printer');
    });

    test('a lease with its own name keeps it', () {
      final lease = {
        'macaddr': 'aa:bb:cc:00:00:20',
        'ipaddr': '192.168.1.20',
        'hostname': 'laserjet',
      };
      final client = Client.fromLease({...lease, ...presence.annotate(lease)});
      expect(client.hostname, 'laserjet');
    });

    test('a lease with neither is Unknown, and presence travels', () {
      final client = Client.fromLease({
        'macaddr': 'aa:bb:cc:00:00:30',
        'hostname': '',
        '_online': false,
      });
      expect(client.hostname, 'Unknown');
      expect(client.isOnline, isFalse);
      expect(ClientPresence.isUnnamed(client.hostname), isTrue);
    });
  });
}
