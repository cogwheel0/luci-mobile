import 'package:flutter/foundation.dart';

/// A firewall zone (`config zone`).
@immutable
class FirewallZone {
  const FirewallZone({
    required this.section,
    required this.name,
    this.input = 'REJECT',
    this.output = 'ACCEPT',
    this.forward = 'REJECT',
    this.masq = false,
    this.networks = const [],
  });

  final String section;
  final String name;
  final String input;
  final String output;
  final String forward;
  final bool masq;
  final List<String> networks;

  /// A zone that NATs is the one facing the internet, which is where port
  /// forwards come from by default.
  bool get looksLikeWan => masq || name.toLowerCase().startsWith('wan');
}

/// A port forward (`config redirect` with `target DNAT`).
@immutable
class PortForward {
  const PortForward({
    required this.section,
    this.name,
    this.enabled = true,
    this.protocol = 'tcp udp',
    this.sourceZone = 'wan',
    this.sourcePort,
    this.destZone = 'lan',
    this.destIp,
    this.destPort,
  });

  final String section;
  final String? name;
  final bool enabled;

  /// Space-separated UCI protocol list: `tcp`, `udp`, `tcp udp`.
  final String protocol;

  final String sourceZone;

  /// The port reached from outside.
  final String? sourcePort;

  final String destZone;

  /// The LAN host traffic is sent to.
  final String? destIp;

  /// The port on that host; when absent the source port is reused.
  final String? destPort;

  String get effectiveDestPort => destPort ?? sourcePort ?? '';
}

/// A traffic rule (`config rule`), which includes the app's client blocks.
@immutable
class TrafficRule {
  const TrafficRule({
    required this.section,
    this.name,
    this.enabled = true,
    this.source,
    this.dest,
    this.sourceMac,
    this.target = 'REJECT',
    this.protocol,
    this.destPort,
  });

  final String section;
  final String? name;
  final bool enabled;
  final String? source;
  final String? dest;
  final String? sourceMac;
  final String target;
  final String? protocol;
  final String? destPort;

  /// True when this app created the rule, and may therefore delete it.
  bool get ownedByApp => section.startsWith('luci_mobile_');
}

/// A static route (`config route` in `/etc/config/network`).
@immutable
class StaticRoute {
  const StaticRoute({
    required this.section,
    required this.interface,
    required this.target,
    this.netmask,
    this.gateway,
    this.metric,
    this.disabled = false,
  });

  final String section;
  final String interface;

  /// Destination network, e.g. `10.0.0.0`.
  final String target;
  final String? netmask;
  final String? gateway;
  final String? metric;
  final bool disabled;
}
