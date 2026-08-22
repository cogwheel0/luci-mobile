import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:luci_mobile/models/glinet_data.dart';
import 'package:luci_mobile/services/interfaces/glinet_api_service_interface.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';
import 'package:luci_mobile/utils/logger.dart';
import 'package:luci_mobile/utils/sha256_crypt.dart';

/// Fetches supplementary data exposed by GL.iNet's `/rpc` API.
class GlInetApiService implements IGlInetApiService {
  final HttpClientManager _httpClientManager;

  GlInetApiService(this._httpClientManager);

  String? _sid;
  String? _lastHost;
  bool? _lastUseHttps;

  @override
  bool get isAuthenticated => _sid != null;

  @override
  void clearSession() {
    _sid = null;
    _lastHost = null;
    _lastUseHttps = null;
  }

  Future<String?> _login(String host, String password, bool useHttps) async {
    if (_sid != null && _lastHost == host && _lastUseHttps == useHttps) {
      return _sid;
    }

    try {
      final client = _httpClientManager.getClient(host, useHttps);
      final baseUrl = '${useHttps ? 'https' : 'http'}://$host';
      final challengeResp = await client.post<Map<String, dynamic>>(
        '$baseUrl/rpc',
        data: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'challenge',
          'params': {'username': 'root'},
        }),
        options: Options(contentType: Headers.jsonContentType),
      );

      final challenge = _asMap(challengeResp.data?['result']);
      final nonce = _asString(challenge?['nonce']);
      final salt = _asString(challenge?['salt']);
      if (nonce == null || salt == null) return null;

      final algorithm = _asInt(challenge?['alg']) ?? 1;
      final cipherPassword = algorithm == 5
          ? Sha256Crypt.hash(password, salt)
          : crypto.md5.convert(utf8.encode('root:$password')).toString();
      if (algorithm != 5) {
        Logger.warning(
          'GL.iNet router uses legacy MD5 auth (alg=$algorithm). '
          'Consider upgrading its firmware.',
        );
      }

      final loginInput = 'root:$cipherPassword:$nonce';
      final hashMethod = _asString(challenge?['hash-method']) ?? 'md5';
      final loginHash = hashMethod == 'sha256'
          ? crypto.sha256.convert(utf8.encode(loginInput)).toString()
          : crypto.md5.convert(utf8.encode(loginInput)).toString();
      final loginResp = await client.post<Map<String, dynamic>>(
        '$baseUrl/rpc',
        data: jsonEncode({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'login',
          'params': {'username': 'root', 'hash': loginHash},
        }),
        options: Options(contentType: Headers.jsonContentType),
      );

      _sid = _asString(_asMap(loginResp.data?['result'])?['sid']);
      _lastHost = _sid == null ? null : host;
      _lastUseHttps = _sid == null ? null : useHttps;
      return _sid;
    } catch (error) {
      Logger.warning('GL.iNet login failed: $error');
      clearSession();
      return null;
    }
  }

  Future<Map<String, dynamic>?> _call(
    String host,
    String password,
    bool useHttps,
    String module,
    String function, [
    Map<String, dynamic> args = const {},
    bool retryExpiredSession = true,
  ]) async {
    if (await _login(host, password, useHttps) == null) return null;

    try {
      final client = _httpClientManager.getClient(host, useHttps);
      final response = await client.post<Map<String, dynamic>>(
        '${useHttps ? 'https' : 'http'}://$host/rpc',
        data: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'call',
          'params': [_sid, module, function, args],
        }),
        options: Options(contentType: Headers.jsonContentType),
      );
      final result = _asMap(response.data?['result']);
      if (result != null) return result;

      if (retryExpiredSession && _isAuthenticationError(response.data)) {
        clearSession();
        return await _call(
          host,
          password,
          useHttps,
          module,
          function,
          args,
          false,
        );
      }
    } catch (error) {
      Logger.warning('GL.iNet API call $module.$function failed: $error');
    }
    return null;
  }

  @override
  Future<GlInetData?> fetchData(
    String host,
    String password,
    bool useHttps,
  ) async {
    if (await _login(host, password, useHttps) == null) return null;

    final radios = <String, GlInetRadio>{};
    final wifi = await _call(host, password, useHttps, 'wifi', 'get_status');
    for (final value in _asList(wifi?['res'])) {
      final radio = _asMap(value);
      final name = _asString(radio?['name']);
      if (name != null) {
        radios[name] = GlInetRadio(
          channel: _asInt(radio?['channel']),
          band: _asString(radio?['band']),
        );
      }
    }

    final clients = <String, GlInetClient>{};
    final clientResult = await _call(
      host,
      password,
      useHttps,
      'clients',
      'get_list',
    );
    for (final value in _asList(clientResult?['clients'])) {
      final client = _asMap(value);
      final mac = _asString(client?['mac'])?.toLowerCase();
      if (mac != null) {
        clients[mac] = GlInetClient(
          online: _asBool(client?['online']),
          wifiBand: _asString(client?['iface']),
          deviceClass: _asString(client?['class']),
          name: _asString(client?['name']),
          alias: _asString(client?['alias']),
        );
      }
    }

    final system = await _call(
      host,
      password,
      useHttps,
      'system',
      'get_status',
    );
    final cpu = _asMap(_asMap(system?['system'])?['cpu']);
    final fan = await _call(host, password, useHttps, 'fan', 'get_status');
    final tailscale = await _call(
      host,
      password,
      useHttps,
      'tailscale',
      'get_status',
    );

    return GlInetData(
      radios: radios,
      clients: clients,
      cpuTemperature: _asDouble(cpu?['temperature']),
      fanSpeed: _asInt(fan?['speed']),
      fanActive: _asBool(fan?['status']),
      tailscaleIp: _asString(tailscale?['address_v4']),
      tailscaleLogin: _asString(tailscale?['login_name']),
      tailscaleStatus: _asInt(tailscale?['status']),
    );
  }

  static bool _isAuthenticationError(Map<String, dynamic>? response) {
    final error = response?['error'];
    if (error == null) return false;
    final text = error.toString().toLowerCase();
    return text.contains('auth') ||
        text.contains('login') ||
        text.contains('permission') ||
        text.contains('session') ||
        text.contains('sid');
  }

  static Map<String, dynamic>? _asMap(dynamic value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : null;

  static List<dynamic> _asList(dynamic value) =>
      value is List ? value : const [];

  static String? _asString(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;

  static int? _asInt(dynamic value) => switch (value) {
    int number => number,
    num number => number.toInt(),
    String text => int.tryParse(text),
    _ => null,
  };

  static double? _asDouble(dynamic value) => switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };

  static bool? _asBool(dynamic value) => switch (value) {
    bool flag => flag,
    num number => number != 0,
    String text when text == '1' || text.toLowerCase() == 'true' => true,
    String text when text == '0' || text.toLowerCase() == 'false' => false,
    _ => null,
  };
}
