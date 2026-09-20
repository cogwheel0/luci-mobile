import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/firewall_planner.dart';

final _firewall = <String, dynamic>{
  'z_lan': {
    '.type': 'zone',
    'name': 'lan',
    'input': 'ACCEPT',
    'output': 'ACCEPT',
    'forward': 'ACCEPT',
    'network': ['lan'],
  },
  'z_wan': {
    '.type': 'zone',
    'name': 'wan',
    'input': 'REJECT',
    'output': 'ACCEPT',
    'forward': 'REJECT',
    'masq': '1',
    'network': ['wan', 'wan6'],
  },
  'ssh_fwd': {
    '.type': 'redirect',
    'name': 'SSH',
    'target': 'DNAT',
    'src': 'wan',
    'src_dport': '2222',
    'dest': 'lan',
    'dest_ip': '192.168.1.10',
    'dest_port': '22',
    'proto': 'tcp',
  },
  'web_fwd': {
    '.type': 'redirect',
    // target omitted: DNAT is the default for a redirect
    'name': 'Web',
    'src': 'wan',
    'src_dport': '8080',
    'dest_ip': '192.168.1.20',
    'proto': 'tcp udp',
    'enabled': '0',
  },
  'snat_thing': {
    '.type': 'redirect',
    'target': 'SNAT',
    'name': 'Outbound',
    'src': 'lan',
  },
  'luci_mobile_block_aabb': {
    '.type': 'rule',
    'name': 'Block laptop',
    'src': 'lan',
    'src_mac': 'AA:BB:CC:11:22:33',
    'target': 'REJECT',
  },
  'user_rule': {
    '.type': 'rule',
    'name': 'Allow VPN',
    'src': 'wan',
    'proto': 'udp',
    'dest_port': '51820',
    'target': 'ACCEPT',
  },
};

final _network = <String, dynamic>{
  'lan': {'.type': 'interface', 'proto': 'static'},
  'r1': {
    '.type': 'route',
    'interface': 'lan',
    'target': '10.0.0.0',
    'netmask': '255.0.0.0',
    'gateway': '192.168.1.254',
  },
};

void main() {
  group('reading zones', () {
    test('parses policies and network membership', () {
      final zones = FirewallPlanner.zones(_firewall);
      expect(zones, hasLength(2));
      final wan = zones.firstWhere((z) => z.name == 'wan');
      expect(wan.input, 'REJECT');
      expect(wan.masq, isTrue);
      expect(wan.networks, ['wan', 'wan6']);
    });

    // Port forwards default to arriving on the NATing zone, so the UI needs
    // to know which one that is without asking the user.
    test('identifies the internet-facing zone', () {
      final zones = FirewallPlanner.zones(_firewall);
      expect(zones.firstWhere((z) => z.name == 'wan').looksLikeWan, isTrue);
      expect(zones.firstWhere((z) => z.name == 'lan').looksLikeWan, isFalse);
    });
  });

  group('reading port forwards', () {
    test('reads the fields a forward is made of', () {
      final fwd = FirewallPlanner.portForwards(
        _firewall,
      ).firstWhere((f) => f.name == 'SSH');
      expect(fwd.sourcePort, '2222');
      expect(fwd.destIp, '192.168.1.10');
      expect(fwd.destPort, '22');
      expect(fwd.protocol, 'tcp');
      expect(fwd.enabled, isTrue);
    });

    // A redirect with no explicit target is a DNAT; treating it as "not a
    // port forward" would hide rules the user can see in LuCI.
    test('treats an implicit target as DNAT', () {
      final names = FirewallPlanner.portForwards(_firewall).map((f) => f.name);
      expect(names, contains('Web'));
    });

    // SNAT redirects are a different feature and must not appear in a port
    // forward list.
    test('excludes SNAT redirects', () {
      final names = FirewallPlanner.portForwards(_firewall).map((f) => f.name);
      expect(names, isNot(contains('Outbound')));
    });

    test('a disabled forward is reported as disabled', () {
      final web = FirewallPlanner.portForwards(
        _firewall,
      ).firstWhere((f) => f.name == 'Web');
      expect(web.enabled, isFalse);
      // With no dest_port the external port is reused internally.
      expect(web.effectiveDestPort, '8080');
    });
  });

  group('ownership', () {
    test('only app-created rules are owned', () {
      final rules = FirewallPlanner.trafficRules(_firewall);
      expect(
        rules
            .firstWhere((r) => r.section.startsWith('luci_mobile_'))
            .ownedByApp,
        isTrue,
      );
      expect(
        rules.firstWhere((r) => r.section == 'user_rule').ownedByApp,
        isFalse,
      );
    });

    // Destroying configuration the user wrote by hand is not ours to do.
    test("removing a user's rule disables it instead of deleting", () {
      final rule = FirewallPlanner.trafficRules(
        _firewall,
      ).firstWhere((r) => r.section == 'user_rule');
      final ops = FirewallPlanner.planRemoveRule(rule);
      final set = ops.single as UciSet;
      expect(set.section, 'user_rule');
      expect(set.values['enabled'], '0');
    });

    test('removing our own rule deletes it', () {
      final rule = FirewallPlanner.trafficRules(
        _firewall,
      ).firstWhere((r) => r.ownedByApp);
      expect(FirewallPlanner.planRemoveRule(rule).single, isA<UciRemove>());
    });
  });

  group('port validation', () {
    test('accepts a single port and an ascending range', () {
      expect(FirewallPlanner.isValidPort('80'), isTrue);
      expect(FirewallPlanner.isValidPort('1'), isTrue);
      expect(FirewallPlanner.isValidPort('65535'), isTrue);
      expect(FirewallPlanner.isValidPort('8000-8010'), isTrue);
    });

    test('rejects out-of-range, malformed and descending ranges', () {
      for (final bad in [
        '0',
        '65536',
        '',
        'http',
        '80-',
        '-80',
        '90-80',
        '1-2-3',
      ]) {
        expect(FirewallPlanner.isValidPort(bad), isFalse, reason: bad);
      }
    });

    // fw4 silently applies only one of two forwards claiming the same port,
    // so the second one looks like it worked and does nothing.
    test('detects a port already claimed on an overlapping protocol', () {
      final existing = FirewallPlanner.portForwards(_firewall);
      expect(
        FirewallPlanner.portAlreadyForwarded(existing, '2222', 'tcp'),
        isTrue,
      );
      // tcp udp overlaps tcp
      expect(
        FirewallPlanner.portAlreadyForwarded(existing, '2222', 'tcp udp'),
        isTrue,
      );
      // udp alone does not overlap the tcp-only rule
      expect(
        FirewallPlanner.portAlreadyForwarded(existing, '2222', 'udp'),
        isFalse,
      );
      expect(
        FirewallPlanner.portAlreadyForwarded(existing, '9999', 'tcp'),
        isFalse,
      );
    });

    test('a forward being edited does not clash with itself', () {
      final existing = FirewallPlanner.portForwards(_firewall);
      expect(
        FirewallPlanner.portAlreadyForwarded(
          existing,
          '2222',
          'tcp',
          exceptSection: 'ssh_fwd',
        ),
        isFalse,
      );
    });
  });

  group('planning', () {
    test('a new forward is a DNAT redirect with an owned section name', () {
      final add =
          FirewallPlanner.planCreatePortForward(
                name: 'Game Server',
                sourceZone: 'wan',
                sourcePort: '25565',
                destIp: '192.168.1.50',
                destPort: '25565',
                protocol: 'tcp udp',
              ).single
              as UciAdd;
      expect(add.config, 'firewall');
      expect(add.type, 'redirect');
      expect(add.name, 'luci_mobile_game_server');
      expect(add.values['target'], 'DNAT');
      expect(add.values['src'], 'wan');
      expect(add.values['src_dport'], '25565');
      expect(add.values['dest_ip'], '192.168.1.50');
      expect(add.values['proto'], 'tcp udp');
      expect(add.values['enabled'], '1');
    });

    test('an awkward name still yields a legal section id', () {
      final add =
          FirewallPlanner.planCreatePortForward(
                name: '  Plex!! (4K) ',
                sourceZone: 'wan',
                sourcePort: '32400',
                destIp: '192.168.1.60',
                destPort: '32400',
                protocol: 'tcp',
              ).single
              as UciAdd;
      expect(add.name, matches(RegExp(r'^luci_mobile_[a-z0-9_]+$')));
      expect(add.name, isNot(contains('__')));
    });

    test('toggling a forward touches only its enabled flag', () {
      final fwd = FirewallPlanner.portForwards(_firewall).first;
      final set =
          FirewallPlanner.planSetForwardEnabled(
                forward: fwd,
                enabled: false,
              ).single
              as UciSet;
      expect(set.values, {'enabled': '0'});
    });

    test('a static route is added to the network config', () {
      final add =
          FirewallPlanner.planCreateRoute(
                interface: 'lan',
                target: '10.0.0.0',
                netmask: '255.0.0.0',
                gateway: '192.168.1.254',
              ).single
              as UciAdd;
      expect(add.config, 'network');
      expect(add.type, 'route');
      expect(add.values['target'], '10.0.0.0');
      expect(add.values['gateway'], '192.168.1.254');
      // An omitted metric must not be written as an empty option.
      expect(add.values.containsKey('metric'), isFalse);
    });

    test('routes are read out of the network config', () {
      final routes = FirewallPlanner.routes(_network);
      expect(routes, hasLength(1));
      expect(routes.single.target, '10.0.0.0');
      expect(routes.single.gateway, '192.168.1.254');
      expect(routes.single.interface, 'lan');
    });
  });
}
