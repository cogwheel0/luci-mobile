import 'package:luci_mobile/utils/ipv4.dart';
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
          sourceIp: uciText(e.value['src_ip']),
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
  /// almost never means, and fw4 silently applies only one of them. Unless
  /// they take it from different senders: one port forwarded to two hosts
  /// depending on [sourceIp] is what restricting the source is for.
  static bool portAlreadyForwarded(
    List<PortForward> existing,
    String port,
    String protocol, {
    String? exceptSection,
    String? sourceIp,
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
      if (!_sourcesOverlap(sourceIp, f.sourceIp)) return false;
      return uciList(f.protocol).toSet().intersection(wanted).isNotEmpty;
    });
  }

  /// An IPv4 address or CIDR subnet a forward may be restricted to,
  /// optionally negated with a leading `!` as LuCI writes it.
  ///
  /// IPv4 only, like the internal address: a forward cannot mix address
  /// families.
  static bool isValidSourceAddress(String raw) {
    final text = raw.trim();
    return _subnet(text.startsWith('!') ? text.substring(1) : text) != null;
  }

  /// Whether traffic from [a] could also come from [b]. Null is any address,
  /// and a source that is not a plain subnet - negated, a list, a netmask
  /// written in LuCI - is assumed to overlap.
  static bool _sourcesOverlap(String? a, String? b) {
    if (a == null || b == null) return true;
    final x = _subnet(a);
    final y = _subnet(b);
    if (x == null || y == null) return true;
    final prefix = x.$2 < y.$2 ? x.$2 : y.$2;
    if (prefix == 0) return true;
    final shift = 32 - prefix;
    return x.$1 >> shift == y.$1 >> shift;
  }

  /// The address and prefix length of an IPv4 address or CIDR subnet, or
  /// null when [raw] is neither.
  static (int, int)? _subnet(String raw) {
    // parseIpv4 trims, and an address with a space in it is not one fw4
    // reads the same way.
    if (raw.contains(RegExp(r'\s'))) return null;
    final parts = raw.split('/');
    if (parts.length > 2) return null;
    final octets = parseIpv4(parts.first);
    if (octets == null) return null;
    var prefix = 32;
    if (parts.length == 2) {
      if (!RegExp(r'^(0|[1-9][0-9]?)$').hasMatch(parts.last)) return null;
      prefix = int.parse(parts.last);
      if (prefix > 32) return null;
    }
    return (octets.fold(0, (sum, octet) => sum << 8 | octet), prefix);
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
    String? sourceIp,
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
        'src_ip': ?sourceIp,
        'src_dport': sourcePort,
        'dest': destZone,
        'dest_ip': destIp,
        'dest_port': destPort,
        'proto': protocol,
        'enabled': '1',
      },
    ),
  ];

  /// [sourceIp] is left alone when null or unchanged, and removed when
  /// empty. An unchanged one is not rewritten: LuCI may have stored it as a
  /// list, which writing it back would flatten.
  static List<UciOperation> planUpdatePortForward({
    required PortForward existing,
    required String name,
    required String sourceZone,
    required String sourcePort,
    required String destIp,
    required String destPort,
    required String protocol,
    String? destZone,
    String? sourceIp,
  }) {
    final newSourceIp = sourceIp == (existing.sourceIp ?? '') ? null : sourceIp;
    return [
      UciSet(
        'firewall',
        section: existing.section,
        values: {
          'name': name,
          // The edit sheet offers zone dropdowns; leaving these out meant
          // changing one reported success and did nothing.
          'src': sourceZone,
          'dest': ?destZone,
          if (newSourceIp != null && newSourceIp.isNotEmpty)
            'src_ip': newSourceIp,
          'src_dport': sourcePort,
          'dest_ip': destIp,
          'dest_port': destPort,
          'proto': protocol,
        },
      ),
      if (newSourceIp == '')
        UciRemove('firewall', section: existing.section, option: 'src_ip'),
    ];
  }

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
