import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/api_service.dart';

/// Spins up a loopback server that answers every ubus call with [reply],
/// recording the JSON-RPC payloads it received.
Future<(String host, List<Map<String, dynamic>> requests)> _serve(
  dynamic Function(String method) reply,
) async {
  final requests = <Map<String, dynamic>>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    final payload = jsonDecode(await utf8.decoder.bind(request).join());
    requests.add(Map<String, dynamic>.from(payload));
    final method = payload['params'][2] as String;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': reply(method)}),
    );
    await request.response.close();
  });
  return ('127.0.0.1:${server.port}', requests);
}

void main() {
  group('uci apply/confirm wire format', () {
    test('uciApply sends rollback and timeout', () async {
      final (host, requests) = await _serve((_) => [0, {}]);

      await RealApiService().uciApply(
        host,
        'token',
        false,
        rollback: true,
        timeoutSeconds: 90,
      );

      final params = requests.single['params'] as List<dynamic>;
      expect(params[0], 'token');
      expect(params[1], 'uci');
      expect(params[2], 'apply');
      expect(params[3], {'rollback': true, 'timeout': 90});
    });

    test('unchecked apply sends rollback false', () async {
      final (host, requests) = await _serve((_) => [0, {}]);

      await RealApiService().uciApply(
        host,
        'token',
        false,
        rollback: false,
        timeoutSeconds: 0,
      );

      expect(requests.single['params'][3], {'rollback': false, 'timeout': 0});
    });

    test('uciConfirm sends no params', () async {
      final (host, requests) = await _serve((_) => [0, {}]);

      await RealApiService().uciConfirm(host, 'token', false);

      final params = requests.single['params'] as List<dynamic>;
      expect(params[2], 'confirm');
      expect(params[3], isEmpty);
    });

    test('uciRevert targets one config', () async {
      final (host, requests) = await _serve((_) => [0, {}]);

      await RealApiService().uciRevert(
        host,
        'token',
        false,
        config: 'wireless',
      );

      expect(requests.single['params'][2], 'revert');
      expect(requests.single['params'][3], {'config': 'wireless'});
    });

    test('uciRollback sends no params', () async {
      final (host, requests) = await _serve((_) => [0, {}]);

      await RealApiService().uciRollback(host, 'token', false);

      expect(requests.single['params'][2], 'rollback');
    });

    test('a non-zero status raises RpcException carrying the code', () async {
      final (host, _) = await _serve((_) => [6, 'Access denied']);

      await expectLater(
        RealApiService().uciConfirm(host, 'token', false),
        throwsA(
          isA<RpcException>()
              .having((e) => e.status, 'status', 6)
              .having((e) => e.method, 'method', 'confirm'),
        ),
      );
    });
  });

  group('uci.configs', () {
    test('unwraps the configs list', () async {
      final (host, _) = await _serve(
        (_) => [
          0,
          {
            'configs': ['dhcp', 'firewall', 'network'],
          },
        ],
      );

      final configs = await RealApiService().uciConfigs(host, 'token', false);

      expect(configs, ['dhcp', 'firewall', 'network']);
    });

    test('returns empty when the router omits the key', () async {
      final (host, _) = await _serve((_) => [0, {}]);

      expect(await RealApiService().uciConfigs(host, 'token', false), isEmpty);
    });
  });

  group('uci.changes', () {
    test('normalizes the unfiltered map shape', () async {
      final (host, requests) = await _serve(
        (_) => [
          0,
          {
            'changes': {
              'dhcp': [
                ['set', 'cfg01', 'name', 'laptop'],
              ],
              'firewall': [
                ['add', 'cfg02', 'rule'],
                ['remove', 'cfg03'],
              ],
            },
          },
        ],
      );

      final changes = await RealApiService().uciChanges(host, 'token', false);

      // No config filter means no params entry for it.
      expect(requests.single['params'][3], isEmpty);
      expect(changes.keys, containsAll(<String>['dhcp', 'firewall']));
      expect(changes['dhcp']!.single, ['set', 'cfg01', 'name', 'laptop']);
      expect(changes['firewall'], hasLength(2));
      expect(changes['firewall']![1], ['remove', 'cfg03']);
    });

    test('normalizes the filtered list shape under its config key', () async {
      final (host, requests) = await _serve(
        (_) => [
          0,
          {
            'changes': [
              ['set', 'cfg01', 'ip', '192.168.1.50'],
            ],
          },
        ],
      );

      final changes = await RealApiService().uciChanges(
        host,
        'token',
        false,
        config: 'dhcp',
      );

      expect(requests.single['params'][3], {'config': 'dhcp'});
      expect(changes, hasLength(1));
      expect(changes['dhcp']!.single, ['set', 'cfg01', 'ip', '192.168.1.50']);
    });

    test('an empty change list yields an empty map', () async {
      final (host, _) = await _serve(
        (_) => [
          0,
          {'changes': <dynamic>[]},
        ],
      );

      final changes = await RealApiService().uciChanges(
        host,
        'token',
        false,
        config: 'dhcp',
      );

      expect(changes, isEmpty);
    });
  });
}
