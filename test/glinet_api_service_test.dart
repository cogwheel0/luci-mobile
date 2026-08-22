import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/glinet_api_service.dart';
import 'package:luci_mobile/services/mock_glinet_api_service.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';

void main() {
  test('session state can be cleared', () {
    final service = GlInetApiService(HttpClientManager());
    expect(service.isAuthenticated, isFalse);
    service.clearSession();
    expect(service.isAuthenticated, isFalse);
  });

  test('reviewer service returns no vendor data', () async {
    final service = MockGlInetApiService();
    expect(await service.fetchData('router', 'password', false), isNull);
  });

  test('parses firmware value variants independently', () async {
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

    final data = await GlInetApiService(HttpClientManager())
        .fetchData('127.0.0.1:${server.port}', 'password', false);

    expect(data?.radios['wifi0']?.channel, 44);
    expect(data?.clients['aa:bb:cc:dd:ee:ff']?.online, isTrue);
    expect(data?.cpuTemperature, 45.5);
    expect(data?.fanSpeed, 1200);
    expect(data?.fanActive, isTrue);
    expect(data?.tailscaleIp, '100.64.0.1');
  });

  test('reauthenticates once when the session expires', () async {
    var loginCount = 0;
    var expired = false;
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
      if (!expired) {
        expired = true;
        return {
          'jsonrpc': '2.0',
          'id': 1,
          'error': {'message': 'session expired'},
        };
      }
      return _result({});
    });
    addTearDown(() => server.close(force: true));

    await GlInetApiService(HttpClientManager())
        .fetchData('127.0.0.1:${server.port}', 'password', false);

    expect(loginCount, 2);
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
