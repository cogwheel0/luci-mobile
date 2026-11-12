import 'dart:async';

import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoActivityIndicator;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('covered routes hide native buttons beneath dialogs', (
    tester,
  ) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 26;
    PlatformUiCapabilities.debugNativeIOS26Override = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveButton(label: 'Take control', onPressed: () {}),
        ),
      ),
    );
    expect(find.byType(CNButton), findsOneWidget);
    final context = tester.element(find.byType(AdaptiveButton));
    final dialog = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('Input')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CNButton), findsNothing);
    expect(find.byType(CNButton, skipOffstage: false), findsOneWidget);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    await dialog;
    expect(find.byType(CNButton), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'Android filled controls retain readable labels in $brightness',
      (tester) async {
        PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
        final colors = ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(colorScheme: colors),
            home: Scaffold(
              body: AdaptiveButton(
                onPressed: () {},
                label: 'Take control',
                sfSymbol: const SFSymbol('hand.tap'),
              ),
            ),
          ),
        );
        // Material 3's own filled button, coloured by the theme.
        expect(find.byType(FilledButton), findsOneWidget);
        final label = tester.renderObject<RenderParagraph>(
          find.text('Take control'),
        );
        final icon = tester.widget<RichText>(
          find.descendant(
            of: find.byIcon(Icons.touch_app_outlined),
            matching: find.byType(RichText),
          ),
        );
        expect(label.text.style!.color, colors.onPrimary);
        expect(icon.text.style!.color, colors.onPrimary);
        final box = tester.widget<Material>(
          find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(Material),
          ),
        );
        expect(box.color, colors.primary);
      },
    );
  }

  testWidgets(
    'Android chips keep selection, disabled state and separate deletion',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
        var selected = false;
        var changes = 0;
        var deletes = 0;
        var enabled = true;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return AdaptiveChip.input(
                    label: const Text('Tag'),
                    semanticLabel: 'Tag action',
                    selected: selected,
                    enabled: enabled,
                    onSelected: (value) => setState(() {
                      selected = value;
                      changes++;
                    }),
                    onDeleted: () => deletes++,
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('Tag'));
        await tester.pumpAndSettle();
        expect(selected, isTrue);
        expect(changes, 1);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Tag action')),
          isSemantics(
            label: 'Tag action',
            isButton: true,
            isSelected: true,
            hasTapAction: true,
          ),
        );
        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is Tooltip && widget.message == 'Delete',
          ),
        );
        expect(deletes, 1);
        expect(changes, 1);
        update(() => enabled = false);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tag'));
        expect(changes, 1);
        expect(
          tester.widget<InputChip>(find.byType(InputChip)).onDeleted,
          isNull,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('button names retain activation on ${platform.name}', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = platform;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final semantics = tester.ensureSemantics();
      try {
        var presses = 0;
        var enabled = true;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return AdaptiveButton(
                    label: 'Visible',
                    semanticLabel: 'Submit',
                    enabled: enabled,
                    onPressed: () => presses++,
                  );
                },
              ),
            ),
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('Submit')),
          isSemantics(label: 'Submit', isButton: true, hasTapAction: true),
        );
        await tester.tap(find.text('Visible'));
        await tester.pumpAndSettle();
        expect(presses, 1);
        update(() => enabled = false);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.bySemanticsLabel('Submit')),
          isSemantics(label: 'Submit', isButton: true),
        );
        await tester.tap(find.text('Visible'));
        await tester.pumpAndSettle();
        expect(presses, 1);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
      'segments reject missing or duplicate choices on ${platform.name}',
      (tester) async {
        for (final segments in <List<AdaptiveSegment<int>>>[
          [],
          [const AdaptiveSegment(value: 1, label: Text('Only'))],
          [
            const AdaptiveSegment(value: 1, label: Text('One')),
            const AdaptiveSegment(value: 1, label: Text('Duplicate')),
          ],
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(
                body: AdaptiveValueSegmentedControl<int>(
                  segments: segments,
                  value: 1,
                  onChanged: (_) {},
                ),
              ),
            ),
          );
          expect(tester.takeException(), isArgumentError);
        }
      },
    );

    testWidgets(
      'typed segments preserve labels and selection rules on ${platform.name}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          var selected = 1;
          var enabled = true;
          final changes = <int>[];
          late StateSetter update;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return AdaptiveValueSegmentedControl<int>(
                      value: selected,
                      segments: const [
                        AdaptiveSegment(
                          value: 1,
                          label: Text('One'),
                          icon: Icon(Icons.looks_one),
                          semanticLabel: 'First option',
                        ),
                        AdaptiveSegment(
                          value: 2,
                          label: Text('Two'),
                          semanticLabel: 'Second option',
                        ),
                        AdaptiveSegment(
                          value: 3,
                          label: Text('Disabled'),
                          enabled: false,
                        ),
                      ],
                      onChanged: enabled
                          ? (next) => setState(() {
                              selected = next;
                              changes.add(next);
                            })
                          : null,
                    );
                  },
                ),
              ),
            ),
          );
          expect(find.bySemanticsLabel('First option'), findsOneWidget);
          expect(find.byIcon(Icons.looks_one), findsOneWidget);
          expect(find.bySemanticsLabel('Second option'), findsOneWidget);
          expect(
            tester.getSemantics(find.bySemanticsLabel('Disabled')),
            isSemantics(isButton: true, isEnabled: false),
          );
          await tester.tap(find.text('Two'));
          await tester.pumpAndSettle();
          expect(selected, 2);
          expect(changes, [2]);
          expect(
            tester.getSemantics(find.bySemanticsLabel('Second option')),
            isSemantics(isSelected: true),
          );
          await tester.tap(find.text('Two'));
          await tester.tap(find.text('Disabled'));
          await tester.pumpAndSettle();
          expect(changes, [2]);
          update(() => enabled = false);
          await tester.pumpAndSettle();
          await tester.tap(find.text('One'));
          await tester.pumpAndSettle();
          expect(selected, 2);
          expect(changes, [2]);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('progress carries a known value and accessibility text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdaptiveProgressIndicator.linear(
            value: 0.4,
            minHeight: 3,
            semanticLabel: 'Upload',
            semanticValue: '40%',
          ),
        ),
      ),
    );
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.4);
    expect(indicator.semanticsLabel, 'Upload');
    expect(indicator.semanticsValue, '40%');
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('activity progress keeps its radius on ${platform.name}', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = platform;
      const color = Color(0xFF3366CC);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: const Scaffold(
            body: Center(
              child: AdaptiveProgressIndicator.activity(
                radius: 8,
                color: color,
              ),
            ),
          ),
        ),
      );
      final spinner = find.byType(CupertinoActivityIndicator);
      final indicator = tester.widget<CupertinoActivityIndicator>(spinner);
      expect(indicator.radius, 8);
      expect(indicator.color, color);
      expect(tester.getSize(spinner), const Size.square(16));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }

  group('a spinner in place of the Material one', () {
    const color = Color(0xFF3366CC);
    Future<void> pumpIn24(WidgetTester tester) => tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 24,
              child: AdaptiveProgressIndicator(strokeWidth: 2.5, color: color),
            ),
          ),
        ),
      ),
    );

    testWidgets('Android: the Material spinner, as configured', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
      await pumpIn24(tester);

      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.strokeWidth, 2.5);
      expect(indicator.color, color);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('iOS: the system activity indicator, fitted to its box', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      await pumpIn24(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      final spinner = find.byType(CupertinoActivityIndicator);
      expect(tester.widget<CupertinoActivityIndicator>(spinner).color, color);
      // Laid out at its own size, and scaled down to draw in the 24 pt box
      // rather than squeezed or spilling out of it.
      expect(tester.getSize(spinner), const Size.square(36));
      expect(tester.getRect(spinner).size, const Size.square(24));
    });
  });

  group('pull to refresh', () {
    Future<List<String>> pumpAndPull(WidgetTester tester) async {
      final refreshed = <String>[];
      final done = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveRefreshIndicator(
              color: const Color(0xFF3366CC),
              onRefresh: () {
                refreshed.add('pulled');
                return done.future;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [SizedBox(height: 2000, child: Text('top'))],
              ),
            ),
          ),
        ),
      );
      // Down from well inside the list, as a thumb pulls.
      await tester.flingFrom(
        const Offset(400, 100),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      // The scroll settles, then the indicator, which then refreshes.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      addTearDown(done.complete);
      return refreshed;
    }

    testWidgets('Android: the Material indicator, in its colour', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
      final refreshed = await pumpAndPull(tester);

      expect(refreshed, ['pulled']);
      final indicator = tester.widget<RefreshProgressIndicator>(
        find.byType(RefreshProgressIndicator),
      );
      expect(indicator.valueColor?.value, const Color(0xFF3366CC));
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('iOS: the system activity indicator, in its own grey', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final refreshed = await pumpAndPull(tester);

      expect(refreshed, ['pulled']);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      final spinner = tester.widget<CupertinoActivityIndicator>(
        find.byType(CupertinoActivityIndicator),
      );
      expect(spinner.color, isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('a card', () {
    Future<void> pumpCard(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveCard(
            elevation: 2,
            borderRadius: BorderRadius.circular(18),
            margin: EdgeInsets.zero,
            child: const SizedBox(width: 100, height: 60, child: Text('CPU')),
          ),
        ),
      ),
    );

    testWidgets('Android: the Material card, raised and rounded', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
      await pumpCard(tester);

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.elevation, 2);
      expect(
        card.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      );
      expect(card.margin, EdgeInsets.zero);
    });

    testWidgets('iOS: a flat tile in the grouped rows\' surface', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      await pumpCard(tester);

      expect(find.byType(Card), findsNothing);
      final tile = tester.widget<Container>(
        find
            .ancestor(of: find.text('CPU'), matching: find.byType(Container))
            .first,
      );
      final decoration = tile.decoration! as BoxDecoration;
      expect(
        decoration.color,
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          tester.element(find.text('CPU')),
        ),
      );
      expect(decoration.borderRadius, BorderRadius.circular(18));
      expect(decoration.boxShadow, isNull);
    });
  });
}
