import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoActionSheet, CupertinoActionSheetAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/wifi_scan_result.dart';
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

  /// A secured network, an open one and a hidden one.
  @override
  Future<List<WifiScanResult>> scanWirelessNetworks({
    required String device,
    BuildContext? context,
  }) async => [
    for (final (ssid, signal, encrypted) in [
      ('Neighbor', -45, true),
      ('Cafe', -62, false),
      ('', -80, true),
    ])
      WifiScanResult.fromJson({
        'ssid': ssid,
        'bssid': 'AA:BB:CC:11:22:${signal.abs()}',
        'mode': 'Master',
        'channel': 6,
        'signal': signal,
        'quality': 50,
        'quality_max': 70,
        'encryption': {
          'enabled': encrypted,
          'description': encrypted ? 'WPA2 PSK (CCMP)' : 'None',
          'wep': false,
          'wpa': encrypted ? 2 : 0,
          'auth_suites': encrypted ? ['PSK'] : <String>[],
          'pair_ciphers': encrypted ? ['CCMP'] : <String>[],
          'group_ciphers': encrypted ? ['CCMP'] : <String>[],
        },
      }),
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

  testWidgets('before iOS 26: the networks found as grouped rows, as iOS '
      'lists Wi-Fi networks, each opening the connect form', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    await _pumpScanner(tester);

    await tester.tap(find.text('Scan Networks'));
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNothing);
    expect(find.text('AVAILABLE NETWORKS'), findsOneWidget);
    expect(find.text('3 found'), findsOneWidget);
    expect(find.text('HIDDEN NETWORKS'), findsOneWidget);
    final cafe = find.widgetWithText(AdaptiveListRow, 'Cafe');
    expect(
      find.descendant(of: cafe, matching: find.text('Open')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(AdaptiveListRow, 'Neighbor'),
        matching: find.text('WPA2'),
      ),
      findsOneWidget,
    );

    await tester.tap(cafe);
    await tester.pumpAndSettle();
    expect(find.byType(AdaptiveFormSheet), findsOneWidget);
  });
}
