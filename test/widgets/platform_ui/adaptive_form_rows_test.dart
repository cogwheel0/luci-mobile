import 'dart:ui' show SemanticsAction;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ListView(padding: const EdgeInsets.all(16), children: [child]),
    ),
  ),
);

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  group('Android', () {
    setUp(
      () =>
          PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android,
    );

    testWidgets('a text field is the Material field the forms used', (
      tester,
    ) async {
      final typed = <String>[];
      final suffix = IconButton(onPressed: () {}, icon: const Icon(Icons.add));
      await _pump(
        tester,
        AdaptiveFormTextField(
          label: 'Source address',
          placeholder: '203.0.113.0/24',
          helper: 'Optional',
          helperMaxLines: 2,
          error: 'Not an address',
          suffix: suffix,
          keyboardType: TextInputType.text,
          onChanged: typed.add,
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      final decoration = field.decoration!;
      expect(decoration.labelText, 'Source address');
      expect(decoration.hintText, '203.0.113.0/24');
      expect(decoration.helperText, 'Optional');
      expect(decoration.helperMaxLines, 2);
      expect(decoration.errorText, 'Not an address');
      expect(decoration.suffixIcon, same(suffix));
      expect(field.keyboardType, TextInputType.text);
      await tester.enterText(find.byType(TextField), '10.0.0.1');
      expect(typed, ['10.0.0.1']);
    });

    testWidgets('a picker is the Material dropdown, showing the hint for a '
        'value it does not list', (tester) async {
      final chosen = <String?>[];
      await _pump(
        tester,
        AdaptiveFormPicker<String>(
          label: 'Protocol',
          value: 'all',
          hint: 'Automatic',
          choices: const [
            AdaptiveFormChoice('tcp', 'TCP'),
            AdaptiveFormChoice('udp', 'UDP'),
          ],
          onChanged: chosen.add,
        ),
      );

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('Protocol'), findsOneWidget);
      expect(find.text('Automatic'), findsOneWidget);
      await tester.tap(find.text('Automatic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UDP').last);
      await tester.pumpAndSettle();
      expect(chosen, ['udp']);
    });

    testWidgets('a section is a column of its rows, the gap apart, with no '
        'header or footer; a pair is one line', (tester) async {
      await _pump(
        tester,
        const AdaptiveFormSection(
          header: 'Header',
          footer: 'Footer',
          children: [
            AdaptiveFormTextField(label: 'Name'),
            AdaptiveFormPair(
              first: AdaptiveFormTextField(label: 'From'),
              second: AdaptiveFormTextField(label: 'To'),
            ),
          ],
        ),
      );

      expect(find.text('HEADER'), findsNothing);
      expect(find.text('Header'), findsNothing);
      expect(find.text('Footer'), findsNothing);
      final name = tester.getRect(find.byType(TextField).at(0));
      final from = tester.getRect(find.byType(TextField).at(1));
      final to = tester.getRect(find.byType(TextField).at(2));
      expect(from.top - name.bottom, 16);
      expect(from.top, to.top);
      expect(to.left - from.right, 16);
    });

    testWidgets('a form puts the gap between its sections', (tester) async {
      await _pump(
        tester,
        const AdaptiveForm(
          sections: [
            AdaptiveFormSection(children: [AdaptiveFormTextField(label: 'A')]),
            AdaptiveFormSection(children: [AdaptiveFormTextField(label: 'B')]),
          ],
        ),
      );

      final a = tester.getRect(find.byType(TextField).at(0));
      final b = tester.getRect(find.byType(TextField).at(1));
      expect(b.top - a.bottom, 16);
    });
  });

  group('before iOS 26', () {
    setUp(() {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    });

    testWidgets('a section is one surface of rows, its header above and its '
        'rows\' notes and footer below', (tester) async {
      await _pump(
        tester,
        const AdaptiveFormSection(
          header: 'Destination',
          footer: 'Applies to new connections.',
          children: [
            AdaptiveFormTextField(
              label: 'Internal address',
              error: 'Enter a valid IPv4 address',
            ),
            AdaptiveFormTextField(
              label: 'Source address',
              helper: 'Optional: only forward from this subnet',
            ),
          ],
        ),
      );

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(CupertinoTextField), findsNWidgets(2));
      final header = tester.getRect(find.text('DESTINATION'));
      final first = tester.getRect(find.text('Internal address'));
      final second = tester.getRect(find.text('Source address'));
      final error = find.text('Enter a valid IPv4 address');
      final helper = find.text('Optional: only forward from this subnet');
      final footer = find.text('Applies to new connections.');
      expect(header.bottom, lessThan(first.top));
      expect(first.bottom, lessThan(second.top));
      expect(tester.getRect(error).top, greaterThan(second.bottom));
      expect(
        tester.getRect(helper).top,
        greaterThan(tester.getRect(error).bottom),
      );
      expect(
        tester.getRect(footer).top,
        greaterThan(tester.getRect(helper).bottom),
      );

      final context = tester.element(error);
      final red = CupertinoColors.systemRed.resolveFrom(context);
      expect(tester.widget<Text>(error).style!.color, red);
      expect(
        tester.widget<Text>(find.text('Internal address')).style!.color,
        red,
        reason: 'the row with the error says so',
      );
      expect(
        tester.widget<Text>(helper).style!.color,
        CupertinoColors.secondaryLabel.resolveFrom(context),
      );
    });

    testWidgets('a text row puts its value at the end, and tapping the '
        'label edits it', (tester) async {
      final typed = <String>[];
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        AdaptiveFormSection(
          children: [
            AdaptiveFormTextField(
              label: 'Name',
              controller: controller,
              placeholder: 'Required',
              onChanged: typed.add,
            ),
          ],
        ),
      );

      final field = tester.widget<CupertinoTextField>(
        find.byType(CupertinoTextField),
      );
      expect(field.textAlign, TextAlign.end);
      expect(field.placeholder, 'Required');
      expect(
        tester.getRect(find.text('Name')).right,
        lessThan(tester.getRect(find.byType(CupertinoTextField)).left),
      );

      await tester.tap(find.text('Name'));
      await tester.pump();
      expect(field.focusNode!.hasFocus, isTrue);
      await tester.enterText(find.byType(CupertinoTextField), 'NAS');
      expect(typed, ['NAS']);
    });

    testWidgets('a pair is two rows of the group', (tester) async {
      await _pump(
        tester,
        const AdaptiveFormSection(
          children: [
            AdaptiveFormPair(
              first: AdaptiveFormTextField(label: 'From'),
              second: AdaptiveFormTextField(label: 'To'),
            ),
          ],
        ),
      );

      expect(
        tester.getRect(find.text('To')).top,
        greaterThan(tester.getRect(find.text('From')).bottom),
      );
      expect(
        tester.getRect(find.text('To')).left,
        tester.getRect(find.text('From')).left,
      );
    });

    testWidgets('a picker shows its choice and picks from an action sheet', (
      tester,
    ) async {
      final chosen = <String?>[];
      await _pump(
        tester,
        AdaptiveFormSection(
          children: [
            AdaptiveFormPicker<String>(
              label: 'Protocol',
              value: 'tcp',
              choices: const [
                AdaptiveFormChoice('tcp', 'TCP'),
                AdaptiveFormChoice('udp', 'UDP'),
              ],
              onChanged: chosen.add,
            ),
          ],
        ),
      );

      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('TCP'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_up_chevron_down), findsOne);

      await tester.tap(find.text('Protocol'));
      await tester.pumpAndSettle();
      final sheet = find.byType(CupertinoActionSheet);
      expect(sheet, findsOneWidget);
      expect(
        tester
            .widget<CupertinoActionSheetAction>(
              find.widgetWithText(CupertinoActionSheetAction, 'TCP'),
            )
            .isDefaultAction,
        isTrue,
        reason: 'the current choice stands out',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(chosen, isEmpty);

      await tester.tap(find.text('Protocol'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CupertinoActionSheetAction, 'UDP'));
      await tester.pumpAndSettle();
      expect(chosen, ['udp']);
    });

    testWidgets('a disabled picker opens nothing; a value it does not list '
        'shows the hint', (tester) async {
      await _pump(
        tester,
        const AdaptiveFormSection(
          children: [
            AdaptiveFormPicker<String?>(
              label: 'Channel width',
              value: 'HE160',
              hint: 'Automatic',
              choices: [AdaptiveFormChoice('HT20', 'HT20')],
              onChanged: null,
            ),
          ],
        ),
      );

      expect(find.text('Automatic'), findsOneWidget);
      await tester.tap(find.text('Channel width'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsNothing);
    });

    testWidgets('a destructive button row is red and acts', (tester) async {
      var pressed = 0;
      await _pump(
        tester,
        AdaptiveFormSection(
          children: [
            AdaptiveFormButtonRow(
              label: 'Remove',
              destructive: true,
              onPressed: () => pressed++,
            ),
          ],
        ),
      );

      final label = find.text('Remove');
      expect(
        tester.widget<Text>(label).style!.color,
        CupertinoColors.systemRed.resolveFrom(tester.element(label)),
      );
      await tester.tap(label);
      expect(pressed, 1);
    });

    testWidgets('a form leaves the space between groups to the groups', (
      tester,
    ) async {
      await _pump(
        tester,
        const AdaptiveForm(
          materialGap: 100,
          sections: [
            AdaptiveFormSection(children: [AdaptiveFormTextField(label: 'A')]),
            AdaptiveFormSection(children: [AdaptiveFormTextField(label: 'B')]),
          ],
        ),
      );

      final a = tester.getRect(find.byType(CupertinoTextField).at(0));
      final b = tester.getRect(find.byType(CupertinoTextField).at(1));
      expect(b.top - a.bottom, lessThan(100));
    });

    testWidgets('VoiceOver reads a text row as its field, named by its label, '
        'and opens a picker read without the group\'s notes', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        AdaptiveFormSection(
          children: [
            const AdaptiveFormTextField(label: 'Name'),
            AdaptiveFormPicker<String>(
              label: 'Encryption',
              value: 'psk2',
              choices: const [AdaptiveFormChoice('psk2', 'WPA2-PSK')],
              onChanged: (_) {},
              helper: 'Applies to every client',
            ),
          ],
        ),
      );

      expect(
        tester.getSemantics(find.byType(CupertinoTextField)).label,
        'Name',
      );
      final picker = tester.getSemantics(
        find.byWidgetPredicate((w) => w is AdaptiveFormPicker<String>),
      );
      expect(picker.label, 'Encryption');
      expect(picker.value, 'WPA2-PSK');
      expect(picker.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      tester.semantics.tap(find.semantics.byLabel('Encryption'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a hardware keyboard reaches a picker and a button row with '
        'Tab, and acts on them', (tester) async {
      var removed = 0;
      await _pump(
        tester,
        AdaptiveFormSection(
          children: [
            AdaptiveFormPicker<String>(
              label: 'Protocol',
              value: 'tcp',
              choices: const [AdaptiveFormChoice('tcp', 'TCP')],
              onChanged: (_) {},
            ),
            AdaptiveFormButtonRow(
              label: 'Remove',
              destructive: true,
              onPressed: () => removed++,
            ),
          ],
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(removed, 1);
    });

    testWidgets('on a narrow screen with large text, a picker\'s label wraps '
        'and its choice stays in the row', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 640)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pump(
        tester,
        AdaptiveFormSection(
          children: [
            AdaptiveFormPicker<String>(
              label: 'Destination zone',
              value: 'lan',
              choices: const [AdaptiveFormChoice('lan', 'lan')],
              onChanged: (_) {},
            ),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      final value = tester.getRect(find.text('lan'));
      expect(value.width, greaterThan(0));
      expect(value.right, lessThanOrEqualTo(320));
      expect(
        tester.getRect(find.text('Destination zone')).right,
        lessThan(value.left),
      );
    });

    testWidgets('a choice made after the picker has gone reaches no one', (
      tester,
    ) async {
      final chosen = <String?>[];
      var showPicker = true;
      late StateSetter setHost;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            setHost = setState;
            return AdaptiveFormSection(
              children: [
                if (showPicker)
                  AdaptiveFormPicker<String>(
                    label: 'Protocol',
                    value: 'tcp',
                    choices: const [
                      AdaptiveFormChoice('tcp', 'TCP'),
                      AdaptiveFormChoice('udp', 'UDP'),
                    ],
                    onChanged: chosen.add,
                  )
                else
                  const AdaptiveFormTextField(label: 'Name'),
              ],
            );
          },
        ),
      );

      await tester.tap(find.text('Protocol'));
      await tester.pumpAndSettle();
      // The form goes, say its sheet closed, while the choices are up.
      setHost(() => showPicker = false);
      await tester.pump();
      await tester.tap(find.widgetWithText(CupertinoActionSheetAction, 'UDP'));
      await tester.pumpAndSettle();

      expect(chosen, isEmpty);
    });

    testWidgets('VoiceOver can press a text row\'s suffix on its own, the '
        'field keeping its name', (tester) async {
      final semantics = tester.ensureSemantics();
      var pressed = 0;
      await _pump(
        tester,
        AdaptiveFormSection(
          children: [
            AdaptiveFormTextField(
              label: 'Password',
              obscureText: true,
              // Not a CupertinoButton, which is an element of its own
              // anyway: a suffix with a plain tap handler.
              suffix: Semantics(
                button: true,
                label: 'Show password',
                onTap: () => pressed++,
                child: const Icon(CupertinoIcons.eye),
              ),
            ),
          ],
        ),
      );

      expect(
        tester.getSemantics(find.byType(CupertinoTextField)).label,
        'Password',
      );
      final suffix = find.semantics.byLabel('Show password');
      expect(
        suffix.evaluate().single.isMergedIntoParent,
        isFalse,
        reason: 'an element of its own, not part of the field\'s row',
      );
      tester.semantics.tap(suffix);
      await tester.pump();
      expect(pressed, 1);
      semantics.dispose();
    });
  });
}
