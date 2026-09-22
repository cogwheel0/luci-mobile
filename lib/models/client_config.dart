import 'package:flutter/foundation.dart';

/// A `dhcp` `host` section — a static lease.
@immutable
class ClientDhcpHost {
  const ClientDhcpHost({
    required this.section,
    required this.macAddresses,
    this.ip,
    this.name,
    this.otherOptionCount = 0,
  });

  /// The UCI section id (`cfg0b9836`, or a named one).
  final String section;

  /// Normalized MACs. A host section may carry several.
  final List<String> macAddresses;

  final String? ip;
  final String? name;

  /// How many options besides `mac`, `ip` and `name` this section carries.
  ///
  /// Non-zero means the user configured something we do not model, so the
  /// section must not be deleted wholesale when a reservation is removed.
  final int otherOptionCount;

  bool get hasReservation => ip != null && ip!.isNotEmpty;
}

/// A `firewall` `rule` section that blocks a client by MAC.
@immutable
class ClientBlockRule {
  const ClientBlockRule({
    required this.section,
    required this.macAddresses,
    required this.enabled,
    required this.ownedByApp,
    this.target,
  });

  final String section;
  final List<String> macAddresses;
  final bool enabled;

  /// True when this app created the rule, which is the only case in which it
  /// may be deleted rather than just disabled.
  final bool ownedByApp;

  final String? target;
}

/// The dynamic range a `config dhcp` section hands out: [start] hosts from
/// the interface address, [limit] of them.
@immutable
class DhcpPool {
  const DhcpPool({required this.start, required this.limit});
  final int start;
  final int limit;

  bool coversHost(int host) => host >= start && host < start + limit;
}

/// Why a proposed reservation IP was rejected or flagged.
enum IpCheckResult {
  ok,

  /// Not a dotted-quad.
  malformed,

  /// Outside the interface's subnet — the lease would never be handed out.
  outsideSubnet,

  /// Inside the DHCP dynamic pool. Works, but can collide with a lease the
  /// server hands to some other device, so warn rather than block.
  insidePool,

  /// Another host section already claims it. dnsmasq refuses duplicates and
  /// will fail to start.
  duplicate,
}

extension IpCheckResultX on IpCheckResult {
  bool get isBlocking =>
      this == IpCheckResult.malformed ||
      this == IpCheckResult.outsideSubnet ||
      this == IpCheckResult.duplicate;
}
