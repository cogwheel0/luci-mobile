import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoNavigationBar;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/screens/manage_routers_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

void main() {
  testWidgets('fallback removal requires confirmation', (tester) async {
    final state = _TestAppState(
      model.Router(
        id: 'router',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
        alternateAddress: 'router.example.com',
        alternateUseHttps: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(home: ManageRoutersScreen()),
      ),
    );

    await tester.tap(find.byTooltip('Remove fallback address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(state.updatedRouter, isNull);

    await tester.tap(find.byTooltip('Remove fallback address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(state.updatedRouter?.hasFallback, isFalse);
  });

  group('adding a router', () {
    tearDown(PlatformUiCapabilities.resetDebugOverrides);

    testWidgets('Android: a dialog that validates, refuses a duplicate, and '
        'signs in', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
      final state = await _openAddRouter(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      final add = find.widgetWithText(FilledButton, 'Add');

      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Please enter the router address'), findsOneWidget);
      expect(state.logins, isEmpty);

      await tester.enterText(_field('Router Address'), '192.168.1.1');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Router already exists.'), findsOneWidget);
      expect(state.logins, isEmpty);

      await tester.enterText(_field('Router Address'), '10.0.0.1');
      await tester.enterText(_field('Password'), 'secret');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(state.logins, ['10.0.0.1 root secret']);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('before iOS 26: a sheet whose Add signs in', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final state = await _openAddRouter(tester);
      expect(find.byType(AlertDialog), findsNothing);
      final bar = find.byType(CupertinoNavigationBar).last;
      expect(
        find.descendant(of: bar, matching: find.text('Add Router')),
        findsOneWidget,
      );

      await tester.enterText(_field('Router Address'), '10.0.0.1');
      await tester.enterText(_field('Password'), 'secret');
      await tester.tap(find.descendant(of: bar, matching: find.text('Add')));
      await tester.pumpAndSettle();
      expect(state.logins, ['10.0.0.1 root secret']);
      expect(find.text('Router Address'), findsNothing);
    });
  });
}

/// The add-router form: what the field labelled [label] holds.
Finder _field(String label) => find.widgetWithText(TextFormField, label);

final _existing = model.Router(
  id: '192.168.1.1-root',
  ipAddress: '192.168.1.1',
  username: 'root',
  password: 'password',
  useHttps: false,
);

Future<_TestAppState> _openAddRouter(WidgetTester tester) async {
  final state = _TestAppState(_existing);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => state)],
      child: const MaterialApp(home: ManageRoutersScreen()),
    ),
  );
  await tester.tap(find.text('Add Router'));
  await tester.pumpAndSettle();
  return state;
}

class _TestAppState extends AppState {
  _TestAppState(this.router)
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  final model.Router router;
  model.Router? updatedRouter;

  @override
  List<model.Router> get routers => [router];

  @override
  Future<void> updateRouter(model.Router router) async =>
      updatedRouter = router;

  final logins = <String>[];

  @override
  Future<bool> login(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    bool fromRouter = false,
    String? alternateAddress,
    bool? alternateUseHttps,
    int activeAddressIndex = 0,
    BuildContext? context,
  }) async {
    logins.add('$ip $user $pass');
    return true;
  }
}
