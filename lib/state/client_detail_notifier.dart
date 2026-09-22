import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/models/client_config.dart';
import 'package:luci_mobile/models/station_info.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/client_alias_store.dart';
import 'package:luci_mobile/services/client_config_planner.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/services/wol_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/uci_mutation.dart';
import 'package:luci_mobile/state/router_session.dart';
import 'package:luci_mobile/utils/logger.dart';

final clientAliasStoreProvider = Provider<ClientAliasStore>(
  (ref) => ClientAliasStore(SecureStorageService()),
);

/// One [WolService] per API service, so what it learns about the router's
/// etherwake config is kept between wakes.
final wolServiceProvider = Provider<WolService?>((ref) {
  final api = ref.watch(apiServiceProvider);
  return api == null ? null : WolService(api);
});

/// Everything the detail page knows about one client beyond its list entry.
@immutable
class ClientDetail {
  const ClientDetail({
    this.alias,
    this.station,
    this.hostHintName,
    this.hintIpv4 = const [],
    this.hintIpv6 = const [],
    this.host,
    this.blockRule,
    this.zone,
    this.subnets = const [],
    this.pools = const {},
    this.reservedIps = const {},
    this.stationUnavailable = false,
    this.configUnavailable = false,
  });

  /// On-device display name, if the user set one.
  final String? alias;

  /// Live wireless stats, when the client is associated to this router.
  final StationInfo? station;

  final String? hostHintName;
  final List<String> hintIpv4;
  final List<String> hintIpv6;

  final ClientDhcpHost? host;
  final ClientBlockRule? blockRule;

  /// The firewall zone covering this client's network. Null means blocking
  /// cannot be offered, because guessing `lan` breaks guest VLANs.
  final String? zone;

  /// Where a reservation may land: the client's own subnet when known, or
  /// every LAN-side subnet when it is not. Empty when the interfaces could
  /// not be read.
  final List<InterfaceSubnet> subnets;

  /// DHCP pools by network, for the in-pool warning.
  final Map<String, DhcpPool> pools;

  final Set<String> reservedIps;

  /// The assoclist read failed; the signal card degrades on its own rather
  /// than blanking the page.
  final bool stationUnavailable;

  /// `uci.get` on dhcp/firewall failed, so the write controls cannot be
  /// trusted and are disabled.
  final bool configUnavailable;

  bool get isBlocked => blockRule != null && blockRule!.enabled;
  bool get hasReservation => host?.hasReservation ?? false;

  ClientDetail copyWith({
    String? alias,
    bool clearAlias = false,
    ClientDhcpHost? host,
    bool clearHost = false,
    ClientBlockRule? blockRule,
    bool clearBlockRule = false,
  }) => ClientDetail(
    alias: clearAlias ? null : (alias ?? this.alias),
    station: station,
    hostHintName: hostHintName,
    hintIpv4: hintIpv4,
    hintIpv6: hintIpv6,
    host: clearHost ? null : (host ?? this.host),
    blockRule: clearBlockRule ? null : (blockRule ?? this.blockRule),
    zone: zone,
    subnets: subnets,
    pools: pools,
    reservedIps: reservedIps,
    stationUnavailable: stationUnavailable,
    configUnavailable: configUnavailable,
  );
}

/// Loads one client's router-side configuration.
///
/// Keyed by normalized MAC, and watches [sessionProvider] so switching router
/// re-reads from scratch.
final clientDetailProvider = FutureProvider.family<ClientDetail, String>((
  ref,
  mac,
) {
  return ClientDetailLoader(ref, mac).load();
}, retry: (_, _) => null);

class ClientDetailLoader {
  ClientDetailLoader(this.ref, String rawMac)
    : mac = StationInfo.normalizeMac(rawMac);

  final Ref ref;
  final String mac;

  Future<ClientDetail> load() async {
    final session = ref.watch(sessionProvider);
    if (session == null) return const ClientDetail();

    final api = ref.watch(apiServiceProvider);
    if (api == null) return const ClientDetail();

    final appState = ref.read(appStateProvider);
    final alias = await ref
        .read(clientAliasStoreProvider)
        .aliasFor(session.routerId, mac);

    // None of these reads depends on another, so they go out together: a
    // router with several APs would otherwise make the page wait a round
    // trip per interface before showing anything. Each catches its own
    // failure - host hints and the assoclist are enrichment, a failure
    // degrades one card rather than blanking the page.
    final (hints, found, configs) = await (
      _fetchHints(session, api),
      _findStation(session, api),
      _fetchConfigs(session, api),
    ).wait;

    final station = found.station;
    final stationNetworks = found.networks;
    final stationFailed = found.failed;
    final dhcp = configs.dhcp;
    final firewall = configs.firewall;
    final configFailed = configs.failed;

    final host = ClientConfigPlanner.findHost(dhcp, mac);
    final hint = hints[mac];

    // Which network the client is on decides the firewall zone and the
    // subnet a reservation is checked against, so it has to come from the
    // client — its addresses, or the AP it is associated to — and not from
    // whichever interface the router happens to list first. Live lease
    // first: host hints remember addresses a client has since moved off.
    final rawDump = appState.dashboardData?['interfaceDump'];
    final interfaceDump = rawDump is Map ? rawDump : null;
    // Which interfaces face the internet is the firewall's call; with no
    // firewall to ask, only the name can say.
    final upstream = configFailed
        ? null
        : ClientConfigPlanner.upstreamNetworks(firewall);
    final located = ClientConfigPlanner.networkForClient(
      interfaceDump: interfaceDump,
      addresses: <String>{
        ..._leaseAddresses(appState),
        ?host?.ip,
        ..._hintList(hint, 'ipaddrs'),
      },
      wirelessNetworks: stationNetworks,
      upstreamNetworks: upstream,
    );
    final network = located?.name;
    // A reservation is checked against the client's own subnet when it is
    // known; otherwise against every LAN-side one, so an address that no
    // interface would ever serve is still refused.
    final subnets = located?.subnet != null
        ? [located!.subnet!]
        : ClientConfigPlanner.interfaceSubnets(
            interfaceDump,
            upstreamNetworks: upstream,
          ).where((s) => !s.upstream).toList();

    return ClientDetail(
      alias: alias,
      station: station,
      hostHintName: hint is Map ? hint['name']?.toString() : null,
      hintIpv4: _hintList(hint, 'ipaddrs'),
      hintIpv6: _hintList(hint, 'ip6addrs'),
      host: host,
      blockRule: ClientConfigPlanner.findBlockRule(firewall, mac),
      zone: ClientConfigPlanner.zoneForNetwork(firewall, network),
      subnets: subnets,
      pools: ClientConfigPlanner.dhcpPools(dhcp),
      reservedIps: ClientConfigPlanner.reservedIps(
        dhcp,
        exceptSection: host?.section,
      ),
      stationUnavailable: stationFailed,
      configUnavailable: configFailed,
    );
  }

  // ------------------------------------------------------------------ reads

  Future<Map<String, dynamic>> _fetchHints(
    RouterSession session,
    IApiService api,
  ) async {
    try {
      return await api.fetchHostHints(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
      );
    } catch (e, stack) {
      Logger.exception('Host hints unavailable', e, stack);
      return const {};
    }
  }

  Future<
    ({Map<String, dynamic> dhcp, Map<String, dynamic> firewall, bool failed})
  >
  _fetchConfigs(RouterSession session, IApiService api) async {
    // Caught per config, so the log names the RPC that failed rather than
    // the wrapper a joint wait would throw.
    final (dhcp, firewall) = await (
      _configOrNull(session, api, 'dhcp'),
      _configOrNull(session, api, 'firewall'),
    ).wait;
    return (
      dhcp: dhcp ?? const <String, dynamic>{},
      firewall: firewall ?? const <String, dynamic>{},
      failed: dhcp == null || firewall == null,
    );
  }

  Future<Map<String, dynamic>?> _configOrNull(
    RouterSession session,
    IApiService api,
    String config,
  ) async {
    try {
      return await _configValues(session, api, config);
    } catch (e, stack) {
      Logger.exception('Client config $config unavailable', e, stack);
      return null;
    }
  }

  /// The station entry for this client, plus the `network`s of the AP it is
  /// associated to — the most direct evidence of which network it is on.
  ///
  /// Every AP interface is asked at once. [failed] is true when the client
  /// was not found and at least one interface could not be read, because
  /// then "not associated" is not something this router has said.
  Future<({StationInfo? station, List<String> networks, bool failed})>
  _findStation(RouterSession session, IApiService api) async {
    const none = (station: null, networks: <String>[], failed: false);
    final wireless = ref.read(appStateProvider).dashboardData?['wireless'];
    if (wireless is! Map) return none;

    final aps = <({String ifname, List<String> networks})>[];
    for (final radio in wireless.values) {
      if (radio is! Map) continue;
      final interfaces = radio['interfaces'];
      if (interfaces is! List) continue;
      for (final iface in interfaces) {
        if (iface is! Map) continue;
        final config = iface['config'];
        if (config is Map && config['mode'] == 'sta') continue;
        final ifname = iface['ifname']?.toString();
        if (ifname == null) continue;
        aps.add((
          ifname: ifname,
          networks: _networksOf(config is Map ? config['network'] : null),
        ));
      }
    }
    if (aps.isEmpty) return none;

    var anyFailed = false;
    final lookups = await Future.wait([
      for (final ap in aps)
        () async {
          try {
            final stations = await api.fetchStationDetails(
              session.ipAddress,
              session.sysauth,
              session.useHttps,
              device: ap.ifname,
            );
            return stations[mac];
          } catch (e, stack) {
            anyFailed = true;
            Logger.exception('Stations on ${ap.ifname} unavailable', e, stack);
            return null;
          }
        }(),
    ]);
    for (var i = 0; i < aps.length; i++) {
      final hit = lookups[i];
      if (hit != null) {
        return (station: hit, networks: aps[i].networks, failed: false);
      }
    }
    return (station: null, networks: const <String>[], failed: anyFailed);
  }

  /// A wifi-iface `network` option: a list, or a space-separated string.
  static List<String> _networksOf(dynamic raw) {
    if (raw is List) return [for (final n in raw) n.toString()];
    if (raw is String) {
      return raw.split(RegExp(r'\s+')).where((n) => n.isNotEmpty).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> _configValues(
    RouterSession session,
    IApiService api,
    String config,
  ) async => uciValuesOf(
    await api.uciGetAll(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      config: config,
    ),
  );

  /// Addresses the dashboard's lease table holds for this client.
  List<String> _leaseAddresses(dynamic appState) {
    final leases = appState.dashboardData?['dhcpLeases'];
    if (leases is! Map) return const [];
    final rows = leases['dhcp_leases'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map &&
            StationInfo.normalizeMac(row['macaddr']?.toString() ?? '') == mac &&
            row['ipaddr'] != null)
          row['ipaddr'].toString(),
    ];
  }

  static List<String> _hintList(dynamic hint, String key) {
    if (hint is! Map) return const [];
    final raw = hint[key];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }
}

/// Applies client changes, guarded against the session going away mid-write.
class ClientMutations {
  ClientMutations(this.ref, String rawMac)
    : mac = StationInfo.normalizeMac(rawMac);

  final Ref ref;
  final String mac;

  /// Sets the on-device display name. Touches no router config.
  Future<bool> setAlias(String? alias) async {
    final session = ref.read(sessionProvider);
    if (session == null) return false;
    final ok = await ref
        .read(clientAliasStoreProvider)
        .setAlias(session.routerId, mac, alias);
    if (ok && ref.mounted) ref.invalidate(clientDetailProvider(mac));
    return ok;
  }

  /// Stages [ops] and applies them with the router's rollback protection.
  ///
  /// Suspends the app's other router traffic for the duration: rpcd binds the
  /// pending rollback to the session that called `uci.apply`, so a concurrent
  /// re-login would make the confirm fail and the change revert.
  Future<ApplyOutcome?> applyOperations(
    List<UciOperation> ops, {
    BuildContext? context,
    void Function(ApplyPhase phase, Duration remaining)? onPhase,
  }) async {
    final outcome = await applyUciOperations(
      ref,
      ops,
      describe: 'client change',
      context: context,
      onPhase: onPhase,
    );
    if (ref.mounted) ref.invalidate(clientDetailProvider(mac));
    return outcome;
  }
}

final clientMutationsProvider = Provider.family<ClientMutations, String>(
  ClientMutations.new,
);
