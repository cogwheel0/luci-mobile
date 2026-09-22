import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/models/firewall_config.dart';
import 'package:luci_mobile/models/uci_change.dart';

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

  // --------------------------------------------------------------- reading

  static List<FirewallZone> zones(Map<String, dynamic> values) => [
    for (final e in uciSections(values, 'zone'))
      FirewallZone(
        section: e.key,
        name: uciText(e.value['name']) ?? e.key,
        input: uciText(e.value['input']) ?? 'REJECT',
        output: uciText(e.value['output']) ?? 'ACCEPT',
        forward: uciText(e.value['forward']) ?? 'REJECT',
        masq: uciBool(e.value['masq'], orElse: false),
        networks: uciList(e.value['network']),
      ),
  ];

  static List<PortForward> portForwards(Map<String, dynamic> values) => [
    for (final e in uciSections(values, 'redirect'))
      // `dnat` is the default target for a redirect; only DNAT entries are
      // port forwards. SNAT redirects are a different feature.
      if ((uciText(e.value['target']) ?? 'dnat').toLowerCase() == 'dnat')
        PortForward(
          section: e.key,
          name: uciText(e.value['name']),
          enabled: uciBool(e.value['enabled'], orElse: true),
          protocol: uciText(e.value['proto']) ?? 'tcp udp',
          sourceZone: uciText(e.value['src']) ?? 'wan',
          sourcePort: uciText(e.value['src_dport']),
          destZone: uciText(e.value['dest']) ?? 'lan',
          destIp: uciText(e.value['dest_ip']),
          destPort: uciText(e.value['dest_port']),
        ),
  ];

  static List<TrafficRule> trafficRules(Map<String, dynamic> values) => [
    for (final e in uciSections(values, 'rule'))
      TrafficRule(
        section: e.key,
        name: uciText(e.value['name']),
        enabled: uciBool(e.value['enabled'], orElse: true),
        source: uciText(e.value['src']),
        dest: uciText(e.value['dest']),
        sourceMac: uciText(e.value['src_mac']),
        target: uciText(e.value['target']) ?? 'REJECT',
        protocol: uciText(e.value['proto']),
        destPort: uciText(e.value['dest_port']),
      ),
  ];

  static List<StaticRoute> routes(Map<String, dynamic> networkValues) => [
    for (final e in uciSections(networkValues, 'route'))
      StaticRoute(
        section: e.key,
        interface: uciText(e.value['interface']) ?? 'lan',
        target: uciText(e.value['target']) ?? '',
        netmask: uciText(e.value['netmask']),
        gateway: uciText(e.value['gateway']),
        metric: uciText(e.value['metric']),
        disabled: uciBool(e.value['disabled'], orElse: false),
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
    final wanted = uciList(protocol).toSet();
    final range = _portRange(port);
    if (range == null) return false;
    return existing.any((f) {
      if (f.section == exceptSection) return false;
      final theirs = _portRange(f.sourcePort ?? '');
      if (theirs == null) return false;
      // Ranges, not strings: `8000-8100` already claims `8080`, and fw4
      // silently applies only one of two forwards that overlap.
      if (range.$2 < theirs.$1 || theirs.$2 < range.$1) return false;
      return uciList(f.protocol).toSet().intersection(wanted).isNotEmpty;
    });
  }

  /// The inclusive port range [raw] covers, or null when it is not one.
  static (int, int)? _portRange(String raw) {
    if (!isValidPort(raw)) return null;
    final parts = raw.trim().split('-');
    final from = int.parse(parts.first.trim());
    final to = int.parse(parts.last.trim());
    return (from, to);
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
    String? destZone,
  }) => [
    UciSet(
      'firewall',
      section: existing.section,
      values: {
        'name': name,
        // The edit sheet offers zone dropdowns; leaving these out meant
        // changing one reported success and did nothing.
        'src': sourceZone,
        'dest': ?destZone,
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
      // The same target via another interface or gateway is another route.
      identity: const ['target', 'interface', 'gateway'],
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

  /// The section names a new section must avoid: everything in the config
  /// except this session's own uncommitted adds. `uci.get` shows those
  /// too, and a forward whose apply failed and could not be reverted must
  /// be re-added under its own name - which re-sets it - not as `_2` with
  /// the leftover left in the way of every apply that follows.
  static Set<String> takenSectionNames(
    Set<String> sectionNames,
    UciChangeSet? pending,
  ) => sectionNames.difference(
    pending?.liveAdds('firewall').keys.toSet() ?? const {},
  );

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
