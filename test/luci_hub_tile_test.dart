import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_hub_tile.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

/// A hub: a section header and a group of a page, a sign-out and an entry
/// the router cannot support. Records the entries opened.
Future<List<String>> _pumpHub(WidgetTester tester) async {
  final opened = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            const LuciSectionHeader('Device management'),
            LuciHubSection(
              tiles: [
                LuciHubTile(
                  icon: Icons.settings,
                  title: 'Services',
                  subtitle: 'Start and stop services',
                  onTap: () => opened.add('Services'),
                ),
                LuciHubTile(
                  icon: Icons.logout,
                  title: 'Logout',
                  subtitle: 'End your session',
                  titleColor: Colors.red,
                  destructive: true,
                  onTap: () => opened.add('Logout'),
                ),
                LuciHubTile(
                  icon: Icons.block,
                  title: 'SQM',
                  subtitle: 'Not installed on this router',
                  enabled: false,
                  onTap: () => opened.add('SQM'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return opened;
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: a raised card of list tiles under a bold header', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    final opened = await _pumpHub(tester);

    expect(find.byType(Card), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(3));
    expect(find.byType(AdaptiveFormSection), findsNothing);
    expect(find.text('DEVICE MANAGEMENT'), findsOneWidget);

    await tester.tap(find.text('Services'));
    expect(opened, ['Services']);
  });

  testWidgets('before iOS 26: an inset group of rows under a grey header, '
      'a chevron on pages, and sign-out in red', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    final semantics = tester.ensureSemantics();
    final opened = await _pumpHub(tester);

    expect(find.byType(Card), findsNothing);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(AdaptiveFormSection), findsOneWidget);

    final header = tester.widget<Text>(find.text('DEVICE MANAGEMENT'));
    expect(header.style?.fontSize, 13);
    expect(
      header.style?.color,
      CupertinoColors.secondaryLabel.resolveFrom(
        tester.element(find.text('DEVICE MANAGEMENT')),
      ),
    );

    final services = find.widgetWithText(AdaptiveListRow, 'Services');
    expect(
      find.descendant(
        of: services,
        matching: find.byIcon(CupertinoIcons.chevron_right),
      ),
      findsOneWidget,
    );
    // Read once, by its title and what it holds, and opened by a tap.
    expect(
      tester.getSemantics(
        find.descendant(of: services, matching: find.text('Services')),
      ),
      isSemantics(label: 'Services\nStart and stop services', isButton: true),
    );
    await tester.tap(find.text('Services'));
    expect(opened, ['Services']);

    // Sign-out opens no page: red, without a chevron.
    final logout = find.widgetWithText(AdaptiveListRow, 'Logout');
    expect(
      find.descendant(
        of: logout,
        matching: find.byIcon(CupertinoIcons.chevron_right),
      ),
      findsNothing,
    );
    expect(
      tester.widget<Text>(find.text('Logout')).style?.color,
      CupertinoColors.systemRed.resolveFrom(
        tester.element(find.text('Logout')),
      ),
    );

    // An entry the router cannot support stays, dimmed, and opens nothing.
    final sqm = find.widgetWithText(AdaptiveListRow, 'SQM');
    expect(
      find.descendant(
        of: sqm,
        matching: find.byIcon(CupertinoIcons.chevron_right),
      ),
      findsNothing,
    );
    await tester.tap(find.text('SQM'));
    expect(opened, ['Services']);
    semantics.dispose();
  });
}
