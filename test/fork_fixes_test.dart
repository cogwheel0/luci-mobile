import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/diagnostics_service.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/router_session.dart';
import 'package:luci_mobile/widgets/wifi_qr_sheet.dart';

const _session = RouterSession(
  routerId: 'r1',
  ipAddress: '192.168.1.1',
  sysauth: 'sid',
  useHttps: false,
  token: 1,
);

/// Grants `file.exec` only for the exact command lines in [allowed], the way
/// rpcd matches LuCI's ACL.
class _AclApi extends MockApiService {
  _AclApi(this.allowed, {this.output = 'line'});

  final Set<String> allowed;
  final String output;
  final tried = <String>[];

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
    final line = [
      params!['command'] as String,
      ...(params['params'] as List).cast<String>(),
    ].join(' ');
    tried.add(line);
    if (!allowed.contains(line)) {
      throw const RpcException(object: 'file', method: 'exec', status: 6);
    }
    return [
      0,
      {'code': 0, 'stdout': output},
    ];
  }
}

void main() {
  group('logs and tools run under LuCI ACL (issue #91)', () {
    test('kernel log asks for exactly `dmesg -r`', () async {
      final api = _AclApi({'/bin/dmesg -r'});
      final result = await DiagnosticsService(api).kernelLog(_session);
      expect(result.succeeded, isTrue);
      expect(api.tried.first, '/bin/dmesg -r');
    });

    test('system log falls back to `logread -e ^` on 22.03', () async {
      final api = _AclApi({'/sbin/logread -e ^'});
      final result = await DiagnosticsService(api).systemLog(_session);
      expect(result.succeeded, isTrue);
      expect(api.tried, [
        '/usr/libexec/syslog-wrapper',
        '/sbin/logread -e ^',
      ]);
    });

    test('system log is trimmed to the newest lines', () async {
      final api = _AclApi({
        '/usr/libexec/syslog-wrapper',
      }, output: List.generate(10, (i) => 'l$i').join('\n'));
      final result = await DiagnosticsService(
        api,
      ).systemLog(_session, lines: 3);
      expect(result.output, 'l7\nl8\nl9');
    });

    test('traceroute tries the other granted path', () async {
      final api = _AclApi({'/bin/traceroute -n -w 1 -q 1 -m 15 8.8.8.8'});
      final result = await DiagnosticsService(
        api,
      ).run(_session, DiagnosticTool.traceroute, '8.8.8.8');
      expect(result.succeeded, isTrue);
    });

    test('nothing granted is still a refusal', () async {
      await expectLater(
        DiagnosticsService(_AclApi({})).kernelLog(_session),
        throwsA(isA<RpcException>().having((e) => e.status, 'status', 6)),
      );
    });

    test('dmesg -r lines carry their level', () {
      final e = LogEntry.parseKernel('<3>[   12.500000] eth0: link failed');
      expect(e.level, 'err');
      expect(e.isProblem, isTrue);
      expect(e.message, 'eth0: link failed');
      expect(e.timestamp, '12.500000s');
    });
  });

  group('throughput orientation (issue #81)', () {
    test('only the uplink counts, and LAN faces clients', () {
      final split = AppState.throughputDevices({
        'interface': [
          {
            'interface': 'lan',
            'device': 'br-lan',
            'route': <dynamic>[],
          },
          {
            'interface': 'wan',
            'device': 'eth1',
            'l3_device': 'pppoe-wan',
            'route': [
              {'target': '0.0.0.0', 'mask': 0},
            ],
          },
          {'interface': 'loopback', 'device': 'lo'},
        ],
      });
      expect(split.upstream, {'eth1', 'pppoe-wan'});
      expect(split.downstream, {'br-lan'});
    });
  });

  group('client names from host hints (issue #75)', () {
    test('an unnamed client takes its /etc/ethers name', () {
      final clients = {
        'AA:BB:CC:DD:EE:FF': Client.fromLease({
          'macaddr': 'aa:bb:cc:dd:ee:ff',
          'ipaddr': '192.168.1.9',
        }),
        '11:22:33:44:55:66': Client.fromLease({
          'macaddr': '11:22:33:44:55:66',
          'hostname': 'laptop',
        }),
      };
      AppState.applyHostHintNames(clients, {
        'AA:BB:CC:DD:EE:FF': {'name': 'printer'},
        '11:22:33:44:55:66': {'name': 'other'},
      });
      expect(clients['AA:BB:CC:DD:EE:FF']!.hostname, 'printer');
      // A name the client chose itself is not overridden.
      expect(clients['11:22:33:44:55:66']!.hostname, 'laptop');
    });
  });

  group('Wi-Fi QR payload (issue #37)', () {
    test('WPA2 with characters that need escaping', () {
      expect(
        wifiQrPayload(ssid: 'My;Net', encryption: 'psk2+ccmp', key: r'a:b\c'),
        r'WIFI:T:WPA;S:My\;Net;P:a\:b\\c;;',
      );
    });

    test('open and WPA3-only networks', () {
      expect(
        wifiQrPayload(ssid: 'Guest', encryption: 'none', key: 'x'),
        'WIFI:T:nopass;S:Guest;;',
      );
      expect(
        wifiQrPayload(ssid: 'W3', encryption: 'sae', key: 'k', hidden: true),
        'WIFI:T:SAE;S:W3;P:k;H:true;;',
      );
      expect(
        wifiQrPayload(ssid: 'Mix', encryption: 'sae-mixed', key: 'k'),
        'WIFI:T:WPA;S:Mix;P:k;;',
      );
    });
  });

  group('language tags', () {
    test('round-trip, script codes included', () {
      for (final tag in ['ru', 'en', 'zh_Hant']) {
        expect(AppState.localeTag(AppState.parseLocaleTag(tag)!), tag);
      }
      expect(AppState.parseLocaleTag(''), isNull);
      expect(AppState.parseLocaleTag(null), isNull);
    });
  });
}
