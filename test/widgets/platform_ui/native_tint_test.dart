import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNProgressIndicator;

import 'dart:io' show Platform;

import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

ColorScheme _scheme(Brightness brightness) =>
    ColorScheme.fromSeed(seedColor: Colors.blue, brightness: brightness);

/// Themed as AdaptiveApp themes the iOS app: the Cupertino primary is the
/// Material primary, under the Material theme.
Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  final scheme = _scheme(brightness);
  return CupertinoApp(
    theme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: scheme.primary,
    ),
    home: Theme(
      data: ThemeData(colorScheme: scheme),
      child: Center(child: child),
    ),
  );
}

// Tests marked macOS-only need the package's native views; elsewhere its
// fallbacks stand in, which AdaptiveButton and AdaptiveScaffold never show.
void main() {
  setUp(() {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
    PlatformUiCapabilities.debugNativeIOS26Override = true;
  });
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'a filled native button takes the app primary in the '
      '${brightness.name} theme, with a readable label',
      (tester) async {
        final scheme = _scheme(brightness);
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            AdaptiveButton(
              onPressed: () {},
              label: 'Connect',
              sfSymbol: const SFSymbol('wifi'),
            ),
          ),
        );

        final button = tester.widget<CNButton>(find.byType(CNButton));
        expect(button.tint, scheme.primary);
        expect(button.config.labelColor, scheme.onPrimary);
        expect(button.icon!.color, scheme.onPrimary);
        await unmount(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      skip: !Platform.isMacOS,
    );
  }

  testWidgets(
    'prominent glass takes the app primary, with a readable label in the '
    'dark theme',
    (tester) async {
      final scheme = _scheme(Brightness.dark);
      await tester.pumpWidget(
        _host(
          brightness: Brightness.dark,
          AdaptiveButton(
            onPressed: () {},
            label: 'Save',
            style: AdaptiveButtonStyle.prominentGlass,
          ),
        ),
      );

      final button = tester.widget<CNButton>(find.byType(CNButton));
      expect(button.tint, scheme.primary);
      expect(button.config.labelColor, scheme.onPrimary);
      await unmount(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    skip: !Platform.isMacOS,
  );

  testWidgets(
    'a gray native button stays neutral, as its Cupertino fallback is',
    (tester) async {
      await tester.pumpWidget(
        _host(
          AdaptiveButton(
            onPressed: () {},
            label: 'Later',
            style: AdaptiveButtonStyle.gray,
          ),
        ),
      );

      final context = tester.element(find.byType(CNButton));
      expect(
        tester.widget<CNButton>(find.byType(CNButton)).tint,
        CupertinoColors.label.resolveFrom(context),
      );
      await unmount(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    skip: !Platform.isMacOS,
  );

  for (final (state, busy) in [('disabled', false), ('busy', true)]) {
    testWidgets(
      'a $state filled native button keeps the system\'s disabled label',
      (tester) async {
        await tester.pumpWidget(
          _host(
            AdaptiveButton(
              onPressed: busy ? () {} : null,
              busy: busy,
              label: 'Connecting',
              sfSymbol: const SFSymbol('wifi'),
            ),
          ),
        );

        final button = tester.widget<CNButton>(find.byType(CNButton));
        expect(button.enabled, isFalse);
        expect(button.config.labelColor, isNull);
        await unmount(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      skip: !Platform.isMacOS,
    );
  }

  for (final (state, symbolColor, onPressed, expected) in [
    ('an uncoloured', null, () {}, 'onPrimary'),
    ('an explicitly coloured', const Color(0xFFFF9500), () {}, 'explicit'),
    ('a disabled', null, null, 'system'),
  ]) {
    testWidgets('$state filled icon-only native button\'s symbol in the '
        'dark theme', (tester) async {
      final scheme = _scheme(Brightness.dark);
      await tester.pumpWidget(
        _host(
          brightness: Brightness.dark,
          AdaptiveButton.sfSymbol(
            onPressed: onPressed,
            sfSymbol: SFSymbol('plus', color: symbolColor),
            style: AdaptiveButtonStyle.filled,
          ),
        ),
      );

      final button = tester.widget<CNButton>(find.byType(CNButton));
      expect(button.tint, scheme.primary);
      expect(button.icon!.color, switch (expected) {
        'onPrimary' => scheme.onPrimary,
        'explicit' => symbolColor,
        _ => isNull,
      });
      await unmount(tester);
    });
  }

  testWidgets('a plain native button takes the app primary', (tester) async {
    await tester.pumpWidget(
      _host(
        AdaptiveButton.sfSymbol(
          onPressed: () {},
          sfSymbol: const SFSymbol('pencil'),
          style: AdaptiveButtonStyle.plain,
        ),
      ),
    );

    expect(
      tester.widget<CNButton>(find.byType(CNButton)).tint,
      _scheme(Brightness.light).primary,
    );
    await unmount(tester);
  });

  testWidgets('a glass native button takes no tint, so iOS picks its '
      'foreground', (tester) async {
    await tester.pumpWidget(
      _host(
        AdaptiveButton.sfSymbol(
          onPressed: () {},
          sfSymbol: const SFSymbol('arrow.clockwise'),
        ),
      ),
    );

    expect(tester.widget<CNButton>(find.byType(CNButton)).tint, isNull);
    await unmount(tester);
  });

  testWidgets('an explicit colour still wins', (tester) async {
    const red = Color(0xFFB3261E);
    await tester.pumpWidget(
      _host(
        AdaptiveButton(
          onPressed: () {},
          label: 'Exit',
          color: red,
          textColor: CupertinoColors.white,
        ),
      ),
    );

    final button = tester.widget<CNButton>(find.byType(CNButton));
    expect(button.tint, red);
    expect(button.config.labelColor, CupertinoColors.white);
    await unmount(tester);
  });

  testWidgets(
    'the native tab bar takes the app primary',
    (tester) async {
      await tester.pumpWidget(
        _host(
          AdaptiveScaffold(
            bottomNavigationBar: AdaptiveBottomNavigationBar(
              items: const [
                AdaptiveNavigationDestination(
                  icon: AdaptiveNavigationIcon.symbol('square.grid.2x2'),
                  label: 'Dashboard',
                ),
                AdaptiveNavigationDestination(
                  icon: AdaptiveNavigationIcon.symbol('gearshape'),
                  label: 'Settings',
                ),
              ],
              selectedIndex: 0,
              onTap: (_) {},
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );

      expect(
        tester.widget<CNTabBar>(find.byType(CNTabBar)).tint,
        _scheme(Brightness.light).primary,
      );
      await unmount(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    skip: !Platform.isMacOS,
  );

  testWidgets('native progress takes the app primary', (tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 200,
          child: AdaptiveProgressIndicator.linear(value: 0.4),
        ),
      ),
    );

    expect(
      tester.widget<CNProgressIndicator>(find.byType(CNProgressIndicator)).tint,
      _scheme(Brightness.light).primary,
    );
    await unmount(tester);
  });
}
