import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A one-field form that confirms with its text, once it has some.
class _NameForm extends StatefulWidget {
  const _NameForm({this.busy = false});

  final bool busy;

  @override
  State<_NameForm> createState() => _NameFormState();
}

class _NameFormState extends State<_NameForm> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdaptiveFormSheet(
    title: 'Rename',
    cancelLabel: 'Cancel',
    confirmLabel: 'Save',
    busy: widget.busy,
    onConfirm: _name.text.isEmpty
        ? null
        : () => Navigator.of(context).pop(_name.text),
    child: TextField(
      key: const Key('name'),
      controller: _name,
      onChanged: (_) => setState(() {}),
    ),
  );
}

/// Opens the form from a page and records what it completes with.
Future<List<String?>> _open(
  WidgetTester tester, {
  required bool cupertino,
  bool busy = false,
}) async {
  final results = <String?>[];
  final opener = Builder(
    builder: (context) => GestureDetector(
      onTap: () async => results.add(
        await showAdaptiveFormSheet<String>(
          context: context,
          builder: (_) => _NameForm(busy: busy),
        ),
      ),
      child: const Text('Open'),
    ),
  );
  await tester.pumpWidget(
    cupertino
        ? CupertinoApp(
            // As the app's iOS root has them, for the forms' Material fields.
            localizationsDelegates: const [
              DefaultMaterialLocalizations.delegate,
              DefaultCupertinoLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            home: CupertinoPageScaffold(child: Center(child: opener)),
          )
        : MaterialApp(
            home: Scaffold(body: Center(child: opener)),
          ),
  );
  await tester.tap(find.text('Open'));
  // A busy form's progress never settles.
  if (busy) {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  } else {
    await tester.pumpAndSettle();
  }
  return results;
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  group('Material', () {
    setUp(
      () =>
          PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android,
    );

    testWidgets('a dialog whose Save confirms with the form\'s value', (
      tester,
    ) async {
      final results = await _open(tester, cupertino: false);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('name')), 'Kitchen TV');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(results, ['Kitchen TV']);
    });

    testWidgets('Cancel completes with null', (tester) async {
      final results = await _open(tester, cupertino: false);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });

    testWidgets('busy shows progress and disables both actions', (
      tester,
    ) async {
      await _open(tester, cupertino: false, busy: true);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });
  });

  group('before iOS 26', () {
    setUp(() {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    });

    testWidgets('a sheet with Cancel and Save in its navigation bar', (
      tester,
    ) async {
      final results = await _open(tester, cupertino: true);

      expect(find.byType(AlertDialog), findsNothing);
      final bar = find.byType(CupertinoNavigationBar);
      expect(bar, findsOneWidget);
      expect(
        find.descendant(of: bar, matching: find.text('Rename')),
        findsOneWidget,
      );
      CupertinoButton barButton(String label) => tester.widget(
        find.ancestor(
          of: find.descendant(of: bar, matching: find.text(label)),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(barButton('Save').onPressed, isNull);

      await tester.enterText(find.byKey(const Key('name')), 'Kitchen TV');
      await tester.pump();
      expect(barButton('Save').onPressed, isNotNull);
      await tester.tap(find.descendant(of: bar, matching: find.text('Save')));
      await tester.pumpAndSettle();
      expect(results, ['Kitchen TV']);
      expect(bar, findsNothing);
    });

    testWidgets('Cancel completes with null', (tester) async {
      final results = await _open(tester, cupertino: true);

      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoNavigationBar),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();
      expect(results, [null]);
    });

    testWidgets('busy shows progress for Save and disables Cancel', (
      tester,
    ) async {
      await _open(tester, cupertino: true, busy: true);

      final bar = find.byType(CupertinoNavigationBar);
      expect(
        find.descendant(
          of: bar,
          matching: find.byType(CupertinoActivityIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('Save')),
        findsNothing,
      );
      final cancel = tester.widget<CupertinoButton>(
        find.ancestor(
          of: find.descendant(of: bar, matching: find.text('Cancel')),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(cancel.onPressed, isNull);
    });
  });

  testWidgets('iOS 26: an ✕ and a prominent ✓ in Liquid Glass, named for '
      'VoiceOver', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
    PlatformUiCapabilities.debugNativeIOS26Override = true;
    final results = await _open(tester, cupertino: true);

    AdaptiveButton barButton(String name) => tester
        .widgetList<AdaptiveButton>(find.byType(AdaptiveButton))
        .singleWhere((button) => button.semanticLabel == name);
    expect(barButton('Cancel').sfSymbol!.name, 'xmark');
    expect(barButton('Save').sfSymbol!.name, 'checkmark');
    expect(barButton('Save').style, AdaptiveButtonStyle.prominentGlass);
    expect(barButton('Save').onPressed, isNull);

    await tester.enterText(find.byKey(const Key('name')), 'Kitchen TV');
    await tester.pump();
    barButton('Save').onPressed!();
    await tester.pumpAndSettle();
    expect(results, ['Kitchen TV']);
  });
}
