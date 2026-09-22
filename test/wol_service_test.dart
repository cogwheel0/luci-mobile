import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/wol_service.dart';
import 'package:luci_mobile/state/router_session.dart';

class _ConfigApi extends MockApiService {
  Map<String, dynamic>? etherwake;
  List<String>? sentParams;

  @override
  Future<dynamic> uciGetAll(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    if (etherwake == null) throw Exception('no such config');
    return [
      0,
      {'values': etherwake},
    ];
  }

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    sentParams = (params?['params'] as List).cast<String>();
    return [
      0,
      {'code': 0, 'stdout': 'sent'},
    ];
  }
}

void main() {
  const session = RouterSession(
    routerId: 'r1',
    ipAddress: '192.168.1.1',
    sysauth: 'sid',
    useHttps: false,
    token: 1,
  );

  // Without `-i`, etherwake sends on eth0 - the switch conduit on a DSA
  // router, where the frame never reaches a LAN port. luci-app-wol's own
  // config says which interface to use.
  test('wake sends on the interface etherwake is configured for', () async {
    final api = _ConfigApi()
      ..etherwake = {
        'setup': {'.type': 'etherwake', 'interface': 'br-lan'},
      };

    expect(await WolService(api).wake(session, 'aa:bb:cc:dd:ee:ff'), isTrue);
    expect(api.sentParams, ['-D', '-i', 'br-lan', 'aa:bb:cc:dd:ee:ff']);
  });

  test('an unreadable etherwake config falls back to no interface', () async {
    final api = _ConfigApi();

    expect(await WolService(api).wake(session, 'aa:bb:cc:dd:ee:ff'), isTrue);
    expect(api.sentParams, ['-D', 'aa:bb:cc:dd:ee:ff']);
  });

  // One timeout must not send every later wake on the wrong interface.
  test('a failed config read is retried on the next wake', () async {
    final api = _ConfigApi();
    final wol = WolService(api);

    await wol.wake(session, 'aa:bb:cc:dd:ee:ff');
    expect(api.sentParams, ['-D', 'aa:bb:cc:dd:ee:ff']);

    api.etherwake = {
      'setup': {'.type': 'etherwake', 'interface': 'br-lan'},
    };
    await wol.wake(session, 'aa:bb:cc:dd:ee:ff');
    expect(api.sentParams, ['-D', '-i', 'br-lan', 'aa:bb:cc:dd:ee:ff']);

    // An answer, on the other hand, is kept.
    api.etherwake = null;
    await wol.wake(session, 'aa:bb:cc:dd:ee:ff');
    expect(api.sentParams, ['-D', '-i', 'br-lan', 'aa:bb:cc:dd:ee:ff']);
  });

  group('normalising a MAC for etherwake', () {
    test('accepts the forms the app already holds', () {
      expect(WolService.normaliseMac('AA:BB:CC:11:22:33'), 'aa:bb:cc:11:22:33');
      expect(WolService.normaliseMac('aa-bb-cc-11-22-33'), 'aa:bb:cc:11:22:33');
      expect(
        WolService.normaliseMac('  AA:bb:CC:11:22:33 '),
        'aa:bb:cc:11:22:33',
      );
    });

    // A client with no lease carries the literal 'N/A', and handing that to
    // etherwake would be a shell argument nobody meant to send.
    test('rejects anything that is not a MAC', () {
      expect(WolService.normaliseMac('N/A'), isNull);
      expect(WolService.normaliseMac(''), isNull);
      expect(WolService.normaliseMac('aa:bb:cc:11:22'), isNull);
      expect(WolService.normaliseMac('aa:bb:cc:11:22:33:44'), isNull);
      expect(WolService.normaliseMac('zz:bb:cc:11:22:33'), isNull);
      expect(WolService.normaliseMac('192.168.1.1'), isNull);
    });
  });

  group('building the etherwake call', () {
    test('asks for output, because nothing else reports success', () {
      expect(WolService.argsFor('aa:bb:cc:11:22:33'), [
        '-D',
        'aa:bb:cc:11:22:33',
      ]);
    });

    test('an interface is passed through when known', () {
      expect(WolService.argsFor('aa:bb:cc:11:22:33', device: 'br-lan'), [
        '-D',
        '-i',
        'br-lan',
        'aa:bb:cc:11:22:33',
      ]);
    });

    test('an empty interface is left out rather than passed as blank', () {
      expect(WolService.argsFor('aa:bb:cc:11:22:33', device: ''), [
        '-D',
        'aa:bb:cc:11:22:33',
      ]);
    });
  });
}
