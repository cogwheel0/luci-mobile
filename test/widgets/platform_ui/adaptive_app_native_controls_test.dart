import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('on iOS, the app tells native controls when a sheet covers '
      'their page, and when it has gone', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    late BuildContext context;
    await tester.pumpWidget(
      AdaptiveApp(
        home: Builder(
          builder: (inner) {
            context = inner;
            return const SizedBox();
          },
        ),
      ),
    );

    final app = tester.widget<CupertinoApp>(find.byType(CupertinoApp));
    expect(
      app.navigatorObservers!.whereType<CNTabBarRouteObserver>(),
      hasLength(1),
    );

    final depth = CNTabBarRouteObserver.anyModalDepth;
    final before = depth.value;
    unawaited(
      showCupertinoSheet<void>(
        context: context,
        scrollableBuilder: (_, controller) =>
            ListView(controller: controller, children: const [Text('Sheet')]),
      ),
    );
    await tester.pumpAndSettle();
    expect(depth.value, before + 1);

    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(depth.value, before);
  });

  testWidgets('the app keeps its own observers beside it', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    final mine = NavigatorObserver();
    await tester.pumpWidget(
      AdaptiveApp(home: const SizedBox(), navigatorObservers: [mine]),
    );

    final app = tester.widget<CupertinoApp>(find.byType(CupertinoApp));
    expect(app.navigatorObservers, contains(mine));
  });

  testWidgets('Android, which has no native controls, adds nothing', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(const AdaptiveApp(home: SizedBox()));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.navigatorObservers, isEmpty);
  });
}
