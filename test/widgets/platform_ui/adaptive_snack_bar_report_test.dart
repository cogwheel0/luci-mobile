import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The Flutter-drawn iOS banner (private to the layer).
final _banner = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_IOSBanner',
);

Future<BuildContext> _page(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: SizedBox.expand())),
  );
  return tester.element(find.byType(Scaffold));
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  group('Material', () {
    setUp(
      () =>
          PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android,
    );

    testWidgets('information is the theme\'s plain bar', (tester) async {
      final context = await _page(tester);
      AdaptiveSnackBar.show(context, message: 'Copied');
      await tester.pump();

      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.behavior, isNull);
      expect(bar.backgroundColor, isNull);
    });

    testWidgets('a success floats in green with a check', (tester) async {
      final context = await _page(tester);
      AdaptiveSnackBar.show(
        context,
        message: 'Wi-Fi updated',
        type: AdaptiveSnackBarType.success,
      );
      await tester.pump();

      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.behavior, SnackBarBehavior.floating);
      expect(bar.backgroundColor, Colors.green.shade700);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('an error floats in the theme\'s error colours', (
      tester,
    ) async {
      final context = await _page(tester);
      final scheme = Theme.of(context).colorScheme;
      AdaptiveSnackBar.show(
        context,
        message: 'Refresh failed',
        type: AdaptiveSnackBarType.error,
      );
      await tester.pump();

      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.behavior, SnackBarBehavior.floating);
      expect(bar.backgroundColor, scheme.error);
      expect(
        tester.widget<Text>(find.text('Refresh failed')).style?.color,
        scheme.onError,
      );
    });

    testWidgets('messages arriving while a bar closes do not queue', (
      tester,
    ) async {
      final context = await _page(tester);
      AdaptiveSnackBar.show(context, message: 'Copied');
      await tester.pumpAndSettle();
      // Both arrive while that bar is closing.
      AdaptiveSnackBar.show(
        context,
        message: 'Rebooting…',
        type: AdaptiveSnackBarType.warning,
        duration: const Duration(days: 1),
      );
      await tester.pump(const Duration(milliseconds: 50));
      AdaptiveSnackBar.show(
        context,
        message: 'Reboot command failed',
        type: AdaptiveSnackBarType.error,
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Reboot command failed'), findsOneWidget);
      expect(find.text('Rebooting…'), findsNothing);
      expect(find.text('Copied'), findsNothing);
    });

    testWidgets('a new message replaces a long-lived one', (tester) async {
      final context = await _page(tester);
      AdaptiveSnackBar.show(
        context,
        message: 'Rebooting…',
        type: AdaptiveSnackBarType.warning,
        duration: const Duration(days: 1),
      );
      await tester.pumpAndSettle();
      AdaptiveSnackBar.show(
        context,
        message: 'Reboot command sent',
        type: AdaptiveSnackBarType.success,
      );
      await tester.pumpAndSettle();

      expect(find.text('Rebooting…'), findsNothing);
      expect(find.text('Reboot command sent'), findsOneWidget);
    });
  });

  group('iOS 26', () {
    setUp(() {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
      PlatformUiCapabilities.debugNativeIOS26Override = true;
    });

    testWidgets('a three-second message is the native toast', (tester) async {
      final context = await _page(tester);
      AdaptiveSnackBar.show(
        context,
        message: 'Wi-Fi updated',
        duration: const Duration(seconds: 3),
      );
      await tester.pump();

      expect(find.text('Wi-Fi updated'), findsWidgets);
      expect(_banner, findsNothing);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('a toast replaces a long-lived banner', (tester) async {
      final context = await _page(tester);
      AdaptiveSnackBar.show(
        context,
        message: 'Rebooting…',
        type: AdaptiveSnackBarType.warning,
        duration: const Duration(days: 1),
      );
      await tester.pump();
      expect(_banner, findsOneWidget);

      AdaptiveSnackBar.show(
        context,
        message: 'Router back online',
        type: AdaptiveSnackBarType.success,
        duration: const Duration(seconds: 3),
      );
      await tester.pump();

      expect(_banner, findsNothing);
      expect(find.text('Rebooting…'), findsNothing);
      expect(find.text('Router back online'), findsWidgets);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('a banner replaced before its first frame does not stay', (
      tester,
    ) async {
      final context = await _page(tester);
      AdaptiveSnackBar.show(
        context,
        message: 'Rebooting…',
        type: AdaptiveSnackBarType.warning,
        duration: const Duration(minutes: 2),
      );
      AdaptiveSnackBar.show(
        context,
        message: 'Reboot command failed',
        type: AdaptiveSnackBarType.error,
        duration: const Duration(seconds: 3),
      );
      await tester.pump();

      expect(_banner, findsNothing);
      expect(find.text('Rebooting…'), findsNothing);
      expect(find.text('Reboot command failed'), findsWidgets);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('a reporter whose page is gone still shows the native toast', (
      tester,
    ) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Edit')),
        ),
      );
      await tester.pumpAndSettle();
      final report = AdaptiveSnackBar.reporter(
        tester.element(find.text('Edit')),
      );
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      report.show(
        message: 'Wi-Fi updated',
        duration: const Duration(seconds: 3),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_banner, findsNothing);
      expect(find.text('Wi-Fi updated'), findsWidgets);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('a message longer than the toast keeps the banner', (
      tester,
    ) async {
      final context = await _page(tester);
      AdaptiveSnackBar.show(
        context,
        message: 'Rebooting…',
        duration: const Duration(minutes: 1),
      );
      await tester.pump();

      expect(_banner, findsOneWidget);
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
    });
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('a reporter still reports after its page is gone '
        '(${platform.name})', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = platform;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Edit')),
        ),
      );
      await tester.pumpAndSettle();
      final report = AdaptiveSnackBar.reporter(
        tester.element(find.text('Edit')),
      );

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsNothing);
      report.show(message: 'Saved', type: AdaptiveSnackBarType.success);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Saved'), findsWidgets);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });
  }

  group('the iOS banner before iOS 26', () {
    setUp(() {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    });

    Future<void> showWarning(WidgetTester tester) async {
      final context = await _page(tester);
      AdaptiveSnackBar.show(
        context,
        message: 'Rebooting…',
        type: AdaptiveSnackBarType.warning,
        duration: const Duration(minutes: 2),
      );
      await tester.pump();
      expect(_banner, findsOneWidget);
    }

    testWidgets('swiping it up dismisses it', (tester) async {
      await showWarning(tester);

      await tester.fling(find.text('Rebooting…'), const Offset(0, -60), 800);
      await tester.pump();
      expect(_banner, findsNothing);
    });

    testWidgets('VoiceOver can dismiss it', (tester) async {
      final semantics = tester.ensureSemantics();
      await showWarning(tester);

      expect(
        tester.getSemantics(find.text('Rebooting…')),
        isSemantics(hasDismissAction: true),
      );
      tester.semantics.performAction(
        find.semantics.byLabel('Rebooting…'),
        SemanticsAction.dismiss,
      );
      await tester.pump();
      expect(_banner, findsNothing);
      semantics.dispose();
    });
  });
}
