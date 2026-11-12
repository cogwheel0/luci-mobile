import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoActionSheet;
import 'package:flutter/services.dart' show MethodChannel;
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
    // Before the board info arrives, the title is the saved hostname, as
    // the menu names the router, rather than its address.
    expect(
      find.descendant(of: title, matching: find.text('OpenWrt')),
      findsOne,
    );
    expect(find.text('192.168.1.1'), findsNothing);

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

  testWidgets(
    'iOS 26: the title opens the system menu under it, and the router '
    'picked there is switched to',
    (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
      PlatformUiCapabilities.debugNativeIOS26Override = true;
      // The system menu, answering with the row at [pick].
      final shown = <Map<Object?, Object?>>[];
      var pick = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('cn_context_menu'),
        (call) async {
          if (call.method != 'show') return null;
          shown.add(call.arguments! as Map<Object?, Object?>);
          return [pick];
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('cn_context_menu'),
          null,
        ),
      );
      final state = await _pumpDashboard(tester);

      final title = find.byType(AdaptiveTitleMenu<String>);
      expect(find.byType(CupertinoActionSheet), findsNothing);

      // The router already in use switches nothing.
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsNothing);
      final menu = shown.single['menu']! as Map<Object?, Object?>;
      expect(menu['labels'], ['OpenWrt', 'lab-ap']);
      expect(menu['subtitles'], ['192.168.1.1', '10.0.0.2']);
      expect(menu['checked'], [true, false]);
      // It grows out of the title's bottom edge.
      final anchor = tester.getRect(title).bottomCenter;
      expect(shown.single['x'], anchor.dx);
      expect(shown.single['y'], anchor.dy);
      expect(state.switchedTo, isEmpty);

      pick = 1;
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(shown, hasLength(2));
      expect(state.switchedTo, ['lab']);
      await tester.pumpWidget(const SizedBox());
    },
    // The menu is the system's through its channel, mocked above: no
    // native view, so this runs on every host.
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
