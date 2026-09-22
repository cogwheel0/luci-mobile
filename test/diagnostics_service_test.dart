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

void main() {
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
