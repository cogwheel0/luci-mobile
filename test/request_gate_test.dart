import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';

/// A router stand-in that counts how many requests it holds at once.
///
/// With [hangWhenParallel] it behaves like the LuCI builds in
/// openwrt/luci#9091: a request that arrives while another is open is never
/// answered, and is let go only when the client gives up on it.
class _Router {
  _Router._(this._server, this.hangWhenParallel) {
    _server.listen(_serve);
  }

  static Future<_Router> start({bool hangWhenParallel = false}) async =>
      _Router._(
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        hangWhenParallel,
      );

  final ServerSocket _server;
  final bool hangWhenParallel;
  int _open = 0;
  int maxOpen = 0;

  String get host => '127.0.0.1:${_server.port}';

  void _serve(Socket socket) {
    final received = StringBuffer();
    var counted = false;
    var finished = false;
    void finish() {
      if (finished) return;
      finished = true;
      if (counted) _open--;
    }

    socket.listen(
      (data) async {
        received.write(latin1.decode(data));
        if (counted || !received.toString().contains('\r\n\r\n')) return;
        counted = true;
        final parallel = _open > 0;
        _open++;
        if (_open > maxOpen) maxOpen = _open;
        if (hangWhenParallel && parallel) return;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        finish();
        socket.write(
          'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n'
          'Connection: close\r\n\r\nok',
        );
        await socket.close();
      },
      onDone: finish,
      onError: (_) => finish(),
      cancelOnError: true,
    );
  }

  Future<void> close() => _server.close();
}

Future<Object> _get(Dio dio, _Router router, {Duration? timeout}) async {
  try {
    final response = await dio.get<String>(
      'http://${router.host}/',
      options: Options(receiveTimeout: timeout),
    );
    return response.data!;
  } catch (e) {
    return e;
  }
}

// No TestWidgetsFlutterBinding: it swaps in an HttpClient that answers every
// request with a 400.
void main() {
  // uhttpd runs three LuCI requests at once by default and queues the rest
  // with their receive timeout already running; the app's own bursts were
  // up to fourteen wide.
  test('no more than three requests reach a router at once', () async {
    final router = await _Router.start();
    addTearDown(router.close);
    final dio = HttpClientManager().getClient(router.host, false);

    final results = await Future.wait([
      for (var i = 0; i < 10; i++) _get(dio, router),
    ]);

    expect(results, everyElement('ok'));
    expect(router.maxOpen, 3);
  });

  test(
    'a router that hangs parallel requests is then sent one at a time',
    () async {
      final router = await _Router.start(hangWhenParallel: true);
      addTearDown(router.close);
      final dio = HttpClientManager().getClient(router.host, false);
      const timeout = Duration(milliseconds: 300);

      final burst = await Future.wait([
        for (var i = 0; i < 6; i++) _get(dio, router, timeout: timeout),
      ]);
      expect(
        burst.whereType<DioException>().map((e) => e.type),
        everyElement(DioExceptionType.receiveTimeout),
      );
      expect(HttpClientManager().maxInFlightFor(router.host, false), 1);

      // Let the router notice the abandoned requests.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final after = await Future.wait([
        for (var i = 0; i < 3; i++) _get(dio, router, timeout: timeout),
      ]);
      expect(after, everyElement('ok'));
    },
  );
}
