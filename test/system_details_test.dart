import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/system_details.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:luci_mobile/widgets/system_details_sheet.dart';

void main() {
  // #14: what LuCI's Status > Overview shows, from the `system board` reply
  // the dashboard already fetches.
  group('system details', () {
    test('every field the router reports, in LuCI order', () {
      final rows = SystemDetail.of({
        'hostname': 'gateway',
        'model': 'TP-Link Archer C7 v5',
        'system': 'Qualcomm Atheros QCA956X ver 1 rev 0',
        'kernel': '6.6.73',
        'release': {
          'target': 'ath79/generic',
          'description': 'OpenWrt 24.10.0 r28427-6df0e3d02a',
        },
      });
      expect(rows, [
        (SystemDetail.hostname, 'gateway'),
        (SystemDetail.model, 'TP-Link Archer C7 v5'),
        (SystemDetail.architecture, 'Qualcomm Atheros QCA956X ver 1 rev 0'),
        (SystemDetail.target, 'ath79/generic'),
        (SystemDetail.firmware, 'OpenWrt 24.10.0 r28427-6df0e3d02a'),
        (SystemDetail.kernel, '6.6.73'),
      ]);
    });

    test('missing or blank fields are left out, not shown empty', () {
      expect(
        SystemDetail.of({'model': 'x86/64', 'kernel': '  ', 'release': 'odd'}),
        [(SystemDetail.model, 'x86/64')],
      );
      expect(SystemDetail.of(null), isEmpty);
    });
  });

  // #10: the peer's name, allowed IPs and traffic were dropped on parsing.
  group('WireGuard peer', () {
    test('name, allowed IPs and transfer are kept', () {
      final peer = RealApiService.wireGuardPeer('key=', {
        'name': ' laptop ',
        'endpoint': '203.0.113.7:51820',
        'allowed_ips': ['10.0.0.2/32', 'fd00::2/128'],
        'latest_handshake': '1762850000',
        'transfer_rx': 1048576,
        'transfer_tx': '2048',
      });
      expect(peer['public_key'], 'key=');
      expect(peer['name'], 'laptop');
      expect(peer['allowed_ips'], ['10.0.0.2/32', 'fd00::2/128']);
      expect(peer['last_handshake'], 1762850000);
      expect(peer['transfer_rx'], 1048576);
      expect(peer['transfer_tx'], 2048);
    });

    // One counter present must not make the other read as zero traffic.
    test('a counter the router did not send stays absent', () {
      final peer = RealApiService.wireGuardPeer('key=', {
        'transfer_rx': 4096,
        'transfer_tx': 'n/a',
      });
      expect(peer['transfer_rx'], 4096);
      expect(peer.containsKey('transfer_tx'), isFalse);
    });

    // An older LuCI, or a peer with no description, sends less.
    test('what the router leaves out is left out', () {
      final peer = RealApiService.wireGuardPeer('key=', {
        'name': '',
        'allowed_ips': ['(none)'],
      });
      expect(peer.containsKey('name'), isFalse);
      expect(peer['allowed_ips'], isEmpty);
      expect(peer.containsKey('transfer_rx'), isFalse);
      expect(peer['endpoint'], 'N/A');
      expect(peer['last_handshake'], 0);
    });
  });

  // The device card opens the sheet on a tap and on the long press #14
  // asked for; the sheet shows each field labelled, selectable for pasting.
  group('system details sheet', () {
    const details = [
      (SystemDetail.model, 'TP-Link Archer C7 v5'),
      (SystemDetail.kernel, '6.6.73'),
    ];

    Future<void> pumpCard(
      WidgetTester tester,
      List<(SystemDetail, String)> details,
    ) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: luciLocalizationsDelegates,
        home: Scaffold(
          body: SystemDetailsTap(
            details: details,
            child: const SizedBox(width: 200, height: 80, child: Text('card')),
          ),
        ),
      ),
    );

    void expectSheet() {
      expect(find.text('System details'), findsOneWidget);
      expect(find.text('Model'), findsOneWidget);
      expect(find.text('Kernel version'), findsOneWidget);
      expect(
        find.widgetWithText(SelectableText, 'TP-Link Archer C7 v5'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SelectableText, '6.6.73'), findsOneWidget);
    }

    testWidgets('a tap opens it', (tester) async {
      await pumpCard(tester, details);
      await tester.tap(find.text('card'));
      await tester.pumpAndSettle();
      expectSheet();
    });

    testWidgets('a long press opens it', (tester) async {
      await pumpCard(tester, details);
      await tester.longPress(find.text('card'));
      await tester.pumpAndSettle();
      expectSheet();
    });

    group('before iOS 26', () {
      setUp(() {
        PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
        PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      });
      tearDown(PlatformUiCapabilities.resetDebugOverrides);

      testWidgets('a sheet of value rows, selectable, closed by Done', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpCard(tester, details);
        await tester.tap(find.text('card'));
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(AdaptiveInfoSheet), findsOneWidget);
        expect(find.text('System details'), findsOneWidget);
        final model = find.widgetWithText(AdaptiveFormValueRow, 'Model');
        expect(
          find.descendant(
            of: model,
            matching: find.widgetWithText(
              SelectableText,
              'TP-Link Archer C7 v5',
            ),
          ),
          findsOneWidget,
        );
        // The value sits on the right of its label.
        expect(
          tester.getRect(find.text('Model')).right,
          lessThan(tester.getRect(find.text('TP-Link Archer C7 v5')).left),
        );
        expect(
          find.widgetWithText(AdaptiveFormValueRow, 'Kernel version'),
          findsOneWidget,
        );
        // VoiceOver reads each value with its label, as one read-only
        // element.
        expect(
          tester.getSemantics(find.text('Model')),
          isSemantics(
            label: 'Model',
            value: 'TP-Link Archer C7 v5',
            isReadOnly: true,
          ),
        );

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.byType(AdaptiveInfoSheet), findsNothing);
        semantics.dispose();
      });
    });

    testWidgets('with nothing to show, the card is inert', (tester) async {
      await pumpCard(tester, const []);
      await tester.tap(find.text('card'));
      await tester.longPress(find.text('card'));
      await tester.pumpAndSettle();
      expect(find.text('System details'), findsNothing);
    });
  });
}
