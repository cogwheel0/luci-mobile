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
          'result': method == 'delete' ? [0, {}] : [4, 'forced failure'],
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
  });
}
