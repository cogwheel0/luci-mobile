import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _action({VoidCallback? onPressed}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: LuciAppBarAction(
        sfSymbol: 'arrow.clockwise',
        materialIcon: Icons.refresh,
        tooltip: 'Refresh',
        onPressed: onPressed,
      ),
    ),
  ),
);

AdaptiveButton _button(WidgetTester tester) =>
    tester.widget<AdaptiveButton>(find.byType(AdaptiveButton));

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: an IconButton with the Material icon and tooltip', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    var presses = 0;
    await tester.pumpWidget(_action(onPressed: () => presses++));

    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    expect(presses, 1);
  });

  testWidgets('iOS 26: a Liquid Glass circle, named for VoiceOver', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
    PlatformUiCapabilities.debugNativeIOS26Override = true;
    await tester.pumpWidget(_action(onPressed: () {}));

    final button = _button(tester);
    expect(button.style, AdaptiveButtonStyle.glass);
    expect(button.sfSymbol!.name, 'arrow.clockwise');
    expect(button.semanticLabel, 'Refresh');
    expect(button.minSize, const Size.square(36));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('before iOS 26: a plain tinted symbol', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    await tester.pumpWidget(_action(onPressed: () {}));

    expect(_button(tester).style, AdaptiveButtonStyle.plain);
  });
}
