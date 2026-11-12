import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoActionSheet;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/screens/dashboard_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

final _home = model.Router(
  id: 'home',
  ipAddress: '192.168.1.1',
  username: 'root',
  password: '',
  useHttps: false,
  lastKnownHostname: 'OpenWrt',
);

final _lab = model.Router(
  id: 'lab',
  ipAddress: '10.0.0.2',
  username: 'root',
  password: '',
  useHttps: false,
  lastKnownHostname: 'lab-ap',
);

/// Two saved routers, signed in to the first, with nothing to fetch.
/// Records the routers switched to.
class _TwoRouters extends AppState {
  _TwoRouters()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  final switchedTo = <String>[];

  @override
  List<model.Router> get routers => [_home, _lab];

  @override
  model.Router? get selectedRouter => _home;

  @override
  bool get dashboardFetchIsFresh => true;

  @override
  Future<void> selectRouter(String id, {BuildContext? context}) async =>
      switchedTo.add(id);
}

Future<_TwoRouters> _pumpDashboard(WidgetTester tester) async {
  final state = _TwoRouters();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => state)],
      child: const MaterialApp(home: DashboardScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: the bordered title opens the router sheet', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    final state = await _pumpDashboard(tester);

    expect(find.byType(AdaptiveTitleMenu<String>), findsNothing);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

    await tester.tap(find.text('192.168.1.1'));
    await tester.pumpAndSettle();
    expect(find.text('Select Router'), findsOneWidget);
    await tester.tap(find.text('lab-ap'));
    await tester.pumpAndSettle();
    expect(state.switchedTo, ['lab']);
  });

  testWidgets('before iOS 26: the title switches routers from an action '
      'sheet, each with its address', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    final state = await _pumpDashboard(tester);

    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    final title = find.byType(AdaptiveTitleMenu<String>);
    expect(title, findsOneWidget);

    await tester.tap(title);
    await tester.pumpAndSettle();
    final sheet = find.byType(CupertinoActionSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('Select Router')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('10.0.0.2')),
      findsOneWidget,
    );

    // The router already in use switches nothing.
    await tester.tap(
      find.descendant(of: sheet, matching: find.text('OpenWrt')),
    );
    await tester.pumpAndSettle();
    expect(state.switchedTo, isEmpty);

    await tester.tap(title);
    await tester.pumpAndSettle();
    await tester.tap(find.text('lab-ap'));
    await tester.pumpAndSettle();
    expect(state.switchedTo, ['lab']);
  });
}
