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
  });

  /// The logical interface (`lan`, `guest`, …).
  final String name;
  final String address;
  final List<int> base;
  final int prefix;
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

  /// dnsmasq requires a valid DNS label. A name with a space or underscore
  /// makes it fail to start, which takes LAN DNS down — and because the router
  /// stays *reachable*, `uci.apply`'s rollback timer will not catch it.
  static final RegExp hostnamePattern = RegExp(
    r'^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
  );

  static bool isValidHostname(String name) => hostnamePattern.hasMatch(name);

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

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Sections of one `.type` out of a `uci.get` `values` map.
  static Iterable<MapEntry<String, Map<String, dynamic>>> sectionsOfType(
    Map<String, dynamic> values,
    String type,
  ) sync* {
    for (final entry in values.entries) {
      final section = entry.value;
      if (section is! Map) continue;
      if (section['.type'] != type) continue;
      yield MapEntry(entry.key, Map<String, dynamic>.from(section));
    }
  }

  // ---------------------------------------------------------------- reading

  /// Finds the `dhcp` `host` section covering [mac], if any.
  static ClientDhcpHost? findHost(Map<String, dynamic> dhcpValues, String mac) {
    final target = StationInfo.normalizeMac(mac);
    for (final entry in sectionsOfType(dhcpValues, 'host')) {
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
        ip: _str(entry.value['ip']),
        name: _str(entry.value['name']),
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
    for (final entry in sectionsOfType(dhcpValues, 'host'))
      if (entry.key != exceptSection && _str(entry.value['ip']) != null)
        _str(entry.value['ip'])!,
  };

  /// Finds a firewall rule blocking [mac].
  static ClientBlockRule? findBlockRule(
    Map<String, dynamic> firewallValues,
    String mac,
  ) {
    final target = StationInfo.normalizeMac(mac);
    for (final entry in sectionsOfType(firewallValues, 'rule')) {
      final macs = macsOf(entry.value['src_mac']);
      if (!macs.contains(target)) continue;
      final rawTarget = _str(entry.value['target'])?.toUpperCase();
      if (rawTarget != 'REJECT' && rawTarget != 'DROP') continue;
      return ClientBlockRule(
        section: entry.key,
        macAddresses: macs,
        enabled: _str(entry.value['enabled']) != '0',
        ownedByApp: entry.key.startsWith(blockRulePrefix),
        target: rawTarget,
      );
    }
    return null;
  }

  /// The logical network (`lan`, `guest`, …) a client sits on, or null.
  ///
  /// Decided by the client, not by the router's interface order: each of
  /// [addresses] is matched against the subnets in `network.interface dump`
  /// ([interfaceDump]). [wirelessNetworks] is the `network` option of the
  /// AP the client is associated to, which is the most direct evidence there
  /// is and also covers a station with no address yet.
  ///
  /// Null when nothing matches. Guessing `lan` there would put a guest-VLAN
  /// client's block rule in the wrong zone, where it blocks nothing.
  static String? networkForClient({
    required Map? interfaceDump,
    Iterable<String> addresses = const [],
    Iterable<String> wirelessNetworks = const [],
  }) {
    final subnets = interfaceSubnets(interfaceDump);
    final bySubnet = <String>[];
    for (final subnet in subnets) {
      for (final address in addresses) {
        final octets = _parseIpv4(address);
        if (octets == null) continue;
        if (_sameSubnet(octets, subnet.base, subnet.prefix)) {
          bySubnet.add(subnet.name);
        }
      }
    }
    final known = {for (final s in subnets) s.name};
    for (final network in wirelessNetworks) {
      if (known.contains(network)) return network;
    }
    if (bySubnet.isNotEmpty) return bySubnet.first;
    for (final network in wirelessNetworks) {
      if (network.isNotEmpty) return network;
    }
    return null;
  }

  /// Every IPv4 subnet in a `network.interface dump`, in the dump's order.
  static List<InterfaceSubnet> interfaceSubnets(Map? interfaceDump) {
    final interfaces = interfaceDump?['interface'];
    if (interfaces is! List) return const [];
    final out = <InterfaceSubnet>[];
    for (final iface in interfaces) {
      if (iface is! Map) continue;
      final name = iface['interface']?.toString();
      if (name == null || name.isEmpty || name == 'loopback') continue;
      final addrs = iface['ipv4-address'];
      if (addrs is! List) continue;
      for (final addr in addrs) {
        if (addr is! Map) continue;
        final base = _parseIpv4(addr['address']?.toString() ?? '');
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
          ),
        );
      }
    }
    return out;
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
    for (final entry in sectionsOfType(firewallValues, 'zone')) {
      final networks = entry.value['network'];
      final list = networks is List
          ? networks.map((e) => e.toString()).toList()
          : (_str(networks)?.split(RegExp(r'\s+')) ?? const <String>[]);
      if (list.contains(network)) return _str(entry.value['name']);
    }
    return null;
  }

  // ------------------------------------------------------------- validation

  /// Checks a proposed reservation IP against the interface subnet, the DHCP
  /// pool and the other reservations.
  static IpCheckResult checkReservationIp(
    String ip, {
    required String? interfaceIp,
    required int? prefixLength,
    required Set<String> alreadyReserved,
    int? poolStart,
    int? poolLimit,
  }) {
    final octets = _parseIpv4(ip);
    if (octets == null) return IpCheckResult.malformed;
    if (alreadyReserved.contains(ip)) return IpCheckResult.duplicate;

    final base = interfaceIp == null ? null : _parseIpv4(interfaceIp);
    if (base != null && prefixLength != null) {
      if (!_sameSubnet(octets, base, prefixLength)) {
        return IpCheckResult.outsideSubnet;
      }
      if (poolStart != null && poolLimit != null && prefixLength >= 24) {
        final host = octets[3];
        if (host >= poolStart && host < poolStart + poolLimit) {
          return IpCheckResult.insidePool;
        }
      }
    }
    return IpCheckResult.ok;
  }

  static List<int>? _parseIpv4(String raw) {
    final parts = raw.trim().split('.');
    if (parts.length != 4) return null;
    final out = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return null;
      out.add(v);
    }
    return out;
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
        UciAdd('dhcp', type: 'host', values: {'mac': normalized, 'name': name}),
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
