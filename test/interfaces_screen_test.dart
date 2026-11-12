import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoDialogAction, CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/wifi_scan_result.dart';
import 'package:luci_mobile/screens/interfaces_screen.dart';
import 'package:luci_mobile/screens/wifi_scan_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

/// A router with a LAN, a WAN that is down, a WireGuard tunnel with one
/// peer, and a Wi-Fi network ([ssid]) on its first radio.
class _Router extends AppState {
  _Router()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  /// As when a refresh brings the data in again.
  void refreshed() => notifyListeners();

  /// The Wi-Fi network's name, as the router reports it.
  String ssid = 'Home';

  /// The Wi-Fi sections removed.
  final removed = <String>[];

  /// When set, removing waits for it.
  Completer<bool>? removing;

  @override
  Future<bool> deleteWirelessInterface(
    String uciSection, {
    BuildContext? context,
  }) async {
    removed.add(uciSection);
    return removing?.future ?? true;
  }

  /// Wi-Fi switch changes asked for, saved when [saving] completes.
  final switched = <(String, bool)>[];
  Completer<bool> saving = Completer();

  @override
  Future<bool> setWirelessInterfaceEnabled(
    String uciSection,
    bool enabled, {
    BuildContext? context,
  }) {
    switched.add((uciSection, enabled));
    return saving.future;
  }

  @override
  Map<String, dynamic>? get dashboardData => {
    'interfaceDump': {
      'interface': [
        {
          'interface': 'lan',
          'up': true,
          'proto': 'static',
          'device': 'br-lan',
          'uptime': 3600,
          'ipv4-address': [
            {'address': '192.168.1.1', 'mask': 24},
          ],
          'ipv6-address': [
            {'address': 'fd00::1', 'mask': 60},
          ],
          'dns-server': ['1.1.1.1'],
          'stats': {'rx_bytes': 1000000, 'tx_bytes': 2000000},
        },
        {'interface': 'wan', 'up': false, 'proto': 'pppoe', 'device': 'eth0'},
        {
          'interface': 'wg0',
          'up': true,
          'proto': 'wireguard',
          'device': 'wg0',
          'uptime': 60,
        },
      ],
    },
    'wireguard': {
      'wg0': {
        'peers': {
          'peer0': {
            'name': 'Phone',
            'public_key': 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345',
            'endpoint': '203.0.113.7:51820',
            'allowed_ips': ['10.0.0.2/32'],
            'transfer_rx': 4096,
            'transfer_tx': 8192,
          },
        },
      },
    },
    'wireless': {
      'radio0': {
        'interfaces': [
          {
            'section': 'default_radio0',
            'ifname': 'phy0-ap0',
            'config': {
              'device': 'radio0',
              'mode': 'ap',
              'ssid': ssid,
              'network': ['lan'],
              'encryption': 'psk2',
            },
            'iwinfo': {'ssid': ssid, 'channel': 36, 'signal': -40},
          },
        ],
      },
    },
  };

  @override
  List<Map<String, String>> getAvailableRadioDevices() => [
    {
      'radioName': 'radio0',
      'band': '5 GHz',
      'ssid': 'Home',
      'ifname': 'phy0-ap0',
    },
  ];

  @override
  Future<List<WifiScanResult>> scanWirelessNetworks({
    required String device,
    BuildContext? context,
  }) async => const [];
}

Future<_Router> _pump(
  WidgetTester tester, {
  String? target,
  VoidCallback? onTargetShown,
}) async {
  final state = _Router();
  tester.view
    ..physicalSize = const Size(1800, 3600)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => state)],
      child: MaterialApp(
        home: InterfacesScreen(
          scrollToInterface: target,
          onScrollComplete: onTargetShown,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

/// A grouped row titled [title] with a chevron, as rows that open a page.
Finder _openingRow(String title) => find.descendant(
  of: find.widgetWithText(AdaptiveListRow, title),
  matching: find.byIcon(CupertinoIcons.chevron_right),
);

Finder _value(String label) => find.widgetWithText(AdaptiveFormValueRow, label);

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: the expanding cards and the Radio button', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await _pump(tester);

    expect(find.byType(AdaptiveListRow), findsNothing);
    expect(find.text('LAN'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Radio'), findsOneWidget);

    // A card expands in place: the LAN's address shows under it.
    expect(find.text('192.168.1.1'), findsNothing);
    await tester.tap(find.text('LAN'));
    await tester.pumpAndSettle();
    expect(find.textContaining('192.168.1.1'), findsWidgets);
    expect(find.byType(AdaptiveFormValueRow), findsNothing);
  });

  testWidgets('Android: a WireGuard card lists its peer', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await _pump(tester);
    await tester.tap(find.text('WG0'));
    await tester.pumpAndSettle();

    expect(find.text('ABCDEFGH...YZ012345'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('203.0.113.7:51820'), findsOneWidget);
    expect(find.text('10.0.0.2/32'), findsOneWidget);
    expect(find.text('Never'), findsOneWidget);
  });

  testWidgets('Android: Remove asks in a Material dialog', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    final state = await _pump(tester);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remove'));
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Remove Wireless Interface?'), findsOneWidget);
    expect(state.removed, isEmpty);
  });

  group('before iOS 26', () {
    setUp(() {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    });

    testWidgets('the interfaces as rows that open a page, and the scanner '
        'as the wireless group\'s last row', (tester) async {
      await _pump(tester);

      expect(find.text('Radio'), findsNothing);
      for (final title in ['LAN', 'WAN', 'WG0', 'Home', 'WiFi Scanner']) {
        expect(_openingRow(title), findsOneWidget, reason: title);
      }
      // A down interface says so in words, not only in its icon's colour.
      Finder off(String row) => find.descendant(
        of: find.widgetWithText(AdaptiveListRow, row),
        matching: find.text('Off'),
      );
      expect(off('WAN'), findsOneWidget);
      expect(off('LAN'), findsNothing);
      expect(off('Home'), findsNothing);
      expect(
        find.descendant(
          of: find.widgetWithText(AdaptiveListRow, 'LAN'),
          matching: find.textContaining('192.168.1.1'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('WiFi Scanner'));
      await tester.pumpAndSettle();
      expect(find.byType(WifiScanScreen), findsOneWidget);
    });

    testWidgets('a wired interface\'s page: its addresses to copy and its '
        'traffic', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('LAN'));
      await tester.pumpAndSettle();

      expect(find.byType(InterfacesScreen), findsNothing);
      expect(
        tester.widget<AdaptiveFormValueRow>(_value('Device')).value,
        'br-lan',
      );
      for (final (label, value) in [
        ('IP Address', '192.168.1.1'),
        ('IPv6 Address', 'fd00::1'),
        ('DNS', '1.1.1.1'),
      ]) {
        final row = tester.widget<AdaptiveFormValueRow>(_value(label));
        expect(row.value, value, reason: label);
        expect(row.selectable, isTrue, reason: label);
      }
      expect(find.text('TRAFFIC'), findsOneWidget);
      expect(_value('Received'), findsOneWidget);
      expect(_value('Transmitted'), findsOneWidget);
    });

    testWidgets('a WireGuard interface\'s page: a group per peer, without '
        'traffic the router did not report', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('WG0'));
      await tester.pumpAndSettle();

      expect(find.text('TRAFFIC'), findsNothing);
      expect(find.text('PHONE'), findsOneWidget);
      expect(
        tester.widget<AdaptiveFormValueRow>(_value('Endpoint')).value,
        '203.0.113.7:51820',
      );
      expect(
        tester.widget<AdaptiveFormValueRow>(_value('Allowed IPs')).value,
        '10.0.0.2/32',
      );
      expect(_value('Last Handshake'), findsOneWidget);
    });

    testWidgets('a Wi-Fi network\'s page: its details, its switch and Edit, '
        'then Remove in red', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<AdaptiveFormValueRow>(_value('Channel')).value,
        '36',
      );
      final toggle = tester.widget<AdaptiveFormSwitch>(
        find.widgetWithText(AdaptiveFormSwitch, 'Interface Enabled'),
      );
      expect(toggle.value, isTrue);
      expect(toggle.onChanged, isNotNull);
      expect(find.widgetWithText(AdaptiveFormButtonRow, 'Edit'), findsOne);
      expect(
        tester
            .widget<AdaptiveFormButtonRow>(
              find.widgetWithText(AdaptiveFormButtonRow, 'Remove'),
            )
            .destructive,
        isTrue,
      );
    });

    testWidgets('a Wi-Fi network\'s switch shows the state asked for while '
        'it is saved, then the router\'s', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      AdaptiveFormSwitch toggle() =>
          tester.widget(find.byType(AdaptiveFormSwitch));
      await tester.tap(find.byType(AdaptiveSwitch));
      await tester.pump();
      expect(state.switched, [('default_radio0', false)]);
      expect(toggle().value, isFalse);
      expect(toggle().label, 'Interface Disabled');
      expect(toggle().onChanged, isNull);

      // Saved; the data has it on still, so it shows on.
      state.saving.complete(true);
      await tester.pumpAndSettle();
      expect(toggle().value, isTrue);
      expect(toggle().onChanged, isNotNull);
    });

    testWidgets('Remove asks in an iOS alert, then removes the network and '
        'leaves its page', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      // Cancelling keeps it.
      await tester.tap(find.widgetWithText(AdaptiveFormButtonRow, 'Remove'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Remove Wireless Interface?'), findsOneWidget);
      expect(
        find.textContaining('Clients on this network will be disconnected'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Cancel'));
      await tester.pumpAndSettle();
      expect(state.removed, isEmpty);
      expect(_value('Channel'), findsOneWidget);

      await tester.tap(find.widgetWithText(AdaptiveFormButtonRow, 'Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Remove'));
      await tester.pumpAndSettle();
      expect(state.removed, ['default_radio0']);
      expect(_value('Channel'), findsNothing);
      expect(_openingRow('LAN'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a removal that ends after the page was left closes nothing '
        'else', (tester) async {
      final state = await _pump(tester)
        ..removing = Completer();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AdaptiveFormButtonRow, 'Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Remove'));
      await tester.pumpAndSettle();
      expect(state.removed, ['default_radio0']);
      expect(
        tester
            .widget<AdaptiveFormButtonRow>(
              find.widgetWithText(AdaptiveFormButtonRow, 'Remove'),
            )
            .onPressed,
        isNull,
        reason: 'disabled while the router works',
      );

      // Back, and into the LAN's page, before the router answers.
      Navigator.of(tester.element(_value('Channel'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('LAN'));
      await tester.pumpAndSettle();
      expect(_value('IP Address'), findsOneWidget);

      state.removing!.complete(true);
      await tester.pumpAndSettle();
      expect(_value('IP Address'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a renamed network\'s page follows its new name', (
      tester,
    ) async {
      final state = await _pump(tester);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);

      state
        ..ssid = 'Cabin'
        ..refreshed();
      await tester.pumpAndSettle();
      expect(find.text('Cabin'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
      expect(_value('Channel'), findsOneWidget);
    });

    testWidgets('a link to an interface opens its page, once', (tester) async {
      var shown = 0;
      final state = await _pump(
        tester,
        target: 'lan',
        onTargetShown: () => shown++,
      );

      expect(_value('IP Address'), findsOneWidget);
      expect(shown, 1);

      // Back on the list, it stays, through a refresh: the link was
      // followed.
      Navigator.of(tester.element(_value('IP Address'))).pop();
      await tester.pumpAndSettle();
      state.refreshed();
      await tester.pumpAndSettle();
      expect(_openingRow('LAN'), findsOneWidget);
      expect(_value('IP Address'), findsNothing);
      expect(shown, 1);
    });

    testWidgets('a link to a Wi-Fi network opens its page', (tester) async {
      var shown = 0;
      await _pump(
        tester,
        target: 'default_radio0',
        onTargetShown: () => shown++,
      );

      expect(
        find.widgetWithText(AdaptiveFormSwitch, 'Interface Enabled'),
        findsOneWidget,
      );
      expect(shown, 1);
    });

    testWidgets('a link to an interface the router lacks leaves the list', (
      tester,
    ) async {
      var shown = 0;
      await _pump(tester, target: 'wwan', onTargetShown: () => shown++);

      expect(_openingRow('LAN'), findsOneWidget);
      expect(find.byType(AdaptiveFormValueRow), findsNothing);
      expect(shown, 1);
    });
  });
}
