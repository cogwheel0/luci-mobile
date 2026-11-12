import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoSearchTextField, CupertinoTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/screens/system_settings_screen.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/state/system_settings_notifier.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

const _settings = SystemSettings(
  section: 'cfg01e48a',
  hostname: 'OpenWrt',
  zoneName: 'UTC',
  description: '',
  notes: '',
  timezones: {'UTC': 'UTC', 'Europe/Berlin': 'CET-1CEST,M3.5.0,M10.5.0/3'},
);

Future<void> _pumpSettings(WidgetTester tester) async {
  // Tall enough for the whole page, wide enough for the test font.
  tester.view
    ..physicalSize = const Size(1800, 3600)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        systemSettingsProvider.overrideWith((ref) async => _settings),
        featureProvider(RouterFeature.systemSettings)
            .overrideWithValue(const FeatureAvailability.available()),
        sessionProvider.overrideWithValue(null),
      ],
      child: const MaterialApp(home: SystemSettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// The iOS row labelled [label]'s text field.
Finder _row(String label) => find.descendant(
  of: find.widgetWithText(AdaptiveFormTextField, label),
  matching: find.byType(CupertinoTextField),
);

AdaptiveButton _save(WidgetTester tester) =>
    tester.widget(find.widgetWithText(AdaptiveButton, 'Save'));

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: the card of Material fields and the list tiles', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await _pumpSettings(tester);

    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.byType(AdaptiveFormSection), findsNothing);
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('Android: the time zone is a searchable bottom sheet', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await _pumpSettings(tester);

    await tester.tap(find.text('Time zone'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AdaptiveFormChoiceList<String>), findsNothing);
  });

  testWidgets('before iOS 26: grouped rows, the time zone and password as '
      'rows that open, and Save once something valid changed', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    await _pumpSettings(tester);

    expect(find.byType(TextField), findsNothing);
    expect(find.byType(AdaptiveFormSection), findsNWidgets(2));
    final zone = find.widgetWithText(AdaptiveFormNavigationRow, 'Time zone');
    expect(find.descendant(of: zone, matching: find.text('UTC')), findsOne);
    // Reviewer mode or not, there is no session here to change it on.
    expect(
      tester
          .widget<AdaptiveFormNavigationRow>(
            find.widgetWithText(AdaptiveFormNavigationRow, 'Router password'),
          )
          .onTap,
      isNotNull,
    );
    expect(_save(tester).onPressed, isNull);

    await tester.enterText(_row('Hostname'), 'bad host');
    await tester.pump();
    expect(find.text('Use letters, digits and hyphens only'), findsOneWidget);
    expect(_save(tester).onPressed, isNull);

    await tester.enterText(_row('Hostname'), 'lab-router');
    await tester.pump();
    expect(find.text('Use letters, digits and hyphens only'), findsNothing);
    expect(_save(tester).onPressed, isNotNull);
  });

  testWidgets('before iOS 26: the time zone is a page of its own, searched, '
      'the current zone checked', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    final semantics = tester.ensureSemantics();
    await _pumpSettings(tester);

    await tester.tap(find.text('Time zone'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    final list = find.byType(AdaptiveFormChoiceList<String>);
    expect(list, findsOneWidget);
    expect(find.byType(CupertinoSearchTextField), findsOneWidget);
    expect(
      tester.getSemantics(
        find.descendant(of: list, matching: find.text('UTC')),
      ),
      isSemantics(label: 'UTC', isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(
        find.descendant(of: list, matching: find.text('Europe/Berlin')),
      ),
      isSemantics(label: 'Europe/Berlin', isButton: true, isSelected: false),
    );

    await tester.enterText(find.byType(CupertinoSearchTextField), 'ber');
    await tester.pump();
    expect(find.descendant(of: list, matching: find.text('UTC')), findsNothing);

    await tester.tap(find.text('Europe/Berlin'));
    await tester.pumpAndSettle();
    expect(list, findsNothing);
    final zone = find.widgetWithText(AdaptiveFormNavigationRow, 'Time zone');
    expect(
      find.descendant(of: zone, matching: find.text('Europe/Berlin')),
      findsOne,
    );
    expect(_save(tester).onPressed, isNotNull);
    semantics.dispose();
  });
}
