import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/screens/addon_screen.dart';
import 'package:luci_mobile/services/addon_catalog.dart';
import 'package:luci_mobile/services/addon_planner.dart';
import 'package:luci_mobile/state/addon_notifier.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

const _queue = AddonSection(
  name: 'eth1',
  label: 'eth1',
  values: {
    'enabled': '1',
    'download': '50000',
    'upload': '10000',
    'qdisc': 'cake',
    'script': 'piece_of_cake.qos',
  },
);

/// Shows SQM's settings for one queue.
Future<void> _pumpSqm(WidgetTester tester) async {
  // Tall enough for every field, wide enough for the test font.
  tester.view
    ..physicalSize = const Size(1800, 4200)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        addonProvider(AddonCatalog.sqm).overrideWith((ref) async => [_queue]),
        featureProvider(RouterFeature.sqm)
            .overrideWithValue(const FeatureAvailability.available()),
      ],
      child: const MaterialApp(home: AddonScreen(spec: AddonCatalog.sqm)),
    ),
  );
  await tester.pumpAndSettle();
}

AdaptiveButton _save(WidgetTester tester) =>
    tester.widget(find.widgetWithText(AdaptiveButton, 'Save'));

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: the Material fields and dropdowns', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await _pumpSqm(tester);

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    expect(find.byType(AdaptiveFormSection), findsNothing);
  });

  testWidgets('before iOS 26: a group per setting, its explanation under it, '
      'and Save once something valid changed', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    await _pumpSqm(tester);

    expect(find.byType(TextField), findsNothing);
    expect(find.byType(AdaptiveFormSection), findsNWidgets(5));
    expect(find.widgetWithText(AdaptiveFormSwitch, 'Enabled'), findsOneWidget);
    final download = find.widgetWithText(
      AdaptiveFormTextField,
      'Download speed',
    );
    expect(
      find.descendant(of: download, matching: find.text('kbit/s')),
      findsOne,
    );
    final qdisc = find.widgetWithText(
      AdaptiveFormPicker<String>,
      'Queue discipline',
    );
    expect(find.descendant(of: qdisc, matching: find.text('cake')), findsOne);
    expect(_save(tester).onPressed, isNull);

    final field = find.descendant(
      of: download,
      matching: find.byType(CupertinoTextField),
    );
    await tester.enterText(field, '99999999');
    await tester.pump();
    expect(find.text('Enter a number between 0 and 10000000'), findsOneWidget);
    expect(_save(tester).onPressed, isNull);

    await tester.enterText(field, '80000');
    await tester.pump();
    expect(find.text('Enter a number between 0 and 10000000'), findsNothing);
    expect(_save(tester).onPressed, isNotNull);
  });
}
