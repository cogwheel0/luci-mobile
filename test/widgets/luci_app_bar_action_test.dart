import 'dart:io' show Platform;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoNavigationBar;
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The system log's bar: a back button, a title and two actions.
Widget _logBar({VoidCallback? onRefresh}) => MaterialApp(
  home: Scaffold(
    appBar: LuciAppBar(
      title: 'System log',
      showBack: true,
      actions: [
        const LuciAppBarAction(
          sfSymbol: 'doc.on.doc',
          materialIcon: Icons.copy,
          tooltip: 'Copy',
          onPressed: null,
        ),
        LuciAppBarAction(
          sfSymbol: 'arrow.clockwise',
          materialIcon: Icons.refresh,
          tooltip: 'Refresh',
          onPressed: onRefresh,
        ),
      ],
    ),
    body: const SizedBox.expand(),
  ),
);

/// Both actions lie inside [bar], side by side, with no layout errors.
void _expectLaidOutIn(WidgetTester tester, Finder bar) {
  expect(tester.takeException(), isNull);
  final barRect = tester.getRect(bar);
  final actions = find.byType(LuciAppBarAction);
  expect(actions, findsNWidgets(2));
  final copy = tester.getRect(actions.at(0));
  final refresh = tester.getRect(actions.at(1));
  for (final rect in [copy, refresh]) {
    expect(rect.left, greaterThanOrEqualTo(barRect.left));
    expect(rect.right, lessThanOrEqualTo(barRect.right));
    expect(rect.top, greaterThanOrEqualTo(barRect.top));
    expect(rect.bottom, lessThanOrEqualTo(barRect.bottom));
  }
  expect(copy.right, lessThanOrEqualTo(refresh.left));
}

AdaptiveButton _button(WidgetTester tester, String tooltip) => tester
    .widgetList<AdaptiveButton>(find.byType(AdaptiveButton))
    .singleWhere((button) => button.semanticLabel == tooltip);

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: IconButtons in the AppBar, with tooltips', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    var refreshes = 0;
    await tester.pumpWidget(_logBar(onRefresh: () => refreshes++));

    _expectLaidOutIn(tester, find.byType(AppBar));
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh'));
    expect(refreshes, 1);
  });

  testWidgets('before iOS 26: plain symbols in the navigation bar', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    var refreshes = 0;
    await tester.pumpWidget(_logBar(onRefresh: () => refreshes++));

    _expectLaidOutIn(tester, find.byType(CupertinoNavigationBar));
    expect(_button(tester, 'Refresh').style, AdaptiveButtonStyle.plain);
    await tester.tap(find.byType(LuciAppBarAction).at(1));
    expect(refreshes, 1);
  });

  // The native buttons are platform views, drawn only on an Apple host.
  testWidgets(
    'iOS 26: Liquid Glass circles in the navigation bar',
    (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
      PlatformUiCapabilities.debugNativeIOS26Override = true;
      await tester.pumpWidget(_logBar(onRefresh: () {}));

      _expectLaidOutIn(tester, find.byType(CupertinoNavigationBar));
      final refresh = _button(tester, 'Refresh');
      expect(refresh.style, AdaptiveButtonStyle.glass);
      expect(refresh.sfSymbol!.name, 'arrow.clockwise');
      expect(
        tester.getSize(find.byType(CNButton).at(1)),
        const Size.square(36),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    skip: !Platform.isMacOS,
  );
}
