import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _tabs = [
  AdaptiveNavigationDestination(
    icon: AdaptiveNavigationIcon.symbol('square.grid.2x2'),
    label: 'Dashboard',
  ),
  AdaptiveNavigationDestination(
    icon: AdaptiveNavigationIcon.symbol('gearshape'),
    label: 'Settings',
  ),
];

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('the iOS root provides a ScaffoldMessenger without a key', (
    tester,
  ) async {
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

    expect(find.byType(CupertinoApp), findsOneWidget);
    expect(ScaffoldMessenger.maybeOf(context), isNotNull);
  });

  testWidgets('pages above the pre-iOS 26 tab bar drop the home indicator '
      'inset that the bar already pads for', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    double? bodyBottomPadding;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: const EdgeInsets.only(bottom: 34)),
            child: AdaptiveScaffold(
              bottomNavigationBar: AdaptiveBottomNavigationBar(
                items: _tabs,
                selectedIndex: 0,
                onTap: (_) {},
              ),
              body: Builder(
                builder: (inner) {
                  bodyBottomPadding = MediaQuery.paddingOf(inner).bottom;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(bodyBottomPadding, 0);
  });

  testWidgets('native icon-only app bar actions keep their names', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
    PlatformUiCapabilities.debugNativeIOS26Override = true;
    await tester.pumpWidget(
      CupertinoApp(
        home: AdaptiveScaffold(
          appBar: AdaptiveAppBar(
            title: 'Clients',
            actions: [
              AdaptiveAppBarAction(
                iosSymbol: 'arrow.clockwise',
                semanticLabel: 'Refresh',
                onPressed: () {},
              ),
            ],
          ),
          body: const SizedBox(),
        ),
      ),
    );

    final button = tester.widget<AdaptiveButton>(find.byType(AdaptiveButton));
    expect(button.semanticLabel, 'Refresh');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  group('segmented control fallbacks', () {
    Widget control({bool enabled = true}) => AdaptiveSegmentedControl(
      labels: const ['Grid', 'List'],
      sfSymbols: const ['square.grid.2x2', 'list.bullet'],
      selectedIndex: 0,
      enabled: enabled,
      onValueChanged: (_) {},
    );

    testWidgets('Cupertino disables every segment when disabled', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      await tester.pumpWidget(CupertinoApp(home: control(enabled: false)));

      final segmented = tester.widget<CupertinoSlidingSegmentedControl<int>>(
        find.byType(CupertinoSlidingSegmentedControl<int>),
      );
      expect(segmented.disabledChildren, {0, 1});
    });

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('${platform.name} icon segments keep their labels', (
        tester,
      ) async {
        PlatformUiCapabilities.debugPlatformOverride = platform;
        PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          platform == TargetPlatform.iOS
              ? CupertinoApp(home: control())
              : MaterialApp(home: Scaffold(body: control())),
        );

        expect(find.bySemanticsLabel(RegExp('Grid')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('List')), findsOneWidget);
        semantics.dispose();
      });
    }
  });

  testWidgets('Material input dialogs show the message', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));

    final result = AdaptiveAlertDialog.inputShow(
      context: tester.element(find.byType(Scaffold)),
      title: 'Rename',
      message: 'Names must be unique.',
      input: const AdaptiveAlertDialogInput(placeholder: 'Name'),
      actions: [
        AlertAction(
          title: 'Cancel',
          style: AlertActionStyle.cancel,
          onPressed: () {},
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Names must be unique.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });
}
