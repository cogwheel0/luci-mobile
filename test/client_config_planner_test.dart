import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/client_config.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/client_config_planner.dart';

const _mac = 'AA:BB:CC:11:22:33';

final _dhcp = <String, dynamic>{
  'lan': {
    '.type': 'dhcp',
    '.name': 'lan',
    'interface': 'lan',
    'start': '100',
    'limit': '150',
  },
  'cfg01': {
    '.type': 'host',
    '.name': 'cfg01',
    'mac': 'AA:BB:CC:11:22:33',
    'ip': '192.168.1.50',
    'name': 'Laptop',
  },
  'cfg02': {
    '.type': 'host',
    '.name': 'cfg02',
    'mac': ['BB:CC:DD:11:22:33', 'BB:CC:DD:44:55:66'],
    'ip': '192.168.1.51',
  },
  'cfg03': {
    '.type': 'host',
    '.name': 'cfg03',
    'mac': 'CC:DD:EE:11:22:33',
    'ip': '192.168.1.52',
    'leasetime': '24h',
    'dns': '1',
  },
};

final _firewall = <String, dynamic>{
  'z_lan': {
    '.type': 'zone',
    '.name': 'z_lan',
    'name': 'lan',
    'network': ['lan'],
  },
  'z_guest': {
    '.type': 'zone',
    '.name': 'z_guest',
    'name': 'guest',
    'network': ['guest', 'guest6'],
  },
  'z_wan': {
    '.type': 'zone',
    '.name': 'z_wan',
    'name': 'wan',
    'network': 'wan wan6',
  },
  'luci_mobile_block_aabbcc112233': {
    '.type': 'rule',
    '.name': 'luci_mobile_block_aabbcc112233',
    'src_mac': 'AA:BB:CC:11:22:33',
    'target': 'REJECT',
    'enabled': '1',
  },
  'user_rule': {
    '.type': 'rule',
    '.name': 'user_rule',
    'src_mac': 'DD:EE:FF:11:22:33',
    'target': 'DROP',
  },
  'not_a_block': {
    '.type': 'rule',
    '.name': 'not_a_block',
    'src_mac': 'EE:FF:00:11:22:33',
    'target': 'ACCEPT',
  },
};

void main() {
  group('MAC handling', () {
    // MACs reach us from UCI, DHCP leases and iwinfo in different cases and
    // separators; matching has to be insensitive to all of it.
    test('normalizes case and separators when matching a host section', () {
      for (final form in ['aa:bb:cc:11:22:33', 'AA-BB-CC-11-22-33']) {
        final host = ClientConfigPlanner.findHost(_dhcp, form);
        expect(host, isNotNull, reason: form);
        expect(host!.section, 'cfg01');
      }
    });

    // A host section can carry several MACs; equality against the raw option
    // would silently miss those.
    test('matches by membership when mac is a list', () {
      final host = ClientConfigPlanner.findHost(_dhcp, 'bb:cc:dd:44:55:66');
      expect(host, isNotNull);
      expect(host!.section, 'cfg02');
      expect(host.macAddresses, hasLength(2));
    });

    test('reads space-separated MACs in a single option', () {
      expect(
        ClientConfigPlanner.macsOf('aa:bb:cc:11:22:33 dd:ee:ff:00:11:22'),
        ['AA:BB:CC:11:22:33', 'DD:EE:FF:00:11:22'],
      );
    });

    test('derives a stable block section name', () {
      expect(
        ClientConfigPlanner.blockSectionFor('aa-bb-cc-11-22-33'),
        'luci_mobile_block_aabbcc112233',
      );
    });

    test('an unknown MAC has no host section', () {
      expect(ClientConfigPlanner.findHost(_dhcp, '11:22:33:44:55:66'), isNull);
    });
  });

  group('hostname validation', () {
    // An invalid name stops dnsmasq, which takes LAN DNS down - and since the
    // router stays reachable, apply's rollback timer will not catch it.
    test('rejects names dnsmasq would choke on', () {
      for (final bad in [
        'my laptop',
        'my_laptop',
        '-leading',
        'trailing-',
        '',
        'a' * 64,
        'has.dot',
      ]) {
        expect(
          ClientConfigPlanner.isValidHostname(bad),
          isFalse,
          reason: 'should reject "$bad"',
        );
      }
    });

    test('accepts valid DNS labels', () {
      for (final good in ['laptop', 'Laptop-01', 'a', 'x' * 63, '0abc']) {
        expect(
          ClientConfigPlanner.isValidHostname(good),
          isTrue,
          reason: 'should accept "$good"',
        );
      }
    });
  });

  group('reservation IP checks', () {
    Set<String> reserved({String? except}) =>
        ClientConfigPlanner.reservedIps(_dhcp, exceptSection: except);

    test('an address in the subnet and outside the pool is fine', () {
      expect(
        ClientConfigPlanner.checkReservationIp(
          '192.168.1.40',
          interfaceIp: '192.168.1.1',
          prefixLength: 24,
          alreadyReserved: reserved(),
          poolStart: 100,
          poolLimit: 150,
        ),
        IpCheckResult.ok,
      );
    });

    test('a different subnet is blocking - the lease would never be used', () {
      expect(
        ClientConfigPlanner.checkReservationIp(
          '10.0.0.5',
          interfaceIp: '192.168.1.1',
          prefixLength: 24,
          alreadyReserved: reserved(),
        ),
        IpCheckResult.outsideSubnet,
      );
    });

    // Inside the pool works but can collide with a dynamically handed lease,
    // so it warns rather than blocks.
    test('an address inside the DHCP pool warns but does not block', () {
      final result = ClientConfigPlanner.checkReservationIp(
        '192.168.1.120',
        interfaceIp: '192.168.1.1',
        prefixLength: 24,
        alreadyReserved: reserved(),
        poolStart: 100,
        poolLimit: 150,
      );
      expect(result, IpCheckResult.insidePool);
      expect(result.isBlocking, isFalse);
    });

    // dnsmasq refuses duplicate reservations and fails to start.
    test('a duplicate of another reservation is blocking', () {
      final result = ClientConfigPlanner.checkReservationIp(
        '192.168.1.51',
        interfaceIp: '192.168.1.1',
        prefixLength: 24,
        alreadyReserved: reserved(),
      );
      expect(result, IpCheckResult.duplicate);
      expect(result.isBlocking, isTrue);
    });

    test('a client keeping its own address is not a duplicate', () {
      expect(
        ClientConfigPlanner.checkReservationIp(
          '192.168.1.50',
          interfaceIp: '192.168.1.1',
          prefixLength: 24,
          alreadyReserved: reserved(except: 'cfg01'),
        ),
        IpCheckResult.ok,
      );
    });

    test('malformed input is rejected', () {
      for (final bad in ['', 'nope', '192.168.1', '192.168.1.999']) {
        expect(
          ClientConfigPlanner.checkReservationIp(
            bad,
            interfaceIp: '192.168.1.1',
            prefixLength: 24,
            alreadyReserved: const {},
          ),
          IpCheckResult.malformed,
          reason: bad,
        );
      }
    });

    test('an unknown subnet skips the subnet check rather than blocking', () {
      expect(
        ClientConfigPlanner.checkReservationIp(
          '10.0.0.5',
          interfaceIp: null,
          prefixLength: null,
          alreadyReserved: const {},
        ),
        IpCheckResult.ok,
      );
    });
  });

  group('reservation planning', () {
    test('a new client gets a new host section', () {
      final ops = ClientConfigPlanner.planReservation(
        mac: 'aa:bb:cc:99:88:77',
        ip: '192.168.1.60',
        name: 'Tablet',
      );
      expect(ops, hasLength(1));
      final add = ops.single as UciAdd;
      expect(add.config, 'dhcp');
      expect(add.type, 'host');
      expect(add.values['mac'], 'AA:BB:CC:99:88:77');
      expect(add.values['ip'], '192.168.1.60');
      expect(add.values['name'], 'Tablet');
    });

    test('an existing host section is updated in place', () {
      final existing = ClientConfigPlanner.findHost(_dhcp, _mac);
      final ops = ClientConfigPlanner.planReservation(
        mac: _mac,
        ip: '192.168.1.61',
        existing: existing,
      );
      final set = ops.single as UciSet;
      expect(set.section, 'cfg01');
      expect(set.values['ip'], '192.168.1.61');
    });

    // Deleting a section that carries settings we do not model would throw
    // away the user's leasetime/dns config.
    test('removal drops only the ip when the section has other options', () {
      final existing = ClientConfigPlanner.findHost(_dhcp, 'CC:DD:EE:11:22:33');
      expect(existing!.otherOptionCount, greaterThan(0));

      final ops = ClientConfigPlanner.planRemoveReservation(existing: existing);
      final remove = ops.single as UciRemove;
      expect(remove.section, 'cfg03');
      expect(remove.option, 'ip');
    });

    test('removal deletes a section that holds nothing else', () {
      const bare = ClientDhcpHost(
        section: 'cfg09',
        macAddresses: [_mac],
        ip: '192.168.1.70',
      );
      final ops = ClientConfigPlanner.planRemoveReservation(existing: bare);
      final remove = ops.single as UciRemove;
      expect(remove.section, 'cfg09');
      expect(remove.option, isNull);
    });

    test('removal keeps a shared multi-MAC section', () {
      final existing = ClientConfigPlanner.findHost(_dhcp, 'BB:CC:DD:11:22:33');
      final ops = ClientConfigPlanner.planRemoveReservation(
        existing: existing!,
      );
      expect((ops.single as UciRemove).option, 'ip');
    });
  });

  group('zone resolution', () {
    // Hardcoding 'lan' breaks guest VLANs and every multi-zone setup.
    test('finds the zone whose network list contains the interface', () {
      expect(ClientConfigPlanner.zoneForNetwork(_firewall, 'lan'), 'lan');
      expect(ClientConfigPlanner.zoneForNetwork(_firewall, 'guest'), 'guest');
      expect(ClientConfigPlanner.zoneForNetwork(_firewall, 'wan6'), 'wan');
    });

    test('returns null rather than guessing when nothing matches', () {
      expect(ClientConfigPlanner.zoneForNetwork(_firewall, 'iot'), isNull);
      expect(ClientConfigPlanner.zoneForNetwork(_firewall, null), isNull);
    });
  });

  group('block and unblock', () {
    test('a new block rule is named, zone-scoped and rejects forwarding', () {
      final ops = ClientConfigPlanner.planBlock(
        mac: 'dd:ee:ff:99:88:77',
        zone: 'guest',
        displayName: 'Tablet',
      );
      final add = ops.single as UciAdd;
      expect(add.config, 'firewall');
      expect(add.type, 'rule');
      expect(add.name, 'luci_mobile_block_ddeeff998877');
      expect(add.values['src'], 'guest');
      expect(add.values['src_mac'], 'DD:EE:FF:99:88:77');
      // The router itself must stay reachable, or a user who blocks the phone
      // in their hand can never unblock it.
      expect(add.values['dest'], '*');
      expect(add.values['target'], 'REJECT');
      expect(add.values['enabled'], '1');
    });

    test('re-blocking re-enables the existing rule instead of duplicating', () {
      final existing = ClientConfigPlanner.findBlockRule(_firewall, _mac);
      final ops = ClientConfigPlanner.planBlock(
        mac: _mac,
        zone: 'lan',
        displayName: 'Laptop',
        existing: existing,
      );
      final set = ops.single as UciSet;
      expect(set.section, 'luci_mobile_block_aabbcc112233');
      expect(set.values['enabled'], '1');
    });

    test('detects our own rule and marks it owned', () {
      final rule = ClientConfigPlanner.findBlockRule(_firewall, _mac);
      expect(rule, isNotNull);
      expect(rule!.ownedByApp, isTrue);
      expect(rule.enabled, isTrue);
    });

    test('detects a DROP rule the user wrote, and does not own it', () {
      final rule = ClientConfigPlanner.findBlockRule(
        _firewall,
        'DD:EE:FF:11:22:33',
      );
      expect(rule, isNotNull);
      expect(rule!.ownedByApp, isFalse);
      expect(rule.target, 'DROP');
    });

    test('an ACCEPT rule is not a block', () {
      expect(
        ClientConfigPlanner.findBlockRule(_firewall, 'EE:FF:00:11:22:33'),
        isNull,
      );
    });

    test('unblocking deletes only a rule this app created', () {
      final ours = ClientConfigPlanner.findBlockRule(_firewall, _mac)!;
      final ops = ClientConfigPlanner.planUnblock(existing: ours);
      expect(ops.single, isA<UciRemove>());
      expect((ops.single as UciRemove).section, ours.section);
    });

    // Destroying configuration the user wrote by hand is not ours to do.
    test("unblocking disables, never deletes, a user's own rule", () {
      final theirs = ClientConfigPlanner.findBlockRule(
        _firewall,
        'DD:EE:FF:11:22:33',
      )!;
      final ops = ClientConfigPlanner.planUnblock(existing: theirs);
      final set = ops.single as UciSet;
      expect(set.section, 'user_rule');
      expect(set.values['enabled'], '0');
    });
  });

  group('DHCP hostname planning', () {
    test('sets the name on an existing section', () {
      final existing = ClientConfigPlanner.findHost(_dhcp, _mac);
      final ops = ClientConfigPlanner.planDhcpName(
        mac: _mac,
        name: 'Workstation',
        existing: existing,
      );
      expect((ops.single as UciSet).values['name'], 'Workstation');
    });

    test('creates a section when the client has none', () {
      final ops = ClientConfigPlanner.planDhcpName(
        mac: '11:22:33:44:55:66',
        name: 'NewThing',
      );
      final add = ops.single as UciAdd;
      expect(add.values['mac'], '11:22:33:44:55:66');
      expect(add.values['name'], 'NewThing');
      expect(add.values.containsKey('ip'), isFalse);
    });

    test('clearing the name removes just that option', () {
      final existing = ClientConfigPlanner.findHost(_dhcp, _mac);
      final ops = ClientConfigPlanner.planDhcpName(
        mac: _mac,
        name: null,
        existing: existing,
      );
      expect((ops.single as UciRemove).option, 'name');
    });

    test('clearing a name that was never set is a no-op', () {
      expect(ClientConfigPlanner.planDhcpName(mac: _mac, name: null), isEmpty);
    });
  });
}
