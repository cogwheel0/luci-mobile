import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/l10n/failure_text.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/services/api_service.dart';

void main() {
  // The widget-test binding answers every HttpClient request with 400 so
  // tests cannot reach the network by accident; this one talks to its own
  // loopback server on purpose.
  setUpAll(() => HttpOverrides.global = null);

  // #89, from the transport all the way to the words on screen.
  testWidgets('the message shown for a real HTTP 500 names the call', (
    tester,
  ) async {
    final thrown = await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      });
      try {
        await RealApiService().call(
          '127.0.0.1:${server.port}',
          'token',
          false,
          object: 'system',
          method: 'board',
        );
        return null;
      } catch (e) {
        return e;
      } finally {
        await server.close(force: true);
      }
    });

    late String shown;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: luciLocalizationsDelegates,
        home: Builder(
          builder: (context) {
            shown = apiErrorText(context, thrown!);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(shown, contains('HTTP 500'));
    expect(shown, contains('system.board'));
  });
}
