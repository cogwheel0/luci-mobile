import 'dart:io' show Platform;

import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNPopupMenuSubmenu;
import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoActionSheet,
        CupertinoActionSheetAction,
        CupertinoButton,
        CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/models/service_status.dart';
import 'package:luci_mobile/screens/services_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/state/router_session.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

/// Records the actions asked of the router's services.
class _RecordingApi extends MockApiService {
  final actions = <String>[];

  @override
  Future<bool> rcInit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String name,
    required String action,
    BuildContext? context,
  }) async {
    actions.add('$name $action');
    return true;
  }
}

const _session = RouterSession(
  routerId: 'r1',
  ipAddress: '192.168.1.1',
  sysauth: 'sysauth',
  useHttps: false,
  token: 1,
);

/// Shows the services list with dnsmasq on it. Completes with the API it
/// acts through.
Future<_RecordingApi> _pumpServices(
  WidgetTester tester, {
  FeatureAvailability gate = const FeatureAvailability.available(),
}) async {
  final api = _RecordingApi();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        servicesProvider.overrideWith(
          (ref) async => const [
            ServiceStatus(name: 'dnsmasq', enabled: true, running: true),
          ],
        ),
        featureProvider(RouterFeature.serviceControl).overrideWithValue(gate),
        sessionProvider.overrideWithValue(_session),
        apiServiceProvider.overrideWithValue(api),
      ],
      child: const MaterialApp(home: ServicesScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

/// Lets the confirmation banner time out.
Future<void> _settleBanner(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: the Material menu', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    final api = await _pumpServices(tester);

    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.ellipsis), findsNothing);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Disable at boot'), findsOneWidget);
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();
    expect(api.actions, ['dnsmasq restart']);
    await _settleBanner(tester);
  });

  testWidgets('before iOS 26: the actions behind an ellipsis, in an action '
      'sheet', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    final semantics = tester.ensureSemantics();
    final api = await _pumpServices(tester);

    expect(find.byType(PopupMenuButton<String>), findsNothing);
    // Read with its row, as Android's menu button is.
    expect(
      find.bySemanticsLabel(RegExp(r'^dnsmasq\n.*\nMore$')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();
    final sheet = find.byType(CupertinoActionSheet);
    for (final label in ['Start', 'Restart', 'Stop', 'Disable at boot']) {
      expect(
        find.descendant(of: sheet, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
    await tester.tap(
      find.widgetWithText(CupertinoActionSheetAction, 'Restart'),
    );
    await tester.pumpAndSettle();
    expect(api.actions, ['dnsmasq restart']);
    await _settleBanner(tester);
    semantics.dispose();
  });

  testWidgets('before iOS 26: without service control the ellipsis is dimmed '
      'and opens nothing', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    await _pumpServices(
      tester,
      gate: const FeatureAvailability.unavailable(
        UnavailableReason.missingPackage,
      ),
    );

    final button = find.ancestor(
      of: find.byIcon(CupertinoIcons.ellipsis),
      matching: find.byType(CupertinoButton),
    );
    expect(tester.widget<CupertinoButton>(button).onPressed, isNull);
    expect(
      tester.widget<Icon>(find.byIcon(CupertinoIcons.ellipsis)).color,
      CupertinoColors.tertiaryLabel.resolveFrom(tester.element(button)),
    );
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsNothing);
  });

  testWidgets(
    'iOS 26: the system pull-down menu, with a symbol for each action',
    (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
      PlatformUiCapabilities.debugNativeIOS26Override = true;
      await _pumpServices(tester);

      final menu = tester.widget<CNPopupMenuButton>(
        find.byType(CNPopupMenuButton),
      );
      expect(menu.buttonIcon?.name, 'ellipsis');
      // Two sections, so the menu keeps this order when it opens upward.
      expect(menu.preserveTopToBottomOrder, isTrue);
      expect(
        [
          for (final section in menu.items.cast<CNPopupMenuSubmenu>())
            [
              for (final item in section.items.cast<CNPopupMenuItem>())
                (item.label, item.icon?.name),
            ],
        ],
        [
          [
            ('Start', 'play.fill'),
            ('Restart', 'arrow.clockwise'),
            ('Stop', 'stop.fill'),
          ],
          [('Disable at boot', 'power')],
        ],
      );
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    skip: !Platform.isMacOS,
  );
}
