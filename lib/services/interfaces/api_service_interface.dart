import 'package:flutter/material.dart';

import 'package:luci_mobile/models/service_status.dart';
import 'package:luci_mobile/models/station_info.dart';

/// API service interface for LuCI RPC communication.
///
/// All RPC methods that return dynamic data follow the LuCI RPC response format:
/// [status, data] where:
/// - status: Integer (0 = success, non-zero = error)
/// - data: The actual response data (varies by method)
///
/// Example: [0, {"hostname": "router", "model": "TP-Link"}]
abstract class IApiService {
  Future<String> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  });
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  });
  // Simplified call method for reviewer mode
  Future<dynamic> callSimple(
    String object,
    String method,
    Map<String, dynamic> params,
  );
  Future<bool> reboot(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<Map<String, dynamic>?> fetchWireGuardPeers({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  });
  Future<Map<String, Set<String>>> fetchAssociatedStations();
  Future<List<String>> fetchAssociatedStationsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  });
  Future<Map<String, Set<String>>> fetchAllAssociatedWirelessMacsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  });

  /// Assigns options. A `List<String>` value writes a UCI list option.
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, Object> values,
    BuildContext? context,
  });
  Future<dynamic> uciCommit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  });

  /// Executes a command on the router via the rpcd `file.exec` ubus method.
  /// [command] must be an absolute executable path; [params] are its
  /// arguments.
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  });

  /// Scans for nearby wireless networks using a given radio device (e.g., wlan0).
  /// Returns the raw scan results from iwinfo.scan.
  Future<List<Map<String, dynamic>>> scanWirelessNetworks({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String device,
    BuildContext? context,
  });

  /// Cancel any ongoing wireless network scan.
  void cancelScan() {}

  /// Adds a new UCI section. If [name] is provided, creates a named section;
  /// otherwise creates an anonymous section.
  Future<dynamic> uciAdd(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String type,
    required Map<String, dynamic> values,
    String? name,
    BuildContext? context,
  });

  /// Deletes a UCI section or one of its options.
  Future<dynamic> uciDelete(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    String? option,
    BuildContext? context,
  });

  /// Retrieves the full UCI config for a given config name.
  Future<dynamic> uciGetAll(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  });

  /// Lists the UCI configs present on the router (`uci.configs`).
  ///
  /// Doubles as a cheap probe for whether a package is installed: a router
  /// with `sqm` in this list has sqm-scripts configured.
  Future<List<String>> uciConfigs(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Reads the staged-but-uncommitted changes (`uci.changes`), keyed by config.
  ///
  /// Omit [config] to read every config at once. Note that these include
  /// changes staged by *other* clients, such as an open LuCI browser tab.
  Future<Map<String, List<List<String>>>> uciChanges(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String? config,
    BuildContext? context,
  });

  /// Discards staged changes for [config] (`uci.revert`).
  ///
  /// Not granted by the stock `luci-base` ACL, so this can fail with a
  /// permission error for non-root logins. Callers must treat it as
  /// best-effort.
  Future<dynamic> uciRevert(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  });

  /// Commits every staged change and reloads the affected services
  /// (`uci.apply`).
  ///
  /// With [rollback] true the router starts a timer of [timeoutSeconds]; if
  /// [uciConfirm] is not called with the *same session* before it expires, the
  /// router restores the previous configuration by itself. That is the safety
  /// net for applying a change that may sever this client's own connectivity.
  ///
  /// Applies are global, not per-config: this commits foreign staged changes
  /// too. Check [uciChanges] first.
  Future<dynamic> uciApply(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required bool rollback,
    required int timeoutSeconds,
    BuildContext? context,
  });

  /// Cancels the pending rollback, making the applied change permanent
  /// (`uci.confirm`).
  ///
  /// Must be sent with the same `sysauth` that called [uciApply]; rpcd binds
  /// the pending rollback to that session id.
  Future<dynamic> uciConfirm(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Immediately restores the pre-apply snapshot (`uci.rollback`) instead of
  /// waiting for the router's timer.
  ///
  /// Like [uciRevert], not granted by the stock ACL; treat as best-effort.
  Future<dynamic> uciRollback(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Reads `luci.getFeatures` — the router's own capability map
  /// (`firewall4`, `ipv6`, `wifi`, `opkg` vs `apk`, `swconfig`, …).
  ///
  /// Read-granted by the stock `luci-base` ACL, but absent on builds without
  /// `rpcd-mod-ucode`, so callers must tolerate a failure.
  Future<Map<String, dynamic>> luciGetFeatures(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Reads the whole ACL map for the current session (`session.list`), as
  /// ubus object -> permitted functions, where `*` means all.
  ///
  /// Returns null when the router will not report it — restricted logins and
  /// older rpcd — so the caller can fall back to per-call [checkUbusAccess].
  Future<Map<String, Set<String>>?> fetchSessionAcl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Full `iwinfo.assoclist` rows for one AP interface, keyed by normalized
  /// MAC.
  ///
  /// [fetchAssociatedStationsWithContext] keeps only the MAC; this keeps the
  /// signal, rates and traffic counters the client detail page needs.
  Future<Map<String, StationInfo>> fetchStationDetails(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String device,
    BuildContext? context,
  });

  /// `luci-rpc.getHostHints` — the router's own hostname/address hints, keyed
  /// by normalized MAC.
  ///
  /// Fills in devices that have no DHCP lease: static-IP hosts, and clients of
  /// an upstream DHCP server when this router is an access point.
  Future<Map<String, dynamic>> fetchHostHints(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// `luci.getRealtimeStats` — the sampled series behind LuCI's status
  /// graphs. Valid modes are `interface`, `wireless`, `conntrack` and `load`;
  /// [device] is required for the interface and wireless modes.
  ///
  /// Each row is a `[timestamp, ...values]` tuple whose shape depends on the
  /// mode.
  Future<List<List<num>>> luciRealtimeStats(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String mode,
    String? device,
    BuildContext? context,
  });

  /// Lists init.d services with their enabled and running state (`rc.list`).
  Future<Map<String, ServiceStatus>> rcList(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Runs an init.d action (`rc.init`): start, stop, restart, reload, enable
  /// or disable.
  Future<bool> rcInit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String name,
    required String action,
    BuildContext? context,
  });

  /// Sets a system account's password (`luci.setPassword`). Returns false
  /// when the router rejected it.
  Future<bool> luciSetPassword(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String username,
    required String password,
    BuildContext? context,
  });

  /// The timezone table (`luci.getTimezones`), name -> POSIX TZ string.
  Future<Map<String, String>> luciTimezones(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  /// Asks whether this session may call `object.function`
  /// (`session.access`). Null means the router gave no usable answer.
  Future<bool?> checkUbusAccess(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String function,
    BuildContext? context,
  });
}
