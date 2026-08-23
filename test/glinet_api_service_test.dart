import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/glinet_data.dart';
import 'package:luci_mobile/services/glinet_api_service.dart';
import 'package:luci_mobile/services/mock_glinet_api_service.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';
import 'package:luci_mobile/utils/wifi_utils.dart';

void main() {
  test('session state can be cleared after authentication', () async {
    final server = await _startRpcServer((request) {
      return switch (request['method']) {
        'challenge' => _result({
          'nonce': 'nonce',
          'salt': 'salt',
          'alg': 5,
          'hash-method': 'sha256',
        }),
        'login' => _result({'sid': 'sid-1'}),
        _ => _result({}),
      };
    });
    addTearDown(() => server.close(force: true));

    final service = GlInetApiService(HttpClientManager());
    await service.fetchData('127.0.0.1:${server.port}', 'password', false);
    expect(service.isAuthenticated, isTrue);
    service.clearSession();
    expect(service.isAuthenticated, isFalse);
  });

  test('reviewer service returns no vendor data', () async {
    final service = MockGlInetApiService();
    expect(await service.fetchData('router', 'password', false), isNull);
  });

  test('formats the documented 2G client band', () {
    final client = Client(
      ipAddress: '192.0.2.1',
      macAddress: '00:11:22:33:44:55',
      hostname: 'client',
      connectionType: ConnectionType.wireless,
      wifiBand: '2G',
    );

    expect(client.connectionLabel, '2.4 GHz');
  });

  test('ignores Wi-Fi channel placeholders', () {
    expect(normalizeWifiChannel('auto'), isNull);
    expect(normalizeWifiChannel('N/A'), isNull);
    expect(normalizeWifiChannel(' 44 '), '44');
  });

  test('prefers an actual channel for configuration-only networks', () {
    expect(resolveWifiChannel(actual: 44, configured: 'auto'), '44');
    expect(resolveWifiChannel(configured: '6'), '6');
    expect(resolveWifiChannel(configured: 'N/A'), 'N/A');
  });

  test('unwraps list-valued UCI device names', () {
    expect(uciString(['radio0']), 'radio0');
    expect(uciString([]), '');
  });

  test('maps GL.iNet radio names to UCI device names', () {
    const wifi = GlInetData(radios: {'wifi0': GlInetRadio(channel: 44)});
    const defaultRadio = GlInetData(
      radios: {'default_radio1': GlInetRadio(channel: 149)},
    );

    expect(wifi.radioForDevice('radio0')?.channel, 44);
    expect(defaultRadio.radioForDevice('radio1')?.channel, 149);
  });

  test('parses radio, client, system, fan, and Tailscale data', () async {
    final server = await _startRpcServer((request) {
      final method = request['method'];
      if (method == 'challenge') {
        return _result({
          'nonce': 'nonce',
          'salt': 'salt',
          'alg': 5,
          'hash-method': 'sha256',
        });
      }
      if (method == 'login') return _result({'sid': 'sid-1'});

      final module = (request['params'] as List)[1];
      return switch (module) {
        'wifi' => _result({
          'res': [
            {'name': 'wifi0', 'channel': '44', 'band': '5g'},
          ],
        }),
        'clients' => _result({
          'clients': [
            {'mac': 'AA:BB:CC:DD:EE:FF', 'online': 1, 'iface': '5G'},
            {'mac': 'AA:BB:CC:DD:EE:00', 'online': 1, 'iface': 'cable'},
            {'mac': 'AA-BB-CC-DD-EE-01', 'online': 1, 'iface': 'wlan0'},
          ],
        }),
        'system' => _result({
          'system': {
            'cpu': {'temperature': 45.5},
          },
        }),
        'fan' => _result({'speed': '1200', 'status': 1}),
        'tailscale' => _result({'address_v4': '100.64.0.1'}),
        _ => _result({}),
      };
    });
    addTearDown(() => server.close(force: true));

    final data = await GlInetApiService(
      HttpClientManager(),
    ).fetchData('127.0.0.1:${server.port}', 'password', false);

    expect(data?.radios['wifi0']?.channel, 44);
    expect(data?.clients['aa:bb:cc:dd:ee:ff']?.online, isTrue);
    expect(data?.clients['aa:bb:cc:dd:ee:ff']?.wifiBand, '5G');
    expect(data?.clients['aa:bb:cc:dd:ee:00']?.wifiBand, isNull);
    expect(data?.clients['aa:bb:cc:dd:ee:01']?.wifiBand, isNull);
    expect(data?.cpuTemperature, 45.5);
    expect(data?.fanSpeed, 1200);
    expect(data?.fanActive, isTrue);
    expect(data?.tailscaleIp, '100.64.0.1');
  });

  test('reauthenticates once when the session expires', () async {
    var loginCount = 0;
    var expired = false;
    final callSids = <String>[];
    final server = await _startRpcServer((request) {
      final method = request['method'];
      if (method == 'challenge') {
        return _result({
          'nonce': 'nonce',
          'salt': 'salt',
          'alg': 5,
          'hash-method': 'sha256',
        });
      }
      if (method == 'login') {
        loginCount++;
        return _result({'sid': 'sid-$loginCount'});
      }
      callSids.add((request['params'] as List).first as String);
      if (!expired) {
        expired = true;
        return {
          'jsonrpc': '2.0',
          'id': 1,
          'error': {'code': -32000, 'message': 'Access denied'},
        };
      }
      final module = (request['params'] as List)[1];
      if (module == 'wifi') {
        return _result({
          'res': [
            {'name': 'wifi0', 'channel': 44},
          ],
        });
      }
      return _result({});
    });
    addTearDown(() => server.close(force: true));

    final data = await GlInetApiService(
      HttpClientManager(),
    ).fetchData('127.0.0.1:${server.port}', 'password', false);

    expect(loginCount, 2);
    expect(callSids.take(2), ['sid-1', 'sid-2']);
    expect(data?.radios['wifi0']?.channel, 44);
  });
}

Map<String, dynamic> _result(Map<String, dynamic> result) => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': result,
};

Future<HttpServer> _startRpcServer(
  Map<String, dynamic> Function(Map<String, dynamic>) respond,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final body = jsonDecode(await utf8.decoder.bind(request).join());
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(respond(Map<String, dynamic>.from(body))),
    );
    await request.response.close();
  });
  return server;
}
