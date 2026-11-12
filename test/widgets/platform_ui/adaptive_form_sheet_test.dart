import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A one-field form that confirms with its text, once it has some.
class _NameForm extends StatefulWidget {
  const _NameForm({this.busy = false, this.removable = false});

  final bool busy;

  /// Offers a Remove action that completes with "removed".
  final bool removable;

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
    subtitle: widget.removable ? 'Living room' : null,
    cancelLabel: 'Cancel',
    confirmLabel: 'Save',
    busy: widget.busy,
    destructiveLabel: widget.removable ? 'Remove' : null,
    onDestructive: widget.removable
        ? () => Navigator.of(context).pop('removed')
        : null,
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
  bool removable = false,
  AdaptiveFormMaterialPresentation material =
      const AdaptiveFormMaterialPresentation.dialog(),
}) async {
  final results = <String?>[];
  final opener = Builder(
    builder: (context) => GestureDetector(
      onTap: () async => results.add(
        await showAdaptiveFormSheet<String>(
          context: context,
          material: material,
          builder: (_) => _NameForm(busy: busy, removable: removable),
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

    testWidgets('a dialog shows the subtitle under its title and a red '
        'Remove before Cancel', (tester) async {
      final results = await _open(tester, cupertino: false, removable: true);

      expect(find.text('Living room'), findsOneWidget);
      final remove = find.widgetWithText(TextButton, 'Remove');
      expect(
        tester.getCenter(remove).dx,
        lessThan(
          tester.getCenter(find.widgetWithText(TextButton, 'Cancel')).dx,
        ),
      );
      expect(
        tester
            .widget<TextButton>(remove)
            .style!
            .foregroundColor!
            .resolve(const {}),
        Theme.of(tester.element(remove)).colorScheme.error,
      );
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(results, ['removed']);
    });

    testWidgets('a busy form ignores the backdrop and Back', (tester) async {
      final results = await _open(tester, cupertino: false, busy: true);

      await tester.tapAt(const Offset(4, 4));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(results, isEmpty);
    });
  });

  group('Material bottom sheet', () {
    setUp(
      () =>
          PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android,
    );

    const bottomSheet = AdaptiveFormMaterialPresentation.bottomSheet();

    testWidgets('a bottom sheet with its title, subtitle and a row of Remove, '
        'Cancel and Save', (tester) async {
      final results = await _open(
        tester,
        cupertino: false,
        removable: true,
        material: bottomSheet,
      );

      expect(find.byType(AlertDialog), findsNothing);
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      expect(
        tester.widget<BottomSheet>(sheet).showDragHandle,
        isTrue,
        reason: 'as the sheets luci-mobile showed had',
      );
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Living room'), findsOneWidget);
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      // Remove leads the row, in the theme's error colour.
      final remove = find.widgetWithText(TextButton, 'Remove');
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      expect(
        tester.getCenter(remove).dx,
        lessThan(tester.getCenter(cancel).dx),
      );
      final context = tester.element(remove);
      expect(
        tester
            .widget<TextButton>(remove)
            .style!
            .foregroundColor!
            .resolve(const {}),
        Theme.of(context).colorScheme.error,
      );

      await tester.enterText(find.byKey(const Key('name')), 'Kitchen TV');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(results, ['Kitchen TV']);
      expect(sheet, findsNothing);
    });

    testWidgets('Remove completes with its own value', (tester) async {
      final results = await _open(
        tester,
        cupertino: false,
        removable: true,
        material: bottomSheet,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(results, ['removed']);
    });

    testWidgets('Cancel and dragging it away complete with null', (
      tester,
    ) async {
      final results = await _open(
        tester,
        cupertino: false,
        material: bottomSheet,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.fling(find.text('Rename'), const Offset(0, 600), 2000);
      await tester.pumpAndSettle();

      expect(results, [null, null]);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('busy disables Remove and Cancel and ignores Back', (
      tester,
    ) async {
      final results = await _open(
        tester,
        cupertino: false,
        busy: true,
        removable: true,
        material: bottomSheet,
      );

      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Remove'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('a sheet drawing its own handle can turn the stock one off', (
      tester,
    ) async {
      await _open(
        tester,
        cupertino: false,
        material: const AdaptiveFormMaterialPresentation.bottomSheet(
          showDragHandle: false,
        ),
      );

      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isFalse,
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

    testWidgets('the subtitle sits under the title in the navigation bar', (
      tester,
    ) async {
      await _open(tester, cupertino: true, removable: true);

      final bar = find.byType(CupertinoNavigationBar);
      final title = find.descendant(of: bar, matching: find.text('Rename'));
      final subtitle = find.descendant(
        of: bar,
        matching: find.text('Living room'),
      );
      expect(subtitle, findsOneWidget);
      expect(
        tester.getCenter(subtitle).dy,
        greaterThan(tester.getCenter(title).dy),
      );
    });

    testWidgets('Remove is a red button under the fields, completing with '
        'its own value', (tester) async {
      final results = await _open(tester, cupertino: true, removable: true);

      final bar = find.byType(CupertinoNavigationBar);
      expect(
        find.descendant(of: bar, matching: find.text('Remove')),
        findsNothing,
      );
      final remove = find.widgetWithText(AdaptiveButton, 'Remove');
      expect(
        tester.getTopLeft(remove).dy,
        greaterThan(tester.getBottomLeft(find.byKey(const Key('name'))).dy),
      );
      final button = tester.widget<AdaptiveButton>(remove);
      expect(
        button.color,
        CupertinoColors.systemRed.resolveFrom(tester.element(remove)),
      );
      expect(button.style, AdaptiveButtonStyle.tinted);

      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(results, ['removed']);
    });

    testWidgets('busy disables Remove', (tester) async {
      await _open(tester, cupertino: true, busy: true, removable: true);

      expect(
        tester
            .widget<AdaptiveButton>(
              find.widgetWithText(AdaptiveButton, 'Remove'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('a form without a destructive action shows no button for '
        'one', (tester) async {
      await _open(tester, cupertino: true);

      expect(find.text('Remove'), findsNothing);
      expect(find.text('Living room'), findsNothing);
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
    // iOS's minimum tap target, the navigation bar's height.
    expect(barButton('Cancel').minSize, const Size.square(44));
    expect(barButton('Save').minSize, const Size.square(44));
    expect(barButton('Save').onPressed, isNull);

    await tester.enterText(find.byKey(const Key('name')), 'Kitchen TV');
    await tester.pump();
    barButton('Save').onPressed!();
    await tester.pumpAndSettle();
    expect(results, ['Kitchen TV']);
  });
}
