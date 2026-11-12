import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoActionSheet, CupertinoActionSheetAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/screens/traffic_screen.dart';
import 'package:luci_mobile/services/traffic_service.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

/// Shows the traffic history with two periods: in each, one device, at an
/// address that names the period.
Future<void> _pumpTraffic(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trafficPeriodsProvider.overrideWith(
          (ref) async => const ['2026-11-01', '2026-10-01'],
        ),
        for (final (period, ip) in [
          ('2026-11-01', '10.0.0.11'),
          ('2026-10-01', '10.0.0.10'),
        ])
          trafficRecordsProvider(period).overrideWith(
            (ref) async => [
              TrafficRow(
                mac: 'aa:bb:cc:dd:ee:ff',
                ip: ip,
                connections: 1,
                rxBytes: 1024,
                txBytes: 512,
              ),
            ],
          ),
        featureProvider(RouterFeature.trafficAccounting)
            .overrideWithValue(const FeatureAvailability.available()),
      ],
      child: const MaterialApp(home: TrafficScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: the Material dropdown', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await _pumpTraffic(tester);

    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.byType(AdaptiveFormPicker<String>), findsNothing);
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.byType(AdaptiveGroupedListView), findsNothing);
  });

  testWidgets('before iOS 26: a picker row that shows the chosen period\'s '
      'traffic', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    await _pumpTraffic(tester);

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    final picker = find.byType(AdaptiveFormPicker<String>);
    expect(
      find.descendant(of: picker, matching: find.text('2026-11-01')),
      findsOneWidget,
    );
    expect(find.text('10.0.0.11'), findsOneWidget);
    // The devices as one inset group: each its address, its usage and a
    // bar under it, and its total on the right.
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(AdaptiveGroupedListView), findsOneWidget);
    final device = find.widgetWithText(AdaptiveListRow, '10.0.0.11');
    expect(
      find.descendant(of: device, matching: find.text('1.5 KB')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: device,
        matching: find.byType(AdaptiveProgressIndicator),
      ),
      findsOneWidget,
    );

    // Each bar spans the row from the address on, whatever the width of
    // its total.
    final bar = find.descendant(
      of: device,
      matching: find.byType(AdaptiveProgressIndicator),
    );
    expect(
      tester.getRect(bar).right,
      tester
          .getRect(find.descendant(of: device, matching: find.text('1.5 KB')))
          .right,
    );

    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(
      find.widgetWithText(CupertinoActionSheetAction, '2026-10-01'),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: picker, matching: find.text('2026-10-01')),
      findsOneWidget,
    );
    expect(find.text('10.0.0.10'), findsOneWidget);
    expect(find.text('10.0.0.11'), findsNothing);
  });
}
