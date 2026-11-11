import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: ListView(children: [child])),
);

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  group('AdaptiveSwitchListTile', () {
    testWidgets('Android keeps the Material row, which toggles on tap', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
      bool? changed;
      await tester.pumpWidget(
        _host(
          AdaptiveSwitchListTile(
            title: const Text('Hidden SSID'),
            value: false,
            onChanged: (value) => changed = value,
          ),
        ),
      );

      expect(find.byType(SwitchListTile), findsOneWidget);
      await tester.tap(find.text('Hidden SSID'));
      expect(changed, isTrue);
    });

    testWidgets('iOS toggles from the switch only, and reads as one switch', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final semantics = tester.ensureSemantics();
      final changes = <bool>[];
      await tester.pumpWidget(
        _host(
          AdaptiveSwitchListTile(
            title: const Text('Hidden SSID'),
            subtitle: const Text('Not broadcast'),
            value: false,
            onChanged: changes.add,
          ),
        ),
      );

      expect(find.byType(SwitchListTile), findsNothing);
      await tester.tap(find.text('Hidden SSID'));
      expect(changes, isEmpty);
      await tester.tap(find.byType(CupertinoSwitch));
      expect(changes, [true]);
      expect(
        tester.getSemantics(find.text('Hidden SSID')),
        isSemantics(
          label: 'Hidden SSID\nNot broadcast',
          hasToggledState: true,
          isToggled: false,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('iOS 26 uses the native switch', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
      PlatformUiCapabilities.debugNativeIOS26Override = true;
      await tester.pumpWidget(
        _host(
          AdaptiveSwitchListTile(
            title: const Text('Client isolation'),
            value: true,
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.byType(CNSwitch), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a disabled iOS row reads as disabled', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const AdaptiveSwitchListTile(
            title: Text('Hidden SSID'),
            value: true,
            onChanged: null,
          ),
        ),
      );

      expect(
        tester.getSemantics(find.text('Hidden SSID')),
        isSemantics(
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );
      semantics.dispose();
    });
  });

  group('AdaptiveCheckboxListTile', () {
    testWidgets('Android keeps the Material row and its control side', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
      bool? changed;
      await tester.pumpWidget(
        _host(
          AdaptiveCheckboxListTile(
            title: const Text('wlan0'),
            value: true,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) => changed = value,
          ),
        ),
      );

      final tile = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(tile.controlAffinity, ListTileControlAffinity.leading);
      await tester.tap(find.text('wlan0'));
      expect(changed, isFalse);
    });

    for (final value in [true, false]) {
      testWidgets('iOS circles a ${value ? '' : 'un'}chosen row and toggles '
          'from the whole row', (tester) async {
        PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
        final semantics = tester.ensureSemantics();
        bool? changed;
        await tester.pumpWidget(
          _host(
            AdaptiveCheckboxListTile(
              title: const Text('wlan0'),
              value: value,
              onChanged: (next) => changed = next,
            ),
          ),
        );

        expect(find.byType(CheckboxListTile), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
        expect(
          find.byIcon(
            value
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.circle,
          ),
          findsOneWidget,
        );
        expect(
          tester.getSemantics(find.text('wlan0')),
          isSemantics(
            label: 'wlan0',
            hasCheckedState: true,
            isChecked: value,
            hasTapAction: true,
          ),
        );
        await tester.tap(find.text('wlan0'));
        expect(changed, !value);
        semantics.dispose();
      });
    }

    testWidgets('a disabled iOS row does not toggle', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        _host(
          const AdaptiveCheckboxListTile(
            title: Text('wlan0'),
            value: true,
            onChanged: null,
          ),
        ),
      );

      await tester.tap(find.text('wlan0'));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Material segments show their icons beside the labels', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    int? selected;
    await tester.pumpWidget(
      _host(
        AdaptiveSegmentedControl(
          labels: const ['Ping', 'Traceroute'],
          materialIcons: const [Icons.network_ping, Icons.route],
          selectedIndex: 0,
          onValueChanged: (index) => selected = index,
        ),
      ),
    );

    expect(find.text('Ping'), findsOneWidget);
    expect(find.text('Traceroute'), findsOneWidget);
    expect(find.byIcon(Icons.network_ping), findsOneWidget);
    expect(find.byIcon(Icons.route), findsOneWidget);
    await tester.tap(find.text('Traceroute'));
    expect(selected, 1);
  });

  testWidgets('iOS segments stay text when given Material icons', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    await tester.pumpWidget(
      _host(
        AdaptiveSegmentedControl(
          labels: const ['Ping', 'Traceroute'],
          materialIcons: const [Icons.network_ping, Icons.route],
          selectedIndex: 0,
          onValueChanged: (_) {},
        ),
      ),
    );

    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
    expect(find.text('Ping'), findsOneWidget);
    expect(find.byIcon(Icons.network_ping), findsNothing);
  });
}
