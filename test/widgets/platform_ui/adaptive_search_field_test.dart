import 'dart:io' show Platform;

import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNSearchBar;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  CupertinoApp(
    home: CupertinoPageScaffold(child: Center(child: child)),
  ),
);

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('before iOS 26: a Cupertino search field, kept in step with '
      'the controller, that clears', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final typed = <String>[];
    await _pump(
      tester,
      AdaptiveSearchField(
        controller: controller,
        placeholder: 'Search clients',
        onChanged: typed.add,
      ),
    );

    final field = tester.widget<CupertinoSearchTextField>(
      find.byType(CupertinoSearchTextField),
    );
    expect(field.placeholder, 'Search clients');
    await tester.enterText(find.byType(CupertinoSearchTextField), 'phone');
    expect(controller.text, 'phone');
    expect(typed, ['phone']);

    // Its own clear button empties the controller.
    await tester.pump();
    await tester.tap(find.byIcon(CupertinoIcons.xmark_circle_fill));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(typed.last, isEmpty);
  });

  testWidgets(
    'iOS 26: the system search bar',
    (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
      PlatformUiCapabilities.debugNativeIOS26Override = true;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        AdaptiveSearchField(controller: controller, placeholder: 'Filter log'),
      );

      expect(find.byType(AdaptiveNativeSearchBar), findsOneWidget);
      expect(find.byType(CupertinoSearchTextField), findsNothing);

      // What the person types, as the native field reports it, reaches the
      // controller before the callback; so does clearing it.
      final typed = <(String, String)>[];
      await _pump(
        tester,
        AdaptiveSearchField(
          controller: controller,
          placeholder: 'Filter log',
          onChanged: (text) => typed.add((text, controller.text)),
        ),
      );
      final native = tester.widget<CNSearchBar>(find.byType(CNSearchBar));
      native.onChanged!('dropbear');
      expect(controller.text, 'dropbear');
      native.onChanged!('');
      expect(controller.text, isEmpty);
      expect(typed, [('dropbear', 'dropbear'), ('', '')]);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    skip: !Platform.isMacOS,
  );
}
