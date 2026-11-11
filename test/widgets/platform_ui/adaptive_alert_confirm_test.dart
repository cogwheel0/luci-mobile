import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Opens a confirmation from a button and records its answer.
Future<List<bool>> _openConfirm(
  WidgetTester tester, {
  required bool cupertino,
  bool destructive = false,
}) async {
  final answers = <bool>[];
  final opener = Builder(
    builder: (context) => GestureDetector(
      onTap: () async => answers.add(
        await AdaptiveAlertDialog.confirm(
          context: context,
          title: 'Remove router?',
          message: 'It will be forgotten on this device.',
          confirmLabel: 'Remove',
          cancelLabel: 'Cancel',
          destructive: destructive,
        ),
      ),
      child: const Text('Open'),
    ),
  );
  await tester.pumpWidget(
    cupertino
        ? CupertinoApp(home: Center(child: opener))
        : MaterialApp(
            home: Scaffold(body: Center(child: opener)),
          ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return answers;
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  group('Material', () {
    setUp(
      () =>
          PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android,
    );

    testWidgets('confirming answers true, with a filled confirm button', (
      tester,
    ) async {
      final answers = await _openConfirm(tester, cupertino: false);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('It will be forgotten on this device.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Remove'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(answers, [true]);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a destructive confirmation is a red text button; '
        'cancelling answers false', (tester) async {
      final answers = await _openConfirm(
        tester,
        cupertino: false,
        destructive: true,
      );

      final remove = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Remove'),
      );
      final context = tester.element(find.text('Remove'));
      expect(
        remove.style!.foregroundColor!.resolve(const {}),
        Theme.of(context).colorScheme.error,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answers, [false]);
    });

    testWidgets('dismissing answers false', (tester) async {
      final answers = await _openConfirm(tester, cupertino: false);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(answers, [false]);
    });
  });

  // The native alert answers over the cn_alert channel, with the index of
  // the action chosen, or nothing when it was dismissed or failed. Answering
  // that channel here checks how confirm reads each reply.
  group('iOS 26 native alert', () {
    setUp(() {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
      PlatformUiCapabilities.debugNativeIOS26Override = true;
    });

    for (final (outcome, reply, answer) in [
      ('confirming', <String, Object?>{'index': 1}, true),
      ('cancelling', <String, Object?>{'index': 0}, false),
      ('a dismissed or failed alert', null, false),
    ]) {
      testWidgets('$outcome answers $answer', (tester) async {
        const channel = MethodChannel('cn_alert');
        final messenger = tester.binding.defaultBinaryMessenger;
        Map<Object?, Object?>? sent;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'show') return null;
          sent = call.arguments as Map<Object?, Object?>;
          return reply;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        final answers = await _openConfirm(
          tester,
          cupertino: true,
          destructive: true,
        );

        expect(answers, [answer]);
        expect(find.byType(CupertinoAlertDialog), findsNothing);
        expect(sent!['title'], 'Remove router?');
        expect(sent!['message'], 'It will be forgotten on this device.');
        final actions = (sent!['actions']! as List)
            .cast<Map<Object?, Object?>>();
        expect(
          [for (final action in actions) (action['label'], action['style'])],
          [('Cancel', 'cancel'), ('Remove', 'destructive')],
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    }

    testWidgets('a non-destructive confirmation is the preferred action', (
      tester,
    ) async {
      const channel = MethodChannel('cn_alert');
      final messenger = tester.binding.defaultBinaryMessenger;
      Map<Object?, Object?>? sent;
      messenger.setMockMethodCallHandler(channel, (call) async {
        sent = call.arguments as Map<Object?, Object?>;
        return <String, Object?>{'index': 1};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final answers = await _openConfirm(tester, cupertino: true);

      expect(answers, [true]);
      final remove = (sent!['actions']! as List)
          .cast<Map<Object?, Object?>>()
          .last;
      expect(remove['style'], 'default');
      expect(remove['preferred'], isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('before iOS 26', () {
    setUp(() {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    });

    for (final destructive in [false, true]) {
      testWidgets('a Cupertino alert with a '
          '${destructive ? 'destructive' : 'default'} confirmation', (
        tester,
      ) async {
        final answers = await _openConfirm(
          tester,
          cupertino: true,
          destructive: destructive,
        );

        expect(find.byType(CupertinoAlertDialog), findsOneWidget);
        final remove = tester.widget<CupertinoDialogAction>(
          find.widgetWithText(CupertinoDialogAction, 'Remove'),
        );
        expect(remove.isDestructiveAction, destructive);
        expect(remove.isDefaultAction, !destructive);
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(answers, [true]);
      });
    }

    testWidgets('cancelling answers false', (tester) async {
      final answers = await _openConfirm(tester, cupertino: true);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answers, [false]);
    });
  });
}
