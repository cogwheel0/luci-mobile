import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/screens/clients_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/app_state_provider.dart';

model.Router _router(String id) => model.Router(
  id: id,
  ipAddress: '192.168.$id.1',
  username: 'root',
  password: 'password',
  useHttps: false,
);

class _TestAppState extends AppState {
  _TestAppState(this._routers)
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  final List<model.Router> _routers;

  /// Records which fetch path the screen chose.
  bool? aggregatedRequested;

  @override
  List<model.Router> get routers => _routers;

  @override
  model.Router? get selectedRouter => _routers.isEmpty ? null : _routers.first;

  @override
  bool get clientsAggregateAllRouters => true;

  @override
  Future<List<Client>> fetchAggregatedClients() async {
    aggregatedRequested = true;
    return const [];
  }

  @override
  Future<List<Client>> fetchClientsForSelectedRouter() async {
    aggregatedRequested = false;
    return const [];
  }
}

Future<_TestAppState> _pump(WidgetTester tester, int routerCount) async {
  final state = _TestAppState([
    for (var i = 0; i < routerCount; i++) _router('$i'),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => state)],
      child: MaterialApp(
        localizationsDelegates: luciLocalizationsDelegates,
        home: const ClientsScreen(),
      ),
    ),
  );
  await tester.pump();
  return state;
}

void main() {
  group('the All / Selected control', () {
    // With one router the two segments return the same clients, so the
    // control is a switch between a thing and itself.
    testWidgets('is hidden when only one router is saved', (tester) async {
      await _pump(tester, 1);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
    });

    testWidgets('appears once a second router is saved', (tester) async {
      await _pump(tester, 2);
      expect(find.byType(SegmentedButton<bool>), findsOneWidget);
    });

    testWidgets('is hidden when no routers are saved', (tester) async {
      await _pump(tester, 0);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
    });
  });

  group('which fetch path is taken', () {
    // The aggregate path logs into every saved router. With one router that
    // buys an extra round trip for exactly the same answer.
    testWidgets('one router uses the cheaper single-router fetch', (
      tester,
    ) async {
      final state = await _pump(tester, 1);
      expect(state.aggregatedRequested, isFalse);
    });

    // ...but the stored preference is honoured as soon as it means something.
    testWidgets('two routers honour the saved aggregate preference', (
      tester,
    ) async {
      final state = await _pump(tester, 2);
      expect(state.aggregatedRequested, isTrue);
    });
  });
}
