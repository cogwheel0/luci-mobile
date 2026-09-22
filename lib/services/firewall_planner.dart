import 'package:luci_mobile/models/firewall_config.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/client_config_planner.dart';

/// Reads and edits `/etc/config/firewall` and the routes in
/// `/etc/config/network`.
///
/// Pure functions of an already-fetched config, so the rules — what a valid
/// port is, which rules this app may delete, how a forward is shaped — are
/// testable without a router.
class FirewallPlanner {
  const FirewallPlanner._();

  /// Sections this app creates and therefore owns.
  static const String ownedPrefix = 'luci_mobile_';

  static String? _str(dynamic v) {
    if (v == null) return null;
    if (v is List) {
      return v.isEmpty ? null : v.map((e) => e.toString()).join(' ');
    }
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static bool _bool(dynamic v, {bool orElse = true}) =>
      ClientConfigPlanner.uciBool(v, orElse: orElse);

  static List<String> _list(dynamic v) {
    if (v == null) return const [];
    if (v is List) return v.map((e) => e.toString()).toList();
    return v
        .toString()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static Iterable<MapEntry<String, Map<String, dynamic>>> _sections(
    Map<String, dynamic> values,
    String type,
  ) sync* {
    for (final entry in values.entries) {
      final s = entry.value;
      if (s is Map && s['.type'] == type) {
        yield MapEntry(entry.key, Map<String, dynamic>.from(s));
      }
    }
  }

  // --------------------------------------------------------------- reading

  static List<FirewallZone> zones(Map<String, dynamic> values) => [
    for (final e in _sections(values, 'zone'))
      FirewallZone(
        section: e.key,
        name: _str(e.value['name']) ?? e.key,
        input: _str(e.value['input']) ?? 'REJECT',
        output: _str(e.value['output']) ?? 'ACCEPT',
        forward: _str(e.value['forward']) ?? 'REJECT',
        masq: _bool(e.value['masq'], orElse: false),
        networks: _list(e.value['network']),
      ),
  ];

  static List<PortForward> portForwards(Map<String, dynamic> values) => [
    for (final e in _sections(values, 'redirect'))
      // `dnat` is the default target for a redirect; only DNAT entries are
      // port forwards. SNAT redirects are a different feature.
      if ((_str(e.value['target']) ?? 'dnat').toLowerCase() == 'dnat')
        PortForward(
          section: e.key,
          name: _str(e.value['name']),
          enabled: _bool(e.value['enabled']),
          protocol: _str(e.value['proto']) ?? 'tcp udp',
          sourceZone: _str(e.value['src']) ?? 'wan',
          sourcePort: _str(e.value['src_dport']),
          destZone: _str(e.value['dest']) ?? 'lan',
          destIp: _str(e.value['dest_ip']),
          destPort: _str(e.value['dest_port']),
        ),
  ];

  static List<TrafficRule> trafficRules(Map<String, dynamic> values) => [
    for (final e in _sections(values, 'rule'))
      TrafficRule(
        section: e.key,
        name: _str(e.value['name']),
        enabled: _bool(e.value['enabled']),
        source: _str(e.value['src']),
        dest: _str(e.value['dest']),
        sourceMac: _str(e.value['src_mac']),
        target: _str(e.value['target']) ?? 'REJECT',
        protocol: _str(e.value['proto']),
        destPort: _str(e.value['dest_port']),
      ),
  ];

  static List<StaticRoute> routes(Map<String, dynamic> networkValues) => [
    for (final e in _sections(networkValues, 'route'))
      StaticRoute(
        section: e.key,
        interface: _str(e.value['interface']) ?? 'lan',
        target: _str(e.value['target']) ?? '',
        netmask: _str(e.value['netmask']),
        gateway: _str(e.value['gateway']),
        metric: _str(e.value['metric']),
        disabled: _bool(e.value['disabled'], orElse: false),
      ),
  ];

  // ------------------------------------------------------------ validation

  /// A single port, or an inclusive `from-to` range, within 1-65535.
  static bool isValidPort(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return false;
    final parts = text.split('-');
    if (parts.length > 2) return false;
    int? previous;
    for (final part in parts) {
      final value = int.tryParse(part.trim());
      if (value == null || value < 1 || value > 65535) return false;
      if (previous != null && value <= previous) return false;
      previous = value;
    }
    return true;
  }

  static bool isValidIpv4(String raw) {
    final parts = raw.trim().split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return false;
    }
    return true;
  }

  /// True when [port] on [protocol] is already forwarded by another rule.
  ///
  /// Two forwards claiming the same external port is a configuration the user
  /// almost never means, and fw4 silently applies only one of them.
  static bool portAlreadyForwarded(
    List<PortForward> existing,
    String port,
    String protocol, {
    String? exceptSection,
  }) {
    final wanted = protocol.split(RegExp(r'\s+')).toSet();
    return existing.any((f) {
      if (f.section == exceptSection) return false;
      if (f.sourcePort != port) return false;
      final theirs = f.protocol.split(RegExp(r'\s+')).toSet();
      return theirs.intersection(wanted).isNotEmpty;
    });
  }

  // -------------------------------------------------------------- planning

  /// [takenSections] are the section names already in the firewall config.
  /// The new section is derived from [name], but rpcd's `uci.add` with an
  /// existing name silently re-sets that section instead of creating one, so
  /// a second "Plex" forward would have overwritten the first.
  static List<UciOperation> planCreatePortForward({
    required String name,
    required String sourceZone,
    required String sourcePort,
    required String destIp,
    required String destPort,
    required String protocol,
    String destZone = 'lan',
    Set<String> takenSections = const {},
  }) => [
    UciAdd(
      'firewall',
      type: 'redirect',
      name: uniqueSectionName(name, takenSections),
      values: {
        'name': name,
        'target': 'DNAT',
        'src': sourceZone,
        'src_dport': sourcePort,
        'dest': destZone,
        'dest_ip': destIp,
        'dest_port': destPort,
        'proto': protocol,
        'enabled': '1',
      },
    ),
  ];

  static List<UciOperation> planUpdatePortForward({
    required PortForward existing,
    required String name,
    required String sourceZone,
    required String sourcePort,
    required String destIp,
    required String destPort,
    required String protocol,
  }) => [
    UciSet(
      'firewall',
      section: existing.section,
      values: {
        'name': name,
        // The edit sheet offers a zone dropdown; leaving `src` out meant
        // changing it reported success and did nothing.
        'src': sourceZone,
        'src_dport': sourcePort,
        'dest_ip': destIp,
        'dest_port': destPort,
        'proto': protocol,
      },
    ),
  ];

  static List<UciOperation> planSetForwardEnabled({
    required PortForward forward,
    required bool enabled,
  }) => [
    UciSet(
      'firewall',
      section: forward.section,
      values: {'enabled': enabled ? '1' : '0'},
    ),
  ];

  static List<UciOperation> planDeletePortForward(PortForward forward) => [
    UciRemove('firewall', section: forward.section),
  ];

  static List<UciOperation> planSetRuleEnabled({
    required TrafficRule rule,
    required bool enabled,
  }) => [
    UciSet(
      'firewall',
      section: rule.section,
      values: {'enabled': enabled ? '1' : '0'},
    ),
  ];

  /// Removes a traffic rule.
  ///
  /// Only rules this app created are deleted; anything the user wrote is
  /// disabled instead, because destroying hand-written configuration is not
  /// ours to do.
  static List<UciOperation> planRemoveRule(TrafficRule rule) => rule.ownedByApp
      ? [UciRemove('firewall', section: rule.section)]
      : [
          UciSet('firewall', section: rule.section, values: {'enabled': '0'}),
        ];

  static List<UciOperation> planCreateRoute({
    required String interface,
    required String target,
    String? netmask,
    String? gateway,
    String? metric,
  }) => [
    UciAdd(
      'network',
      type: 'route',
      values: {
        'interface': interface,
        'target': target,
        'netmask': ?netmask,
        'gateway': ?gateway,
        'metric': ?metric,
      },
    ),
  ];

  static List<UciOperation> planDeleteRoute(StaticRoute route) => [
    UciRemove('network', section: route.section),
  ];

  /// An owned section name derived from [name] that is not in [taken].
  static String uniqueSectionName(String name, Set<String> taken) {
    final base = '$ownedPrefix${_slug(name)}';
    if (!taken.contains(base)) return base;
    for (var i = 2; ; i++) {
      final candidate = '${base}_$i';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  /// A UCI-safe section suffix derived from a user-supplied name.
  static String _slug(String name) {
    final cleaned = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final base = cleaned.isEmpty ? 'fwd' : cleaned;
    return base.length <= 24 ? base : base.substring(0, 24);
  }
}
