import 'package:flutter/foundation.dart';

import 'package:luci_mobile/models/station_info.dart';

/// What the kernel's neighbour table says about one address.
enum NeighbourState {
  /// Answered recently: REACHABLE, DELAY, PROBE, or a PERMANENT entry.
  present,

  /// Not confirmed lately (STALE): idle, or gone and not yet probed.
  unconfirmed,

  /// Stopped answering (FAILED, INCOMPLETE).
  gone,
}

@immutable
class Neighbour {
  const Neighbour({required this.ip, required this.state, this.mac});

  final String ip;

  /// Normalised; absent for an entry that never resolved.
  final String? mac;
  final NeighbourState state;
}

/// Names and presence the router knows beyond its DHCP leases.
///
/// Leases alone name only clients that sent a hostname, and say nothing
/// about whether a client is still there: a phone that left keeps its lease
/// for hours. The router knows more - `getHostHints` merges `/etc/ethers`,
/// static DHCP hosts and reverse DNS, and the neighbour table says who has
/// answered lately - and this puts that into the client list.
class ClientPresence {
  const ClientPresence({this.hostHints = const {}, this.neighbours});

  /// `luci-rpc getHostHints`, keyed by normalised MAC.
  final Map<String, dynamic> hostHints;

  /// The IPv4 neighbour table; null when it could not be read, in which
  /// case presence is left unknown rather than guessed.
  final List<Neighbour>? neighbours;

  /// The command line LuCI's `luci-mod-status-routes` ACL grants
  /// (`/sbin/ip -[46] neigh show`); any other form is refused.
  static const neighbourCommand = ('/sbin/ip', ['-4', 'neigh', 'show']);

  /// Parses `ip neigh show` output:
  /// `192.168.1.50 dev br-lan lladdr aa:bb:cc:dd:ee:ff REACHABLE`.
  static List<Neighbour> parseNeighbours(String output) {
    final out = <Neighbour>[];
    for (final line in output.split('\n')) {
      final words = line.trim().split(RegExp(r'\s+'));
      if (words.length < 2) continue;
      final lladdr = words.indexOf('lladdr');
      final mac = lladdr >= 0 && lladdr + 1 < words.length
          ? StationInfo.normalizeMac(words[lladdr + 1])
          : null;
      final state = switch (words.last.toUpperCase()) {
        'REACHABLE' ||
        'DELAY' ||
        'PROBE' ||
        'PERMANENT' => NeighbourState.present,
        'STALE' => NeighbourState.unconfirmed,
        'FAILED' || 'INCOMPLETE' => NeighbourState.gone,
        _ => null,
      };
      if (state == null) continue;
      out.add(Neighbour(ip: words.first, mac: mac, state: state));
    }
    return out;
  }

  /// The name the router has for [mac] from `/etc/ethers`, a static DHCP
  /// host or reverse DNS, or null.
  String? nameFor(String mac) {
    final hint = hostHints[StationInfo.normalizeMac(mac)];
    final name = hint is Map ? hint['name']?.toString().trim() : null;
    return (name == null || name.isEmpty) ? null : name;
  }

  /// Whether the client with [mac] (and lease address [ip]) is connected.
  ///
  /// Associated to an AP: yes. Otherwise the neighbour table decides, by
  /// MAC, else by the lease address (an entry that never resolved has no
  /// MAC). Recently answered: yes. Stopped answering, or absent from a
  /// table that was read: no. Not confirmed lately (STALE), or no table to
  /// ask: unknown - an idle printer and a phone that just left look the
  /// same there.
  bool? isOnline({
    required String mac,
    required String? ip,
    required bool associated,
  }) {
    if (associated) return true;
    final table = neighbours;
    if (table == null) return null;
    final normalised = StationInfo.normalizeMac(mac);
    // Every entry that is this client's, not just the first: after an
    // address change the old one can linger, FAILED or STALE, beside the
    // REACHABLE current one, in either order. By address only for an entry
    // with no MAC: one that has a MAC is another device's if it is not this
    // one's.
    final states = {
      for (final n in table)
        if (n.mac == normalised || (n.mac == null && ip != null && n.ip == ip))
          n.state,
    };
    return mergeOnline(
      states.map(
        (s) => switch (s) {
          NeighbourState.present => true,
          NeighbourState.unconfirmed => null,
          NeighbourState.gone => false,
        },
      ),
      // Absent from a table that was read: not there.
      ifNone: false,
    );
  }

  /// One answer from several: online if any says so, else unknown if any
  /// cannot tell, else offline. [ifNone] when there are none.
  ///
  /// Also how the all-routers list combines routers: a client one router
  /// still sees is online, whatever another's stale lease says.
  static bool? mergeOnline(Iterable<bool?> answers, {bool? ifNone}) {
    var any = false;
    var unknown = false;
    for (final a in answers) {
      any = true;
      if (a == true) return true;
      if (a == null) unknown = true;
    }
    if (!any) return ifNone;
    return unknown ? null : false;
  }

  /// What this router knows about the client behind [lease], as extra lease
  /// keys [Client.fromLease] reads: `_hintName` and `_online`.
  ///
  /// For the all-routers list, where each router's leases are merged with
  /// the others' and its presence has to travel with them. Association is
  /// applied after the merge, from every router's stations.
  ///
  /// `_online` is there only when the neighbour table was read: its absence
  /// means presence was never checked, which [Client.fromLease] treats
  /// differently from checked and unconfirmed.
  Map<String, Object?> annotate(Map<String, dynamic> lease) {
    final mac = lease['macaddr']?.toString() ?? '';
    final ip = lease['ipaddr']?.toString();
    return {
      '_hintName': mac.isEmpty ? null : nameFor(mac),
      if (neighbours != null)
        '_online': mac.isEmpty
            ? null
            : isOnline(mac: mac, ip: ip, associated: false),
    };
  }

  /// Whether a client's connection type may still be guessed from its
  /// vendor and hostname. Only while presence was never checked, or the
  /// client is confirmed present: a phone that left sits STALE or FAILED,
  /// and the vendor guess would keep calling it wired (#5).
  static bool mayGuessType({
    required bool presenceChecked,
    required bool? online,
  }) => !presenceChecked || online == true;

  /// How long each optional read may hold up the client list. The list is
  /// complete without them; a router slow to answer one should cost
  /// seconds, not a full request timeout per read.
  static const readBudget = Duration(seconds: 5);

  /// How much a hostname says, for picking between two leases of one
  /// client: any real name beats the `Unknown` placeholder, else longer
  /// wins.
  static int nameScore(String hostname) =>
      isUnnamed(hostname) ? -1 : hostname.length;

  /// Whether [hostname] is the placeholder for "no name".
  static bool isUnnamed(String hostname) =>
      hostname.isEmpty || hostname == 'Unknown' || hostname == 'N/A';
}
