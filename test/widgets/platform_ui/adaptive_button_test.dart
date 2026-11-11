import 'dart:io' show Platform;

import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  group('Material', () {
    setUp(
      () =>
          PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android,
    );

    for (final (style, type) in [
      (AdaptiveButtonStyle.filled, FilledButton),
      (AdaptiveButtonStyle.tinted, FilledButton),
      (AdaptiveButtonStyle.bordered, OutlinedButton),
      (AdaptiveButtonStyle.plain, TextButton),
    ]) {
      testWidgets('${style.name} is a $type with the theme\'s own shape', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(AdaptiveButton(onPressed: () {}, label: 'Save', style: style)),
        );

        final button = tester.widget<ButtonStyleButton>(find.byType(type));
        expect(button.style?.shape, isNull);
      });
    }

    testWidgets('a given radius still shapes the button', (tester) async {
      await tester.pumpWidget(
        _host(
          AdaptiveButton(
            onPressed: () {},
            label: 'Save',
            borderRadius: BorderRadius.circular(14),
            useSmoothRectangleBorder: false,
          ),
        ),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(
        button.style!.shape!.resolve(const {}),
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );
    });

    testWidgets('materialIcon replaces the SF Symbol fallback', (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        _host(
          AdaptiveButton(
            onPressed: () => presses++,
            label: 'Save changes',
            sfSymbol: const SFSymbol('square.and.arrow.down'),
            materialIcon: Icons.save,
          ),
        ),
      );

      expect(find.byIcon(Icons.save), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.square_arrow_down), findsNothing);
      await tester.tap(find.text('Save changes'));
      expect(presses, 1);
    });

    testWidgets('busy disables the button and shows progress for its icon', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        _host(
          AdaptiveButton(
            onPressed: () => presses++,
            busy: true,
            label: 'Applying',
            materialIcon: Icons.save,
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.save), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Applying'));
      expect(presses, 0);
    });

    testWidgets('materialVisualDensity reaches the button', (tester) async {
      await tester.pumpWidget(
        _host(
          AdaptiveButton(
            onPressed: () {},
            label: 'Radio',
            style: AdaptiveButtonStyle.plain,
            materialVisualDensity: VisualDensity.compact,
          ),
        ),
      );

      expect(
        tester.widget<TextButton>(find.byType(TextButton)).style!.visualDensity,
        VisualDensity.compact,
      );
    });
  });

  group('Cupertino filled labels', () {
    setUp(() {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    });

    Future<Color?> labelColor(
      WidgetTester tester, {
      required Brightness brightness,
      Color? fill,
    }) async {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      );
      // As AdaptiveApp sets them: the Cupertino primary is the Material one.
      await tester.pumpWidget(
        CupertinoApp(
          theme: CupertinoThemeData(
            brightness: brightness,
            primaryColor: scheme.primary,
          ),
          home: Theme(
            data: ThemeData(colorScheme: scheme),
            child: Center(
              child: AdaptiveButton(
                onPressed: () {},
                label: 'Connect',
                color: fill,
              ),
            ),
          ),
        ),
      );
      return tester.widget<Text>(find.text('Connect')).style?.color;
    }

    for (final brightness in Brightness.values) {
      testWidgets('pair with the ${brightness.name} theme primary', (
        tester,
      ) async {
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        );
        expect(
          await labelColor(tester, brightness: brightness),
          scheme.onPrimary,
        );
      });
    }

    for (final (state, busy, expected) in [
      ('busy', true, CupertinoColors.secondaryLabel),
      ('disabled', false, CupertinoColors.tertiaryLabel),
    ]) {
      for (final style in [
        AdaptiveButtonStyle.filled,
        AdaptiveButtonStyle.plain,
      ]) {
        testWidgets('go grey on a $state ${style.name} button', (tester) async {
          await tester.pumpWidget(
            CupertinoApp(
              home: Center(
                child: AdaptiveButton(
                  onPressed: busy ? () {} : null,
                  busy: busy,
                  label: 'Connecting',
                  style: style,
                ),
              ),
            ),
          );
          final context = tester.element(find.text('Connecting'));
          expect(
            tester.widget<Text>(find.text('Connecting')).style?.color,
            expected.resolveFrom(context),
          );
        });
      }
    }

    testWidgets('read on a custom fill by its brightness', (tester) async {
      expect(
        await labelColor(
          tester,
          brightness: Brightness.dark,
          fill: const Color(0xFFFFEB3B),
        ),
        CupertinoColors.black,
      );
      expect(
        await labelColor(
          tester,
          brightness: Brightness.light,
          fill: const Color(0xFF1B5E20),
        ),
        CupertinoColors.white,
      );
    });
  });

  testWidgets('a busy Cupertino button shows an activity indicator', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    var presses = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: AdaptiveButton(
            onPressed: () => presses++,
            busy: true,
            label: 'Connecting',
            sfSymbol: const SFSymbol('wifi'),
          ),
        ),
      ),
    );

    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.wifi), findsNothing);
    await tester.tap(find.text('Connecting'));
    expect(presses, 0);
  });

  // CNButton draws its native view only on an Apple host; elsewhere its
  // own fallback stands in, which AdaptiveButton never shows.
  testWidgets(
    'a busy native button is disabled and shows only its label',
    (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
      PlatformUiCapabilities.debugNativeIOS26Override = true;
      Widget button({required bool busy}) => _host(
        AdaptiveButton(
          onPressed: () {},
          busy: busy,
          label: busy ? 'Connecting' : 'Connect',
          sfSymbol: const SFSymbol('wifi'),
          materialIcon: Icons.wifi,
        ),
      );

      await tester.pumpWidget(button(busy: false));
      var native = tester.widget<CNButton>(find.byType(CNButton));
      expect(native.enabled, isTrue);
      expect(native.icon?.name, 'wifi');

      await tester.pumpWidget(button(busy: true));
      native = tester.widget<CNButton>(find.byType(CNButton));
      expect(native.enabled, isFalse);
      expect(native.icon, isNull);
      expect(native.label, 'Connecting');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    skip: !Platform.isMacOS,
  );
}
