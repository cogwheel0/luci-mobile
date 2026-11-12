import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoActivityIndicator, CupertinoAlertDialog;
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/l10n/app_localizations.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';
import 'package:luci_mobile/widgets/luci_apply_progress.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

/// An app whose one button calls [onPressed] with a context under the
/// navigator. A spinner never settles, so [settle] is false behind one.
Future<void> _pumpApp(
  WidgetTester tester,
  void Function(BuildContext context) onPressed, {
  bool settle = true,
  Locale? locale,
}) async {
  tester.view
    ..physicalSize = const Size(1800, 3600)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: luciLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => onPressed(context),
              child: const Text('Go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Go'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// Asks to trust a self-signed certificate; completes with the answer.
Future<Completer<bool?>> _prompt(WidgetTester tester, {Locale? locale}) async {
  final answer = Completer<bool?>();
  await _pumpApp(
    tester,
    (context) => showCertificatePrompt(
      context,
      host: 'router.lan',
      subject: 'CN=OpenWrt',
      issuer: 'CN=OpenWrt',
      validFrom: '2026-01-01 00:00:00',
      validUntil: '2028-01-01 00:00:00',
      fingerprint: 'AB:CD:EF',
    ).then(answer.complete),
    locale: locale,
  );
  return answer;
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  group('certificate prompt', () {
    testWidgets('Android: a Material dialog; Accept Risk trusts it', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
      final answer = await _prompt(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('CN=OpenWrt'), findsNWidgets(2));
      await tester.tap(find.text('Accept Risk'));
      await tester.pumpAndSettle();
      expect(await answer.future, isTrue);
    });

    testWidgets('before iOS 26: a sheet of the certificate\'s details to '
        'read and copy, Cancel in its bar, and Accept Risk spelt out in red', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final answer = await _prompt(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(AdaptiveFormSheet), findsOneWidget);
      expect(find.text('Certificate Warning'), findsOneWidget);
      // The heading loses the colon it has inline in the dialog.
      expect(find.text('CERTIFICATE DETAILS'), findsOneWidget);
      final rows = tester.widgetList<AdaptiveFormValueRow>(
        find.byType(AdaptiveFormValueRow),
      );
      expect(
        [for (final r in rows) (r.label, r.value, r.selectable)],
        [
          ('Subject', 'CN=OpenWrt', true),
          ('Issuer', 'CN=OpenWrt', true),
          ('Valid From', '2026-01-01 00:00:00', true),
          ('Valid Until', '2028-01-01 00:00:00', true),
          ('SHA-256', 'AB:CD:EF', true),
        ],
      );
      expect(find.textContaining('router.lan is not trusted'), findsOneWidget);
      expect(find.textContaining('Only proceed if you trust'), findsOneWidget);

      // No confirm in the bar: the only way on is the red row.
      expect(
        tester
            .widget<AdaptiveFormSheet>(find.byType(AdaptiveFormSheet))
            .confirmLabel,
        isNull,
      );
      final accept = find.widgetWithText(AdaptiveFormButtonRow, 'Accept Risk');
      expect(find.text('Accept Risk'), findsOneWidget);
      expect(tester.widget<AdaptiveFormButtonRow>(accept).destructive, isTrue);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(await answer.future, isTrue);
    });

    testWidgets('before iOS 26: the heading loses a full-width colon too', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      await _prompt(tester, locale: const Locale('zh'));

      expect(find.text('证书详情'), findsOneWidget);
    });

    testWidgets('before iOS 26: Cancel does not trust it', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final answer = await _prompt(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await answer.future, isNot(isTrue));
    });
  });

  group('apply progress', () {
    /// Applies a change that waits on [done], with [progress] showing.
    Future<void> apply(
      WidgetTester tester,
      ApplyProgress progress,
      Completer<void> done,
    ) => _pumpApp(
      tester,
      (context) => LuciApplyProgressDialog.run<void>(
        context,
        progress: progress,
        work: () => done.future,
      ),
      settle: false,
    );

    testWidgets('Android: a Material dialog, the spinner beside the title', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
      final progress = ApplyProgress()
        ..update(ApplyPhase.applying, const Duration(seconds: 90));
      final done = Completer<void>();
      await apply(tester, progress, done);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Applying...'), findsOneWidget);

      done.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('before iOS 26: an iOS alert of the spinner over what is '
        'under way and what is left, closed when the work ends', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final progress = ApplyProgress()
        ..update(ApplyPhase.applying, const Duration(seconds: 90));
      final done = Completer<void>();
      await apply(tester, progress, done);

      expect(find.byType(AlertDialog), findsNothing);
      final alert = find.byType(CupertinoAlertDialog);
      expect(alert, findsOneWidget);
      expect(
        find.descendant(
          of: alert,
          matching: find.byType(CupertinoActivityIndicator),
        ),
        findsOneWidget,
      );
      expect(find.text('Applying...'), findsOneWidget);

      // The countdown follows the router.
      progress.update(ApplyPhase.awaitingConfirm, const Duration(seconds: 30));
      await tester.pump();
      expect(find.text('Confirming...'), findsOneWidget);
      expect(
        find.text('Reverts in 30s if the router cannot be reached'),
        findsOneWidget,
      );

      // A tap outside does not close it.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(alert, findsOneWidget);

      done.complete();
      await tester.pumpAndSettle();
      expect(alert, findsNothing);
    });

    testWidgets('before iOS 26: said up front when the router cannot undo '
        'the change', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final progress = ApplyProgress()
        ..update(ApplyPhase.applying, Duration.zero);
      final done = Completer<void>();
      await apply(tester, progress, done);

      expect(
        find.textContaining('cannot undo the change by itself'),
        findsOneWidget,
      );
      done.complete();
      await tester.pumpAndSettle();
    });
  });
}
