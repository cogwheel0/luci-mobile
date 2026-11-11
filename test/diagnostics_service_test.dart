import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/diagnostics_service.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/state/router_session.dart';

const _session = RouterSession(
  routerId: 'r1',
  ipAddress: '192.168.1.1',
  sysauth: 'sid',
  useHttps: false,
  token: 1,
);

class _ExecApi extends MockApiService {
  dynamic reply;
  Map<String, dynamic>? lastParams;

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
    lastParams = params;
    if (reply is Exception) throw reply as Exception;
    if (reply is RpcException) throw reply as RpcException;
    return reply;
  }
}

/// Answers `file.exec` per command line, the way rpcd's ACL check does:
/// a command line it has no answer for is refused.
class _AclApi extends MockApiService {
  _AclApi(this.replies);

  /// `command arg arg` -> reply, or an RpcException to throw.
  final Map<String, Object> replies;
  final List<String> asked = [];

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
      params?['command'],
      ...(params?['params'] as List? ?? const []),
    ].join(' ');
    asked.add(line);
    final reply =
        replies[line] ??
        const RpcException(object: 'file', method: 'exec', status: 6);
    if (reply is RpcException) throw reply;
    return reply;
  }
}

List<Object> _stdout(String text) => [
  0,
  {'code': 0, 'stdout': text, 'stderr': ''},
];

const _notFound = RpcException(object: 'file', method: 'exec', status: 4);

void main() {
  group('logs use the exact command lines LuCI ACLs grant', () {
    test('24.10+: the syslog wrapper', () async {
      final api = _AclApi({
        '/usr/libexec/syslog-wrapper': _stdout(
          'Sun Sep 20 08:53:53 2026 daemon.notice netifd: up\n',
        ),
      });

      final result = await DiagnosticsService(api).systemLog(_session);

      expect(result.output, contains('netifd: up'));
      expect(api.asked, ['/usr/libexec/syslog-wrapper']);
    });

    // 21.02 to 23.05 have no wrapper (rpcd: not found) and grant
    // `logread -e ^` but not `logread -l 200`.
    test('older releases: logread -e ^', () async {
      final api = _AclApi({
        '/usr/libexec/syslog-wrapper': _notFound,
        '/sbin/logread -e ^': _stdout('line\n'),
      });

      final result = await DiagnosticsService(api).systemLog(_session);

      expect(result.output, 'line');
      expect(api.asked, ['/usr/libexec/syslog-wrapper', '/sbin/logread -e ^']);
    });

    test('only the last lines are kept', () async {
      final log = [for (var i = 1; i <= 300; i++) 'line $i'].join('\n');
      final api = _AclApi({'/usr/libexec/syslog-wrapper': _stdout(log)});

      final result = await DiagnosticsService(
        api,
      ).systemLog(_session, lines: 200);

      final lines = result.output.split('\n');
      expect(lines, hasLength(200));
      expect(lines.first, 'line 101');
      expect(lines.last, 'line 300');
    });

    // When nothing works, "you may not" is the useful answer - not the
    // "not found" from whichever candidate happened to be tried last.
    test('a refusal wins over not-found when every form fails', () async {
      final api = _AclApi({
        '/usr/libexec/syslog-wrapper': _notFound,
        '/usr/sbin/logread -e ^': _notFound,
      });

      await expectLater(
        DiagnosticsService(api).systemLog(_session),
        throwsA(isA<RpcException>().having((e) => e.status, 'status', 6)),
      );
    });

    test('a failure other than refusal or absence is not retried', () async {
      final api = _AclApi({
        '/usr/libexec/syslog-wrapper': const RpcException(
          object: 'file',
          method: 'exec',
          status: 7,
        ),
      });

      await expectLater(
        DiagnosticsService(api).systemLog(_session),
        throwsA(isA<RpcException>().having((e) => e.status, 'status', 7)),
      );
      expect(api.asked, hasLength(1));
    });

    test('kernel log: dmesg -r', () async {
      final api = _AclApi({
        '/bin/dmesg -r': _stdout('<6>[    0.000000] Booting Linux\n'),
      });

      final result = await DiagnosticsService(api).kernelLog(_session);

      expect(result.output, contains('Booting Linux'));
      expect(api.asked, ['/bin/dmesg -r']);
    });

    // "No log entries" would say the router had nothing to report; it was
    // the read that failed.
    test('a reader that fails and prints nothing is an error', () async {
      final api = _AclApi({
        '/usr/libexec/syslog-wrapper': [
          0,
          {'code': 1, 'stdout': '', 'stderr': 'Failed to connect to ubus'},
        ],
        '/bin/dmesg -r': [0, {}],
      });
      final service = DiagnosticsService(api);

      await expectLater(
        service.systemLog(_session),
        throwsA(
          isA<RpcException>().having(
            (e) => e.detail,
            'detail',
            'Failed to connect to ubus',
          ),
        ),
      );
      // Not retried: the older forms are ones this router would refuse.
      expect(api.asked, ['/usr/libexec/syslog-wrapper']);
      await expectLater(
        service.kernelLog(_session),
        throwsA(
          isA<RpcException>().having(
            (e) => e.detail,
            'detail',
            'no exit status',
          ),
        ),
      );
    });

    test('output that did arrive is kept whatever the exit code', () async {
      final api = _AclApi({
        '/usr/libexec/syslog-wrapper': [
          0,
          {'code': 1, 'stdout': 'partial\n', 'stderr': ''},
        ],
      });

      final result = await DiagnosticsService(api).systemLog(_session);

      expect(result.output, 'partial');
    });
  });

  test('dmesg -r priorities become severities', () {
    final warn = LogEntry.parse('<4>[   12.5] mt7915e: firmware timeout');
    expect(warn.isWarning, isTrue);
    expect(warn.message, '[   12.5] mt7915e: firmware timeout');
    // Copy and the filter use raw: it is the line as the router printed it.
    expect(warn.raw, '<4>[   12.5] mt7915e: firmware timeout');

    // Facility bits (here: user, 1 << 3) do not change the severity.
    expect(LogEntry.parse('<11>[ 1.0] oops').isProblem, isTrue);
    expect(LogEntry.parse('<6>[ 1.0] fine').isProblem, isFalse);
  });

  test('a bare ubus status is named in the error shown to the user', () {
    final info = describeApiError(_notFound);
    expect(info.kind, ApiErrorKind.rpcFailed);
    expect(info.detail, 'Not found (ubus status 4)');

    // The router's own message, when there is one, still wins.
    expect(
      describeApiError(
        const RpcException(object: 'x', method: 'y', status: 7, detail: 'busy'),
      ).detail,
      'busy',
    );
  });

  // A ping that gets no replies exits 1 with the loss statistics on stdout.
  // That output is the whole point of running it; it must not be reported as
  // the RPC having failed.
  test('a non-zero exit is a result, and its output is kept', () async {
    final api = _ExecApi()
      ..reply = [
        0,
        {
          'code': 1,
          'stdout': '5 packets transmitted, 0 received, 100% packet loss',
          'stderr': '',
        },
      ];

    final result = await DiagnosticsService(
      api,
    ).run(_session, DiagnosticTool.ping, '10.0.0.9');

    expect(result.succeeded, isFalse);
    expect(result.exitCode, 1);
    expect(result.output, contains('100% packet loss'));
    expect(api.lastParams?['command'], '/bin/ping');
  });

  // A body with no exit status is a run we cannot vouch for; calling it a
  // success turns "the log could not be read" into "the log is empty".
  test('a reply with no exit status is not a success', () async {
    final api = _ExecApi()..reply = [0, {}];

    final result = await DiagnosticsService(
      api,
    ).run(_session, DiagnosticTool.ping, '10.0.0.9');

    expect(result.succeeded, isFalse);
    expect(result.exitCode, -1);
  });

  test('an RPC-level refusal is still an error', () async {
    final api = _ExecApi()
      ..reply = const RpcException(object: 'file', method: 'exec', status: 6);

    await expectLater(
      DiagnosticsService(api).run(_session, DiagnosticTool.nslookup, 'x'),
      throwsA(isA<RpcException>().having((e) => e.status, 'status', 6)),
    );
  });
}
