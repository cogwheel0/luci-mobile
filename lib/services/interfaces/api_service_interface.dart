import 'package:flutter/material.dart';

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
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, String> values,
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

  /// Deletes a UCI section (e.g., to remove a wifi-iface).
  Future<dynamic> uciDelete(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
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
}
