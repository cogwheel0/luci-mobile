import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/wol_service.dart';
import 'package:luci_mobile/state/router_session.dart';

class _ConfigApi extends MockApiService {
  Map<String, dynamic>? etherwake;
  Map<String, dynamic>? luciWol;
  Map<String, dynamic>? network;
  Object? execReply;
  Object readError = Exception('timeout');

  /// `luci.wol stat` reply; null means the object does not exist (legacy).
  Map<String, dynamic>? stat;
  int reads = 0;
  int statCalls = 0;
  String? execObject;
  String? execName;
  List<String>? sentParams;

  @override
  Future<dynamic> uciGetAll(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    final values = switch (config) {
      'etherwake' => etherwake,
      'luci-wol' => luciWol,
      'network' => network,
      _ => null,
    };
    if (config == 'etherwake') reads++;
    if (values == null) throw readError;
    return [
      0,
      {'values': values},
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
    if (object == 'luci.wol' && method == 'stat') {
      statCalls++;
      if (stat == null) {
        throw RpcException(object: object, method: method, status: 4);
      }
      return [0, stat];
    }
    execObject = object;
    if (object == 'luci.wol') {
      execName = params?['name'] as String?;
      sentParams = (params?['args'] as List).cast<String>();
    } else {
      sentParams = (params?['params'] as List).cast<String>();
    }
    return execReply ??
        [
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

  // Nothing acknowledges a magic packet, so this return value is the only
  // signal the user gets: a reply carrying no exit status is not a send.
  test('a reply with no exit status is not reported as sent', () async {
    final api = _ConfigApi()
      ..etherwake = {
        'setup': {'.type': 'etherwake', 'interface': 'br-lan'},
      }
      ..execReply = [0, 'sent'];

    expect(await WolService(api).wake(session, 'aa:bb:cc:dd:ee:ff'), isFalse);
  });

  // A router without luci-app-wol has no config; that answer is kept, so a
  // second wake does not pay for the same failed round trip.
  test('a missing etherwake config is asked about once', () async {
    final api = _ConfigApi()
      ..readError = const RpcException(object: 'uci', method: 'get', status: 4);
    final wol = WolService(api);

    await wol.wake(session, 'aa:bb:cc:dd:ee:ff');
    await wol.wake(session, 'aa:bb:cc:dd:ee:ff');

    expect(api.reads, 1);
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

  // OpenWrt 25.x's luci-app-wol has no `file.exec` grant and no `etherwake`
  // config: it goes through `luci.wol`, configured by `luci-wol`.
  group('modern luci-app-wol', () {
    test('wakes through luci.wol with the target\'s interface', () async {
      final api = _ConfigApi()
        ..stat = {'etherwake': true, 'wakeonlan': false}
        ..luciWol = {
          'defaults': {'.type': 'wol'},
          'cfg1': {
            '.type': 'target',
            'mac': 'AA:BB:CC:DD:EE:FF',
            'iface': 'br-lan',
            'broadcast': '1',
          },
        };

      expect(await WolService(api).wake(session, 'aa:bb:cc:dd:ee:ff'), isTrue);
      expect(api.execObject, 'luci.wol');
      expect(api.execName, WolService.etherwake);
      expect(api.sentParams, ['-D', '-i', 'br-lan', '-b', 'aa:bb:cc:dd:ee:ff']);
    });

    test('an unknown device goes out on the LAN device', () async {
      final api = _ConfigApi()
        ..stat = {'etherwake': true, 'wakeonlan': false}
        ..luciWol = {
          'defaults': {'.type': 'wol'},
        }
        ..network = {
          'lan': {'.type': 'interface', 'device': 'br-lan'},
        };

      expect(await WolService(api).wake(session, 'aa:bb:cc:dd:ee:ff'), isTrue);
      expect(api.sentParams, ['-D', '-i', 'br-lan', 'aa:bb:cc:dd:ee:ff']);
    });

    test('wakeonlan alone is used with just the MAC', () async {
      final api = _ConfigApi()
        ..stat = {'etherwake': false, 'wakeonlan': true}
        ..luciWol = {
          'defaults': {'.type': 'wol', 'executable': WolService.etherwake},
        };

      expect(await WolService(api).wake(session, 'aa:bb:cc:dd:ee:ff'), isTrue);
      expect(api.execName, WolService.wakeonlan);
      expect(api.sentParams, ['aa:bb:cc:dd:ee:ff']);
    });

    test('a disallowed binary is not reported as sent', () async {
      final api = _ConfigApi()
        ..stat = {'etherwake': true, 'wakeonlan': false}
        ..luciWol = {
          'defaults': {'.type': 'wol'},
        }
        ..execReply = [
          0,
          {'code': 1, 'stdout': '', 'stderr': 'disallowed'},
        ];

      expect(await WolService(api).wake(session, 'aa:bb:cc:dd:ee:ff'), isFalse);
    });

    test('neither binary installed sends nothing', () async {
      final api = _ConfigApi()..stat = {'etherwake': false, 'wakeonlan': false};

      expect(await WolService(api).wake(session, 'aa:bb:cc:dd:ee:ff'), isFalse);
      expect(api.sentParams, isNull);
    });

    test('which package is installed is asked once', () async {
      final api = _ConfigApi()
        ..stat = {'etherwake': true, 'wakeonlan': false}
        ..luciWol = {
          'defaults': {'.type': 'wol'},
        };
      final wol = WolService(api);

      await wol.wake(session, 'aa:bb:cc:dd:ee:ff');
      await wol.wake(session, 'aa:bb:cc:dd:ee:ff');
      expect(api.statCalls, 1);
    });
  });

  test('legacy wake goes through file.exec', () async {
    final api = _ConfigApi()
      ..etherwake = {
        'setup': {'.type': 'etherwake', 'interface': 'br-lan'},
      };

    expect(await WolService(api).wake(session, 'aa:bb:cc:dd:ee:ff'), isTrue);
    expect(api.execObject, 'file');
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
