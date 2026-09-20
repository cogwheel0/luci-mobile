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
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/uci_mutation.dart';
import 'package:luci_mobile/state/router_session.dart';
import 'package:luci_mobile/utils/logger.dart';

final clientAliasStoreProvider = Provider<ClientAliasStore>(
  (ref) => ClientAliasStore(SecureStorageService()),
);

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
    this.subnetIp,
    this.prefixLength,
    this.poolStart,
    this.poolLimit,
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

  final String? subnetIp;
  final int? prefixLength;
  final int? poolStart;
  final int? poolLimit;
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
    subnetIp: subnetIp,
    prefixLength: prefixLength,
    poolStart: poolStart,
    poolLimit: poolLimit,
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

    // Host hints and the assoclist are enrichment: a failure degrades one
    // card, it does not blank the page.
    Map<String, dynamic> hints = const {};
    try {
      hints = await api.fetchHostHints(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
      );
    } catch (e, stack) {
      Logger.exception('Host hints unavailable', e, stack);
    }

    StationInfo? station;
    var stationFailed = false;
    try {
      station = await _findStation(session, api);
    } catch (e, stack) {
      stationFailed = true;
      Logger.exception('Station details unavailable', e, stack);
    }

    Map<String, dynamic> dhcp = const {};
    Map<String, dynamic> firewall = const {};
    var configFailed = false;
    try {
      dhcp = await _configValues(session, api, 'dhcp');
      firewall = await _configValues(session, api, 'firewall');
    } catch (e, stack) {
      configFailed = true;
      Logger.exception('Client config unavailable', e, stack);
    }

    final host = ClientConfigPlanner.findHost(dhcp, mac);
    final network = _networkForClient(appState);
    final hint = hints[mac];

    return ClientDetail(
      alias: alias,
      station: station,
      hostHintName: hint is Map ? hint['name']?.toString() : null,
      hintIpv4: _hintList(hint, 'ipaddrs'),
      hintIpv6: _hintList(hint, 'ip6addrs'),
      host: host,
      blockRule: ClientConfigPlanner.findBlockRule(firewall, mac),
      zone: ClientConfigPlanner.zoneForNetwork(firewall, network),
      subnetIp: _lanAddress(appState, network),
      prefixLength: _lanPrefix(appState, network),
      poolStart: _intOption(dhcp, network ?? 'lan', 'start'),
      poolLimit: _intOption(dhcp, network ?? 'lan', 'limit'),
      reservedIps: ClientConfigPlanner.reservedIps(
        dhcp,
        exceptSection: host?.section,
      ),
      stationUnavailable: stationFailed,
      configUnavailable: configFailed,
    );
  }

  // ------------------------------------------------------------------ reads

  Future<StationInfo?> _findStation(
    RouterSession session,
    IApiService api,
  ) async {
    final wireless = ref.read(appStateProvider).dashboardData?['wireless'];
    if (wireless is! Map) return null;
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
        final stations = await api.fetchStationDetails(
          session.ipAddress,
          session.sysauth,
          session.useHttps,
          device: ifname,
        );
        final hit = stations[mac];
        if (hit != null) return hit;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _configValues(
    RouterSession session,
    IApiService api,
    String config,
  ) async {
    final raw = await api.uciGetAll(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      config: config,
    );
    if (raw is! List || raw.length < 2) return const {};
    final data = raw[1];
    if (data is! Map) return const {};
    final values = data['values'];
    if (values is Map) return Map<String, dynamic>.from(values);
    return Map<String, dynamic>.from(data);
  }

  static List<String> _hintList(dynamic hint, String key) {
    if (hint is! Map) return const [];
    final raw = hint[key];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  /// The logical network (`lan`, `guest`, …) the client's address sits on.
  String? _networkForClient(dynamic appState) {
    final dump = appState.dashboardData?['interfaceDump'];
    if (dump is! Map) return null;
    final interfaces = dump['interface'];
    if (interfaces is! List) return null;
    for (final iface in interfaces) {
      if (iface is! Map) continue;
      final name = iface['interface']?.toString();
      if (name == null || name == 'loopback') continue;
      if (iface['proto'] == 'static' || iface['proto'] == 'dhcp') {
        final addrs = iface['ipv4-address'];
        if (addrs is List && addrs.isNotEmpty) return name;
      }
    }
    return null;
  }

  String? _lanAddress(dynamic appState, String? network) =>
      _lanField(appState, network, 'address')?.toString();

  int? _lanPrefix(dynamic appState, String? network) {
    final v = _lanField(appState, network, 'mask');
    return v is int ? v : int.tryParse(v?.toString() ?? '');
  }

  dynamic _lanField(dynamic appState, String? network, String field) {
    final dump = appState.dashboardData?['interfaceDump'];
    if (dump is! Map) return null;
    final interfaces = dump['interface'];
    if (interfaces is! List) return null;
    for (final iface in interfaces) {
      if (iface is! Map) continue;
      if (network != null && iface['interface'] != network) continue;
      final addrs = iface['ipv4-address'];
      if (addrs is List && addrs.isNotEmpty && addrs.first is Map) {
        return (addrs.first as Map)[field];
      }
    }
    return null;
  }

  static int? _intOption(
    Map<String, dynamic> values,
    String section,
    String option,
  ) {
    final s = values[section];
    if (s is! Map) return null;
    return int.tryParse(s[option]?.toString() ?? '');
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
