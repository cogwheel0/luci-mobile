import 'package:luci_mobile/utils/ipv4.dart';
import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/models/client_config.dart';
import 'package:luci_mobile/models/station_info.dart';
import 'package:luci_mobile/models/uci_change.dart';

/// One IPv4 address an interface holds, from `network.interface dump`.
class InterfaceSubnet {
  const InterfaceSubnet({
    required this.name,
    required this.address,
    required this.base,
    required this.prefix,
    this.upstream = false,
  });

  /// The logical interface (`lan`, `guest`, …).
  final String name;
  final String address;
  final List<int> base;
  final int prefix;

  /// True for an interface in an internet-facing firewall zone (or, with no
  /// firewall to ask, one named like one). Clients do not sit there, however
  /// wide its subnet. Not the default route: a dumb AP's `lan` carries one.
  final bool upstream;

  bool contains(List<int> octets) =>
      ClientConfigPlanner._sameSubnet(octets, base, prefix);
}

/// What the firewall says about upstream networks; see
/// [ClientConfigPlanner.upstreamHints].
class UpstreamHints {
  const UpstreamHints({required this.named, required this.masq});

  /// Networks in a zone named `wan…`.
  final Set<String> named;

  /// Networks in a zone that masquerades.
  final Set<String> masq;
}

/// Where a client sits: the logical network, and the interface subnet it was
/// matched to (absent when only the AP's membership named the network).
class ClientNetwork {
  const ClientNetwork(this.name, this.subnet);
  final String name;
  final InterfaceSubnet? subnet;
}

/// Turns "reserve this IP" / "block this client" into UCI operations.
///
/// Everything here is a pure function of already-fetched config, so the rules
/// — which section to touch, when to delete versus disable, what counts as a
/// valid hostname — are testable without a router.
class ClientConfigPlanner {
  const ClientConfigPlanner._();

  /// Prefix for block rules this app creates. Unblock only ever *deletes* a
  /// section carrying this prefix; anything else is disabled instead, so a
  /// rule the user wrote in LuCI is never silently destroyed.
  static const String blockRulePrefix = 'luci_mobile_block_';

  /// The section name this app uses for a given MAC's block rule.
  static String blockSectionFor(String mac) =>
      '$blockRulePrefix${StationInfo.normalizeMac(mac).replaceAll(':', '').toLowerCase()}';

  /// Reads a UCI `mac` option, which may be a single value or a list.
  static List<String> macsOf(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map((e) => StationInfo.normalizeMac(e.toString()))
          .where((e) => e.isNotEmpty)
          .toList();
    }
    // A single option may still hold several space-separated MACs.
    return raw
        .toString()
        .split(RegExp(r'\s+'))
        .where((e) => e.trim().isNotEmpty)
        .map(StationInfo.normalizeMac)
        .toList();
  }

  // ---------------------------------------------------------------- reading

  /// Finds the `dhcp` `host` section covering [mac], if any.
  static ClientDhcpHost? findHost(Map<String, dynamic> dhcpValues, String mac) {
    final target = StationInfo.normalizeMac(mac);
    for (final entry in uciSections(dhcpValues, 'host')) {
      final macs = macsOf(entry.value['mac']);
      if (!macs.contains(target)) continue;
      const known = {
        'mac',
        'ip',
        'name',
        '.type',
        '.name',
        '.anonymous',
        '.index',
      };
      final others = entry.value.keys.where((k) => !known.contains(k)).length;
      return ClientDhcpHost(
        section: entry.key,
        macAddresses: macs,
        ip: uciText(entry.value['ip']),
        name: uciText(entry.value['name']),
        otherOptionCount: others,
      );
    }
    return null;
  }

  /// Every IP already claimed by a host section other than [exceptSection].
  static Set<String> reservedIps(
    Map<String, dynamic> dhcpValues, {
    String? exceptSection,
  }) => {
    for (final entry in uciSections(dhcpValues, 'host'))
      if (entry.key != exceptSection) ?uciText(entry.value['ip']),
  };

  /// Finds a firewall rule blocking [mac].
  static ClientBlockRule? findBlockRule(
    Map<String, dynamic> firewallValues,
    String mac,
  ) {
    final target = StationInfo.normalizeMac(mac);
    for (final entry in uciSections(firewallValues, 'rule')) {
      final macs = macsOf(entry.value['src_mac']);
      if (!macs.contains(target)) continue;
      final rawTarget = uciText(entry.value['target'])?.toUpperCase();
      if (rawTarget != 'REJECT' && rawTarget != 'DROP') continue;
      return ClientBlockRule(
        section: entry.key,
        macAddresses: macs,
        enabled: uciBool(entry.value['enabled'], orElse: true),
        ownedByApp: entry.key.startsWith(blockRulePrefix),
        target: rawTarget,
      );
    }
    return null;
  }

  /// The logical network (`lan`, `guest`, …) a client sits on, or null.
  ///
  /// Decided by the client, not by the router's interface order. The
  /// [addresses] are tried in the order given — callers put the live lease
  /// first and stale host hints last — against [subnets], from
  /// [interfaceSubnets]. [wirelessNetworks] is the
  /// `network` option of the AP the client is associated to, which is the
  /// most direct evidence there is and also covers a station with no
  /// address yet.
  ///
  /// Null when nothing matches. Guessing `lan` there would put a guest-VLAN
  /// client's block rule in the wrong zone, where it blocks nothing.
  static ClientNetwork? networkForClient({
    required List<InterfaceSubnet> subnets,
    Iterable<String> addresses = const [],
    Iterable<String> wirelessNetworks = const [],
  }) {
    // The AP says which interfaces it bridges; the address says which of
    // them - and which of their subnets - the client is on. Only if no
    // address matches any of them does the first bridged interface stand.
    final apSubnets = [
      for (final network in wirelessNetworks)
        ...subnets.where((s) => s.name == network),
    ];
    for (final address in addresses) {
      final hit = subnetContaining(address, apSubnets);
      if (hit != null) return ClientNetwork(hit.name, hit);
    }
    if (apSubnets.isNotEmpty) {
      return ClientNetwork(apSubnets.first.name, apSubnets.first);
    }
    final lanSide = subnets.where((s) => !s.upstream).toList();
    for (final address in addresses) {
      final hit = subnetContaining(address, lanSide);
      if (hit != null) return ClientNetwork(hit.name, hit);
    }
    for (final network in wirelessNetworks) {
      if (network.isNotEmpty) return ClientNetwork(network, null);
    }
    return null;
  }

  /// The most specific of [subnets] that holds [address], or null.
  ///
  /// Longest prefix, not first listed: a /16 upstream or a wide transit
  /// network must not swallow a client that a /24 describes exactly.
  static InterfaceSubnet? subnetContaining(
    String address,
    Iterable<InterfaceSubnet> subnets,
  ) {
    final octets = parseIpv4(address);
    if (octets == null) return null;
    InterfaceSubnet? best;
    for (final subnet in subnets) {
      if (!subnet.contains(octets)) continue;
      if (best == null || subnet.prefix > best.prefix) best = subnet;
    }
    return best;
  }

  /// The dynamic pool of every `config dhcp` section, keyed by the network
  /// it serves — the `interface` option, which need not match the section
  /// name (`config dhcp 'guest_pool'` with `option interface 'guest'`).
  static Map<String, DhcpPool> dhcpPools(Map<String, dynamic> dhcpValues) {
    final out = <String, DhcpPool>{};
    for (final entry in uciSections(dhcpValues, 'dhcp')) {
      if (uciBool(entry.value['ignore'])) continue;
      final network = uciText(entry.value['interface']) ?? entry.key;
      final start = int.tryParse(uciText(entry.value['start']) ?? '');
      final limit = int.tryParse(uciText(entry.value['limit']) ?? '');
      if (start == null || limit == null) continue;
      out[network] = DhcpPool(start: start, limit: limit);
    }
    return out;
  }

  /// Every IPv4 subnet in a `network.interface dump`, in the dump's order.
  ///
  /// [hints] is what the firewall said (see [upstreamHints]); it is trusted
  /// when given. Only when the firewall could not be read does the name
  /// decide, and then a name starting with `wan` is the one hint there is.
  static List<InterfaceSubnet> interfaceSubnets(
    Map? interfaceDump, {
    UpstreamHints? hints,
  }) {
    final interfaces = interfaceDump?['interface'];
    if (interfaces is! List) return const [];
    final out = <InterfaceSubnet>[];
    for (final iface in interfaces) {
      if (iface is! Map) continue;
      final name = iface['interface']?.toString();
      if (name == null || name.isEmpty || name == 'loopback') continue;
      final addrs = iface['ipv4-address'];
      if (addrs is! List) continue;
      final upstream = hints == null
          ? name.startsWith('wan')
          : hints.named.contains(name) ||
                (hints.masq.contains(name) && _hasDefaultRoute(iface['route']));
      for (final addr in addrs) {
        if (addr is! Map) continue;
        final base = parseIpv4(addr['address']?.toString() ?? '');
        final mask = addr['mask'];
        final prefix = mask is int
            ? mask
            : int.tryParse(mask?.toString() ?? '');
        if (base == null || prefix == null) continue;
        out.add(
          InterfaceSubnet(
            name: name,
            address: addr['address'].toString(),
            base: base,
            prefix: prefix,
            upstream: upstream,
          ),
        );
      }
    }
    return out;
  }

  /// What the firewall says about which networks face the internet: those
  /// in a zone named `wan`, and those in a zone that NATs.
  ///
  /// The two are kept apart because NAT alone proves nothing - a `lan` that
  /// masquerades out a VPN is still where the clients are - so a
  /// masquerading network counts as upstream only if it also carries the
  /// default route (see [interfaceSubnets]). A dumb AP has neither hint,
  /// and its `lan` stays a client network even with the default route.
  static UpstreamHints upstreamHints(Map<String, dynamic> firewallValues) {
    final named = <String>{};
    final masq = <String>{};
    for (final entry in uciSections(firewallValues, 'zone')) {
      final name = uciText(entry.value['name']) ?? '';
      final networks = uciList(entry.value['network']);
      if (name.toLowerCase().startsWith('wan')) named.addAll(networks);
      if (uciBool(entry.value['masq'])) masq.addAll(networks);
    }
    return UpstreamHints(named: named, masq: masq);
  }

  static bool _hasDefaultRoute(dynamic routes) {
    if (routes is! List) return false;
    return routes.any(
      (r) => r is Map && r['target'] == '0.0.0.0' && r['mask'] == 0,
    );
  }

  /// The firewall zone whose `network` list contains [network].
  ///
  /// Returns null when nothing matches. Callers must gate the feature off
  /// rather than fall back to `lan`: hardcoding it breaks guest VLANs and any
  /// multi-zone setup.
  static String? zoneForNetwork(
    Map<String, dynamic> firewallValues,
    String? network,
  ) {
    if (network == null || network.isEmpty) return null;
    for (final entry in uciSections(firewallValues, 'zone')) {
      if (uciList(entry.value['network']).contains(network)) {
        return uciText(entry.value['name']);
      }
    }
    return null;
  }

  // ------------------------------------------------------------- validation

  /// Checks a proposed reservation IP against the subnets it may sit on,
  /// the DHCP pool of the one it lands in, and the other reservations.
  ///
  /// [subnets] is the client's own subnet when that is known, or every
  /// LAN-side subnet when it is not — an address on none of them would
  /// never be handed out. Empty means the router's interfaces could not be
  /// read, and the subnet check is skipped rather than refusing everything.
  static IpCheckResult checkReservationIp(
    String ip, {
    required Iterable<InterfaceSubnet> subnets,
    required Set<String> alreadyReserved,
    Map<String, DhcpPool> pools = const {},
  }) {
    // The value saved is the trimmed one, so every check runs on that;
    // otherwise a pasted space would slip a duplicate past the guard.
    ip = ip.trim();
    final octets = parseIpv4(ip);
    if (octets == null) return IpCheckResult.malformed;
    if (alreadyReserved.contains(ip)) return IpCheckResult.duplicate;
    if (subnets.isEmpty) return IpCheckResult.ok;

    final subnet = subnetContaining(ip, subnets);
    if (subnet == null) return IpCheckResult.outsideSubnet;
    // dnsmasq counts `start` from the network address, not from zero.
    final pool = pools[subnet.name];
    final offset = _toInt(octets) - _networkAddress(subnet);
    if (pool != null && pool.coversOffset(offset)) {
      return IpCheckResult.insidePool;
    }
    return IpCheckResult.ok;
  }

  static int _toInt(List<int> octets) =>
      (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];

  static int _networkAddress(InterfaceSubnet subnet) {
    final bits = subnet.prefix.clamp(0, 32);
    final mask = bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
    return _toInt(subnet.base) & mask;
  }

  static bool _sameSubnet(List<int> a, List<int> b, int prefix) {
    var bits = prefix.clamp(0, 32);
    for (var i = 0; i < 4; i++) {
      if (bits <= 0) break;
      final take = bits >= 8 ? 8 : bits;
      final mask = take == 8 ? 0xFF : (0xFF << (8 - take)) & 0xFF;
      if ((a[i] & mask) != (b[i] & mask)) return false;
      bits -= take;
    }
    return true;
  }

  // -------------------------------------------------------------- planning

  /// Creates or updates the static lease for [mac].
  static List<UciOperation> planReservation({
    required String mac,
    required String ip,
    String? name,
    ClientDhcpHost? existing,
  }) {
    final normalized = StationInfo.normalizeMac(mac);
    if (existing == null) {
      return [
        UciAdd(
          'dhcp',
          type: 'host',
          identity: const ['mac'],
          values: {
            'mac': normalized,
            'ip': ip,
            if (name != null && name.isNotEmpty) 'name': name,
          },
        ),
      ];
    }
    return [
      UciSet(
        'dhcp',
        section: existing.section,
        values: {'ip': ip, if (name != null && name.isNotEmpty) 'name': name},
      ),
    ];
  }

  /// Removes the static lease.
  ///
  /// Deletes the whole section only when this app would have created exactly
  /// it; otherwise just drops the `ip` option so the user's other settings
  /// survive.
  static List<UciOperation> planRemoveReservation({
    required ClientDhcpHost existing,
    bool keepName = false,
  }) {
    final sectionIsOursAlone =
        existing.otherOptionCount == 0 &&
        (existing.name == null || !keepName) &&
        existing.macAddresses.length == 1;
    if (sectionIsOursAlone) {
      return [UciRemove('dhcp', section: existing.section)];
    }
    return [UciRemove('dhcp', section: existing.section, option: 'ip')];
  }

  /// Sets or clears the DHCP hostname for [mac].
  ///
  /// Only for the advanced "also set the DHCP hostname" path — the default
  /// rename is a local alias, which touches no router config at all.
  static List<UciOperation> planDhcpName({
    required String mac,
    required String? name,
    ClientDhcpHost? existing,
  }) {
    final normalized = StationInfo.normalizeMac(mac);
    if (name == null || name.isEmpty) {
      if (existing == null) return const [];
      return [UciRemove('dhcp', section: existing.section, option: 'name')];
    }
    if (existing == null) {
      return [
        UciAdd(
          'dhcp',
          type: 'host',
          identity: const ['mac'],
          values: {'mac': normalized, 'name': name},
        ),
      ];
    }
    return [
      UciSet('dhcp', section: existing.section, values: {'name': name}),
    ];
  }

  /// Blocks [mac] from reaching anything beyond the router.
  ///
  /// `dest: '*'` with no `input` rule stops internet and inter-network
  /// forwarding while leaving the router itself reachable — deliberately, so a
  /// user who blocks the phone they are holding can still unblock it.
  static List<UciOperation> planBlock({
    required String mac,
    required String zone,
    required String displayName,
    ClientBlockRule? existing,
  }) {
    final normalized = StationInfo.normalizeMac(mac);
    if (existing != null) {
      return [
        UciSet('firewall', section: existing.section, values: {'enabled': '1'}),
      ];
    }
    return [
      UciAdd(
        'firewall',
        type: 'rule',
        name: blockSectionFor(normalized),
        values: {
          'name': 'Block $displayName (LuCI Mobile)',
          'src': zone,
          'src_mac': normalized,
          'dest': '*',
          'target': 'REJECT',
          'enabled': '1',
        },
      ),
    ];
  }

  /// Lifts a block.
  ///
  /// Removes the rule when this app created it; otherwise disables it, because
  /// deleting configuration the user wrote by hand is not ours to do.
  static List<UciOperation> planUnblock({required ClientBlockRule existing}) {
    if (existing.ownedByApp) {
      return [UciRemove('firewall', section: existing.section)];
    }
    return [
      UciSet('firewall', section: existing.section, values: {'enabled': '0'}),
    ];
  }
}
