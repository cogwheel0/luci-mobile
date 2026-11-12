import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoActionSheet, CupertinoActionSheetAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/wifi_scan_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

/// An app state whose router has a 2.4 GHz radio serving "Home" and a
/// 5 GHz one serving nothing yet.
class _TwoRadios extends AppState {
  _TwoRadios()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  @override
  List<Map<String, String>> getAvailableRadioDevices() => [
    {
      'radioName': 'radio0',
      'band': '2.4 GHz',
      'ssid': 'Home',
      'ifname': 'phy0-ap0',
    },
    {'radioName': 'radio1', 'band': '5 GHz', 'ssid': '', 'ifname': 'phy1-ap0'},
  ];
}

Future<void> _pumpScanner(WidgetTester tester) async {
  // Wide enough for the test font.
  tester.view
    ..physicalSize = const Size(1800, 2400)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => _TwoRadios())],
      child: const MaterialApp(home: WifiScanScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: the Material dropdown', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await _pumpScanner(tester);

    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.byType(AdaptiveFormPicker<String>), findsNothing);
  });

  testWidgets('before iOS 26: a picker row, each radio with the network it '
      'serves', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    await _pumpScanner(tester);

    expect(find.byType(DropdownButton<String>), findsNothing);
    final picker = find.byType(AdaptiveFormPicker<String>);
    expect(
      find.descendant(of: picker, matching: find.text('Radio')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: find.text('radio0 (2.4 GHz)')),
      findsOneWidget,
    );

    await tester.tap(picker);
    await tester.pumpAndSettle();
    final sheet = find.byType(CupertinoActionSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('Home')),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(CupertinoActionSheetAction, 'radio1 (5 GHz)'),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: picker, matching: find.text('radio1 (5 GHz)')),
      findsOneWidget,
    );
  });
}
