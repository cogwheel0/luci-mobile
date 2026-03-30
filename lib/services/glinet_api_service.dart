import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:luci_mobile/utils/sha256_crypt.dart';
import 'package:luci_mobile/utils/logger.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';

/// Lightweight GL.iNet /rpc API service for supplementary data.
/// Used alongside standard LuCI/ubus for data not available via ubus
/// on GL.iNet routers (WiFi channels, CPU temperature, fan status).
class GlInetApiService {
  final HttpClientManager _httpClientManager;

  GlInetApiService(this._httpClientManager);

  String? _sid;
  String? _lastHost;

  /// Whether we have an active session.
  bool get isAuthenticated => _sid != null;

  /// Clear the cached session (call on logout or router switch).
  void clearSession() {
    _sid = null;
    _lastHost = null;
  }

  /// Authenticate to GL.iNet's /rpc endpoint.
  /// Returns cached session if already authenticated to the same host.
  Future<String?> login(String host, String password, bool useHttps) async {
    // Reuse existing session for the same host
    if (_sid != null && _lastHost == host) return _sid;
    try {
      final client = _httpClientManager.getClient(host, useHttps);
      final baseUrl = '${useHttps ? 'https' : 'http'}://$host';

      // Step 1: Challenge
      final challengeResp = await client.post<Map<String, dynamic>>(
        '$baseUrl/rpc',
        data: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'challenge',
          'params': {'username': 'root'},
        }),
        options: Options(contentType: 'application/json'),
      );

      final result = challengeResp.data?['result'] as Map<String, dynamic>?;
      if (result == null) return null;

      final nonce = result['nonce'] as String;
      final saltStr = result['salt'] as String;
      final alg = result['alg'] as int? ?? 1;
      final hashMethod = result['hash-method'] as String? ?? 'md5';

      // Step 2: Compute cipher password
      String cipherPassword;
      if (alg == 5) {
        cipherPassword = Sha256Crypt.hash(password, saltStr);
      } else {
        // Legacy MD5 fallback for firmware < 4.x.
        // WARNING: This is a weak unsalted hash. The password is included
        // in md5("root:password") which is trivially reversible with
        // rainbow tables. Routers with alg != 5 should be upgraded to
        // firmware 4.x+ which uses proper SHA-256 crypt with salt.
        cipherPassword = crypto.md5
            .convert(utf8.encode('root:$password'))
            .toString();
        Logger.warning(
          'GL.iNet router uses legacy MD5 auth (alg=$alg). '
          'Consider upgrading firmware for stronger authentication.',
        );
      }

      // Step 3: Compute final hash
      final loginInput = 'root:$cipherPassword:$nonce';
      String loginHash;
      if (hashMethod == 'sha256') {
        loginHash = crypto.sha256.convert(utf8.encode(loginInput)).toString();
      } else {
        loginHash = crypto.md5.convert(utf8.encode(loginInput)).toString();
      }

      // Step 4: Login
      final loginResp = await client.post<Map<String, dynamic>>(
        '$baseUrl/rpc',
        data: jsonEncode({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'login',
          'params': {'username': 'root', 'hash': loginHash},
        }),
        options: Options(contentType: 'application/json'),
      );

      final loginResult = loginResp.data?['result'] as Map<String, dynamic>?;
      _sid = loginResult?['sid'] as String?;
      _lastHost = _sid != null ? host : null;
      return _sid;
    } catch (e) {
      Logger.warning('GL.iNet login failed: $e');
      return null;
    }
  }

  /// Call a GL.iNet API method.
  Future<Map<String, dynamic>?> call(
    String host,
    bool useHttps,
    String module,
    String function, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (_sid == null) return null;
    try {
      final client = _httpClientManager.getClient(host, useHttps);
      final baseUrl = '${useHttps ? 'https' : 'http'}://$host';

      final resp = await client.post<Map<String, dynamic>>(
        '$baseUrl/rpc',
        data: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'call',
          'params': [_sid, module, function, args],
        }),
        options: Options(contentType: 'application/json'),
      );

      return resp.data?['result'] as Map<String, dynamic>?;
    } catch (e) {
      Logger.warning('GL.iNet API call $module.$function failed: $e');
      return null;
    }
  }

  /// Get WiFi status from GL.iNet API.
  /// Returns map of radio name → {channel, band} (e.g., {"wifi0": {"channel": 1, "band": "2g"}}).
  Future<Map<String, Map<String, dynamic>>> getWifiStatus(
    String host,
    bool useHttps,
  ) async {
    final result = await call(host, useHttps, 'wifi', 'get_status');
    if (result == null) return {};

    final radios = <String, Map<String, dynamic>>{};
    final res = result['res'] as List<dynamic>? ?? [];
    for (final radio in res) {
      final name = radio['name'] as String?;
      if (name != null) {
        radios[name] = {
          'channel': radio['channel'] as int? ?? 0,
          'band': radio['band'] as String? ?? '',
        };
      }
    }
    return radios;
  }

  /// Get client list for enrichment. Returns map of MAC → client data.
  Future<Map<String, Map<String, dynamic>>> getClients(
    String host,
    bool useHttps,
  ) async {
    final result = await call(host, useHttps, 'clients', 'get_list');
    if (result == null) return {};

    final clients = <String, Map<String, dynamic>>{};
    final list = result['clients'] as List<dynamic>? ?? [];
    for (final c in list) {
      final mac = (c['mac'] as String?)?.toLowerCase();
      if (mac != null) {
        clients[mac] = {
          'online': c['online'] as bool? ?? false,
          'iface': c['iface'] as String?, // "2G", "5G", "6G"
          'class': c['class'] as String?, // "phone", "laptop"
          'name': c['name'] as String?,
          'alias': c['alias'] as String?,
        };
      }
    }
    return clients;
  }

  /// Get system extras: CPU temperature and fan status.
  Future<Map<String, dynamic>> getSystemExtras(
    String host,
    bool useHttps,
  ) async {
    final extras = <String, dynamic>{};

    // CPU temperature from system.get_status
    final sysStatus = await call(host, useHttps, 'system', 'get_status');
    if (sysStatus != null) {
      final sys = sysStatus['system'] as Map<String, dynamic>?;
      final cpu = sys?['cpu'] as Map<String, dynamic>?;
      extras['cpu_temperature'] = cpu?['temperature'] as int?;
    }

    // Fan status
    final fanStatus = await call(host, useHttps, 'fan', 'get_status');
    if (fanStatus != null) {
      extras['fan_speed'] = fanStatus['speed'] as int?;
      extras['fan_active'] = fanStatus['status'] as bool?;
    }

    // Tailscale status
    final tsStatus = await call(host, useHttps, 'tailscale', 'get_status');
    if (tsStatus != null) {
      extras['tailscale_ip'] = tsStatus['address_v4'] as String?;
      extras['tailscale_login'] = tsStatus['login_name'] as String?;
      extras['tailscale_status'] = tsStatus['status'] as int?;
    }

    return extras;
  }
}
