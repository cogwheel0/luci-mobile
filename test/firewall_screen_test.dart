import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoNavigationBar;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/firewall_config.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/screens/firewall_screen.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/firewall_notifier.dart';
import 'package:luci_mobile/utils/keyboards.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

const _forward = PortForward(
  section: 'web',
  name: 'Web server',
  protocol: 'tcp',
  sourcePort: '8080',
  destIp: '192.168.1.10',
  destPort: '80',
);

/// Records what the screen applies, instead of writing it to a router.
class _RecordingMutations extends FirewallMutations {
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

/// Shows the firewall's port forwards and opens [_forward]. Completes with
/// the list of what the screen goes on to apply.
Future<List<List<UciOperation>>> _openForward(WidgetTester tester) async {
  final applied = <List<UciOperation>>[];
  // Tall enough for the whole form, and wide enough for the test font's
  // square glyphs, which make "TCP + UDP" far wider than a phone's font.
  tester.view
    ..physicalSize = const Size(1800, 3600)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firewallProvider.overrideWith(
          (ref) async => const FirewallState(
            zones: [
              FirewallZone(section: 'lan', name: 'lan'),
              FirewallZone(section: 'wan', name: 'wan', masq: true),
            ],
            forwards: [_forward],
            sectionNames: {'web'},
          ),
        ),
        firewallMutationsProvider.overrideWith(
          (ref) => _RecordingMutations(ref, applied),
        ),
      ],
      child: const MaterialApp(home: FirewallScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Web server'));
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

  testWidgets('Android: a port forward opens in a bottom sheet whose Remove '
      'deletes it', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    final applied = await _openForward(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Edit port forward'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    final [ops] = applied;
    final remove = ops.single as UciRemove;
    expect((remove.config, remove.section), ('firewall', 'web'));
    await _finish(tester);
  });

  testWidgets('iOS: a port forward opens in a sheet with Save in its '
      'navigation bar and Remove under the fields', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    final applied = await _openForward(tester);

    expect(find.byType(BottomSheet), findsNothing);
    final bar = find.byType(CupertinoNavigationBar).last;
    expect(
      find.descendant(of: bar, matching: find.text('Edit port forward')),
      findsOneWidget,
    );
    expect(find.descendant(of: bar, matching: find.text('Save')), findsOne);

    // Nothing was changed, so Cancel applies nothing.
    await tester.tap(find.descendant(of: bar, matching: find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(applied, isEmpty);

    await tester.tap(find.text('Web server'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AdaptiveButton, 'Remove'));
    await tester.pumpAndSettle();

    final [ops] = applied;
    final remove = ops.single as UciRemove;
    expect((remove.config, remove.section), ('firewall', 'web'));
    await _finish(tester);
  });

  testWidgets('the port and address fields take a keyboard with "." and '
      '"-", not iOS\'s digits-only pad', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    await _openForward(tester);

    TextInputType? keyboard(String label) => tester
        .widget<TextField>(find.widgetWithText(TextField, label))
        .keyboardType;
    for (final label in [
      'External port',
      'Internal address',
      'Internal port',
    ]) {
      expect(keyboard(label), numericAddressKeyboard, reason: label);
    }
    // A subnet needs "/", which only the full keyboard has everywhere.
    expect(keyboard('Source address'), TextInputType.text);
  });
}
