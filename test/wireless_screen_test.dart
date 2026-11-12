import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoActionSheetAction, CupertinoDialogAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/models/wireless_config.dart';
import 'package:luci_mobile/screens/wireless_screen.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/state/wireless_notifier.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

const _network = WirelessNetwork(
  section: 'default_radio0',
  device: 'radio0',
  ssid: 'Home',
  encryption: 'psk2',
  key: 'correct horse',
);

/// Records what the screen applies, instead of writing it to a router.
class _RecordingMutations extends WirelessMutations {
  _RecordingMutations(super.ref, this.applied);

  final List<List<UciOperation>> applied;

  @override
  Future<ApplyOutcome?> apply(
    List<UciOperation> ops, {
    BuildContext? context,
    void Function(ApplyPhase phase, Duration remaining)? onPhase,
  }) async {
    applied.add(ops);
    return null;
  }
}

/// Shows the wireless networks and opens [_network]. Completes with the
/// list of what the screen goes on to apply.
Future<List<List<UciOperation>>> _openNetwork(WidgetTester tester) async {
  final applied = await _pumpWireless(tester);
  await tester.tap(find.text('Home'));
  await tester.pumpAndSettle();
  return applied;
}

/// Shows the wireless networks. Completes with the list of what the screen
/// goes on to apply.
Future<List<List<UciOperation>>> _pumpWireless(WidgetTester tester) async {
  final applied = <List<UciOperation>>[];
  // Tall enough for the whole form, and wide enough for the test font.
  tester.view
    ..physicalSize = const Size(1800, 3600)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        wirelessConfigProvider.overrideWith(
          (ref) async => const [
            WirelessRadio(
              section: 'radio0',
              band: '2g',
              channel: '6',
              country: 'US',
              networks: [_network],
            ),
          ],
        ),
        featureProvider(RouterFeature.wirelessStations)
            .overrideWithValue(const FeatureAvailability.available()),
        wirelessMutationsProvider.overrideWith(
          (ref) => _RecordingMutations(ref, applied),
        ),
      ],
      child: const MaterialApp(home: WirelessScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return applied;
}

/// Lets the apply report that follows a removal run out.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: Remove asks first, and cancelling keeps the network', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    final applied = await _openNetwork(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('Remove Wireless Interface?'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(
          'This will permanently remove "Home" from your wireless '
          'configuration.',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Cancel')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(applied, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Remove')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    final [ops] = applied;
    final remove = ops.single as UciRemove;
    expect((remove.config, remove.section), ('wireless', 'default_radio0'));
    await _finish(tester);
  });

  testWidgets('before iOS 26: Remove asks in a Cupertino alert', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    final applied = await _openNetwork(tester);

    await tester.tap(find.widgetWithText(AdaptiveButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(applied, isEmpty, reason: 'not before it is confirmed');
    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Remove'));
    await tester.pumpAndSettle();

    final [ops] = applied;
    expect((ops.single as UciRemove).section, 'default_radio0');
    await _finish(tester);
  });

  testWidgets('Android: radio settings are Material dropdowns and a field', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await _pumpWireless(tester);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is AdaptiveButton && w.semanticLabel == 'Radio settings',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String?>), findsOneWidget);
    final country = tester.widget<TextField>(find.byType(TextField));
    expect(country.decoration!.labelText, 'Country code');
    expect(country.maxLength, 2);
  });

  testWidgets('before iOS 26: radio settings are grouped rows, the width '
      'reading Automatic when none is set', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    final applied = await _pumpWireless(tester);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is AdaptiveButton && w.semanticLabel == 'Radio settings',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    String rowValue(String label) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((w) => w is AdaptiveFormPicker),
            ),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .join(' | ');
    expect(rowValue('Channel'), 'Channel | 6');
    expect(rowValue('Channel width'), 'Channel width | Automatic');

    // Picking a channel and saving writes it.
    await tester.tap(find.text('Channel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoActionSheetAction, '11'));
    await tester.pumpAndSettle();
    expect(rowValue('Channel'), 'Channel | 11');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final [ops] = applied;
    final set = ops.whereType<UciSet>().single;
    expect(set.values, {'channel': '11'});
    await _finish(tester);
  });
}
