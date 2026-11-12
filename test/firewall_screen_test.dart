import 'dart:io' show Platform;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoDialogAction,
        CupertinoNavigationBar,
        CupertinoNavigationBarBackButton,
        CupertinoTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/firewall_config.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/screens/firewall_screen.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/firewall_notifier.dart';
import 'package:luci_mobile/utils/keyboards.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_hub_tile.dart';
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

/// Shows the firewall. Completes with the list of what the screen goes on
/// to apply.
Future<List<List<UciOperation>>> _pumpFirewall(
  WidgetTester tester, {
  List<FirewallZone> zones = const [
    FirewallZone(section: 'lan', name: 'lan'),
    FirewallZone(section: 'wan', name: 'wan', masq: true),
  ],
  List<TrafficRule> rules = const [],
  List<StaticRoute> routes = const [],
}) async {
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
          (ref) async => FirewallState(
            zones: zones,
            forwards: const [_forward],
            rules: rules,
            routes: routes,
            sectionNames: const {'web'},
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
  return applied;
}

/// Shows the firewall's port forwards, from the list on iOS, and opens
/// [_forward].
Future<List<List<UciOperation>>> _openForward(WidgetTester tester) async {
  final applied = await _pumpFirewall(tester);
  if (PlatformUiCapabilities.isIOS) {
    await tester.tap(find.text('Port forwards'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Web server'));
  await tester.pumpAndSettle();
  return applied;
}

/// What is labelled [label] for VoiceOver, such as an icon button.
Finder _labelled(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

/// Lets the apply report that follows a removal run out.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: a port forward opens in a bottom sheet whose Remove '
      'deletes it once confirmed', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    final applied = await _openForward(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Edit port forward'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);

    // Cancelling the confirmation keeps the forward, and the sheet.
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Remove port forward?')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(
          'This will permanently remove "Web server" from your firewall '
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
    await tester.tap(find.widgetWithText(AdaptiveFormButtonRow, 'Remove'));
    await tester.pumpAndSettle();
    expect(applied, isEmpty, reason: 'not before it is confirmed');
    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Remove'));
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

    // The keyboard the iOS row's own text field asks for.
    TextInputType? keyboard(String label) => tester
        .widget<CupertinoTextField>(
          find.descendant(
            of: find.widgetWithText(AdaptiveFormTextField, label),
            matching: find.byType(CupertinoTextField),
          ),
        )
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

  testWidgets('Android: the four parts are tabs, and port forwards has its '
      'floating add button', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await _pumpFirewall(tester);

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(Tab), findsNWidgets(4));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Web server'), findsOneWidget);
  });

  group('iOS', () {
    setUp(() {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    });

    testWidgets('a list of the four parts, each saying what is in it', (
      tester,
    ) async {
      await _pumpFirewall(tester);

      expect(find.byType(TabBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(CupertinoNavigationBar),
          matching: find.text('Firewall'),
        ),
        findsOneWidget,
      );
      Finder row(String title) => find.ancestor(
        of: find.text(title),
        matching: find.byType(LuciHubTile),
      );
      String rowText(String title) => tester
          .widgetList<Text>(
            find.descendant(of: row(title), matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .join(' | ');

      expect(rowText('Port forwards'), 'Port forwards | Web server | 1');
      expect(rowText('Traffic rules'), 'Traffic rules | No traffic rules');
      expect(rowText('Zones'), 'Zones | lan, wan | 2');
      expect(rowText('Static routes'), 'Static routes | No static routes');
    });

    testWidgets('a long list shows its first five names and the full count', (
      tester,
    ) async {
      await _pumpFirewall(
        tester,
        zones: [
          for (var i = 1; i <= 30; i++)
            FirewallZone(section: 'zone$i', name: 'zone$i'),
        ],
      );

      final row = find.ancestor(
        of: find.text('Zones'),
        matching: find.byType(LuciHubTile),
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text('zone1, zone2, zone3, zone4, zone5, …'),
        ),
        findsOneWidget,
      );
      expect(find.descendant(of: row, matching: find.text('30')), findsOne);
    });

    testWidgets('each row pushes its own page, with a back button', (
      tester,
    ) async {
      await _pumpFirewall(tester);

      await tester.tap(find.text('Zones'));
      await tester.pumpAndSettle();
      final bar = find.byType(CupertinoNavigationBar).last;
      expect(find.descendant(of: bar, matching: find.text('Zones')), findsOne);
      // A group per zone: its name (and NAT) over its three policies.
      expect(find.text('LAN'), findsOneWidget);
      expect(find.text('WAN · NAT'), findsOneWidget);
      expect(find.byType(AdaptiveFormValueRow), findsNWidgets(6));

      await tester.tap(
        find.descendant(
          of: bar,
          matching: find.byType(CupertinoNavigationBarBackButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LuciHubTile), findsNWidgets(4));
    });

    testWidgets('port forwards as grouped rows, each opening to edit, its '
        'switch toggling it without opening it', (tester) async {
      final applied = await _pumpFirewall(tester);
      await tester.tap(find.text('Port forwards'));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNothing);
      final web = find.widgetWithText(AdaptiveListRow, 'Web server');
      expect(
        find.descendant(
          of: web,
          matching: find.textContaining('192.168.1.10:80'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: web, matching: find.byType(AdaptiveSwitch)),
      );
      await tester.pumpAndSettle();
      expect(applied, hasLength(1));
      expect(find.byType(AdaptiveFormSheet), findsNothing);
      await _finish(tester);
    });

    testWidgets(
      'iOS 26: a tap on a forward\'s native switch does not open the '
      'forward, and the switch toggles it',
      (tester) async {
        PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
        PlatformUiCapabilities.debugNativeIOS26Override = true;
        final applied = await _pumpFirewall(tester);
        await tester.tap(find.text('Port forwards'));
        await tester.pumpAndSettle();

        final web = find.widgetWithText(AdaptiveListRow, 'Web server');
        final native = find.descendant(
          of: web,
          matching: find.byType(CNSwitch),
        );
        expect(native, findsOneWidget);
        // A native view claims no tap in Flutter: inside the row's tap
        // target, this tap would open the forward.
        await tester.tap(native);
        await tester.pumpAndSettle();
        expect(find.byType(AdaptiveFormSheet), findsNothing);
        expect(applied, isEmpty);

        // The switch's own change, as the native control reports it.
        tester.widget<CNSwitch>(native).onChanged(false);
        await tester.pumpAndSettle();
        expect(applied, hasLength(1));
        expect(find.byType(AdaptiveFormSheet), findsNothing);
        await _finish(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      skip: !Platform.isMacOS,
    );

    testWidgets('traffic rules and static routes as grouped rows, with '
        'their switch and buttons', (tester) async {
      await _pumpFirewall(
        tester,
        rules: const [
          TrafficRule(
            section: 'luci_mobile_block_tv',
            name: 'Block TV',
            sourceMac: 'aa:bb:cc:00:00:09',
          ),
        ],
        routes: const [
          StaticRoute(
            section: 'vpn',
            interface: 'wg0',
            target: '10.8.0.0',
            netmask: '255.255.255.0',
            gateway: '10.8.0.1',
          ),
        ],
      );

      await tester.tap(find.text('Traffic rules'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      final rule = find.widgetWithText(AdaptiveListRow, 'Block TV');
      expect(
        find.descendant(of: rule, matching: find.byType(AdaptiveSwitch)),
        findsOneWidget,
      );
      // A rule the app wrote is removed, so its button says Remove.
      expect(
        find.descendant(of: rule, matching: _labelled('Remove')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoNavigationBar).last,
          matching: find.byType(CupertinoNavigationBarBackButton),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Static routes'));
      await tester.pumpAndSettle();
      final route = find.ancestor(
        of: find.textContaining('via 10.8.0.1'),
        matching: find.byType(AdaptiveListRow),
      );
      expect(route, findsOneWidget);
      expect(
        find.descendant(of: route, matching: _labelled('Remove')),
        findsOneWidget,
      );
    });

    testWidgets('port forwards adds from the navigation bar\'s +, not a '
        'floating button', (tester) async {
      await _pumpFirewall(tester);
      await tester.tap(find.text('Port forwards'));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(find.byType(LuciAppBarAction));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(CupertinoNavigationBar).last,
          matching: find.text('Add port forward'),
        ),
        findsOneWidget,
      );
    });
  });
}
