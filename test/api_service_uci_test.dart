import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/api_service.dart';

void main() {
  test('UCI calls reject errors and can delete a single option', () async {
    final requests = <Map<String, dynamic>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final payload = jsonDecode(await utf8.decoder.bind(request).join());
      requests.add(Map<String, dynamic>.from(payload));
      final method = payload['params'][2];
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'result': method == 'delete'
              ? [0, {}]
              : method == 'exec'
              ? [
                  0,
                  {'code': 1, 'stderr': 'forced exit'},
                ]
              : [4, 'forced failure'],
        }),
      );
      await request.response.close();
    });

    final service = RealApiService();
    final host = '127.0.0.1:${server.port}';
    await service.uciDelete(
      host,
      'token',
      false,
      config: 'wireless',
      section: 'wifinet0',
      option: 'key',
    );
    expect(requests.single['params'][3]['option'], 'key');

    await expectLater(
      service.uciCommit(host, 'token', false, config: 'network'),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('uci.commit failed: forced failure'),
        ),
      ),
    );

    await expectLater(
      service.systemExec(host, 'token', false, command: '/sbin/false'),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('file.exec failed: forced exit'),
        ),
      ),
    );
  });

  test('a stale scan cannot clear the active cancellation token', () async {
    final firstRequest = Completer<HttpRequest>();
    final secondRequest = Completer<HttpRequest>();
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      (requestCount++ == 0 ? firstRequest : secondRequest).complete(request);
    });

    final service = RealApiService();
    final host = '127.0.0.1:${server.port}';
    final firstScan = service.scanWirelessNetworks(
      ipAddress: host,
      sysauth: 'token',
      useHttps: false,
      device: 'radio0',
    );
    await firstRequest.future;

    final secondScan = service.scanWirelessNetworks(
      ipAddress: host,
      sysauth: 'token',
      useHttps: false,
      device: 'radio1',
    );
    await secondRequest.future;
    expect(await firstScan.timeout(const Duration(seconds: 1)), isEmpty);

    service.cancelScan();
    expect(await secondScan.timeout(const Duration(seconds: 1)), isEmpty);
  });
}
