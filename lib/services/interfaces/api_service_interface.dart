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
}
