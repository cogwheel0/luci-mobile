import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/dashboard_preferences.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/screens/dashboard_settings_list_screen.dart';
import 'package:luci_mobile/screens/router_dashboard_settings_screen.dart';
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

/// A router with a WAN and a LAN and one Wi-Fi network, showing
/// everything; records the preferences saved.
class _Router extends AppState {
  _Router()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  final saved = <DashboardPreferences>[];

  @override
  List<model.Router> get routers => [_home];

  @override
  model.Router? get selectedRouter => _home;

  @override
  Map<String, dynamic>? get dashboardData => {
    'wireless': {
      'radio0': {
        'interfaces': [
          {
            'config': {'device': 'radio0'},
            'iwinfo': {'ssid': 'Home'},
          },
        ],
      },
    },
    'interfaceDump': {
      'interface': [
        {'interface': 'wan'},
        {'interface': 'lan'},
      ],
    },
  };

  @override
  DashboardPreferences get dashboardPreferences => DashboardPreferences();

  @override
  Future<void> saveDashboardPreferences(DashboardPreferences prefs) async =>
      saved.add(prefs);
}

Future<_Router> _pump(WidgetTester tester, Widget page) async {
  tester.view
    ..physicalSize = const Size(1800, 4200)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final state = _Router();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => state)],
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('before iOS 26: a group per part, a switch to show all, and '
      'otherwise the interfaces to check', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    final state = await _pump(
      tester,
      const RouterDashboardSettingsScreen(routerId: 'home'),
    );

    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(AdaptiveFormSection), findsNWidgets(3));
    expect(find.text('THROUGHPUT MONITORING'), findsOneWidget);

    // Throughput for one interface: the first is checked, then the other.
    await tester.tap(
      find.descendant(
        of: find.byType(AdaptiveFormSection).first,
        matching: find.byType(AdaptiveSwitch),
      ),
    );
    await tester.pumpAndSettle();
    AdaptiveListRow row(String title) =>
        tester.widget(find.widgetWithText(AdaptiveListRow, title).first);
    expect(row('lan').selected, isTrue);
    expect(row('wan').selected, isFalse);
    await tester.tap(find.widgetWithText(AdaptiveListRow, 'wan').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(row('wan').selected, isTrue);
    expect(state.saved.last.primaryThroughputInterface, 'wan');
    expect(state.saved.last.showAllThroughput, isFalse);

    // Wired interfaces to show: all checked at first; a tap hides one.
    await tester.tap(
      find.descendant(
        of: find.byType(AdaptiveFormSection).last,
        matching: find.byType(AdaptiveSwitch),
      ),
    );
    await tester.pumpAndSettle();
    final lan = find.widgetWithText(AdaptiveListRow, 'LAN');
    expect(tester.widget<AdaptiveListRow>(lan).selected, isTrue);
    expect(
      find.descendant(of: lan, matching: find.text('Local Area Network')),
      findsOneWidget,
    );
    await tester.tap(lan);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<AdaptiveListRow>(lan).selected, isFalse);
    expect(state.saved.last.enabledWiredInterfaces, {'wan'});
  });

  testWidgets('before iOS 26: the routers as grouped rows that open', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    await _pump(tester, const DashboardSettingsListScreen());

    expect(find.byType(Card), findsNothing);
    final router = find.widgetWithText(AdaptiveListRow, 'OpenWrt');
    expect(
      find.descendant(
        of: router,
        matching: find.byIcon(CupertinoIcons.chevron_right),
      ),
      findsOneWidget,
    );
    await tester.tap(router);
    await tester.pumpAndSettle();
    expect(find.byType(RouterDashboardSettingsScreen), findsOneWidget);
  });
}
