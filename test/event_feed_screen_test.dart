import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/screens/event_feed_screen.dart';
import 'package:luci_mobile/state/event_feed_notifier.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

/// The internet went down, then a phone joined.
class _TwoEvents extends EventFeedNotifier {
  @override
  Future<List<RouterEvent>> build() async => [
    RouterEvent(
      kind: RouterEventKind.wanDown,
      at: DateTime(2026, 11, 12, 9, 30),
      routerId: 'home',
    ),
    RouterEvent(
      kind: RouterEventKind.clientJoined,
      at: DateTime(2026, 11, 12, 10, 15),
      routerId: 'home',
      subject: 'phone',
    ),
  ];
}

Future<void> _pumpFeed(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [eventFeedProvider.overrideWith(_TwoEvents.new)],
      child: const MaterialApp(home: EventFeedScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: list tiles, newest first', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await _pumpFeed(tester);

    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.byType(AdaptiveGroupedListView), findsNothing);
  });

  testWidgets('before iOS 26: one inset group of rows, newest first, each '
      'read as what happened and when', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    final semantics = tester.ensureSemantics();
    await _pumpFeed(tester);

    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(AdaptiveGroupedListView), findsOneWidget);
    final joined = find.widgetWithText(
      AdaptiveListRow,
      'phone joined the network',
    );
    final down = find.widgetWithText(
      AdaptiveListRow,
      'Internet connection went down',
    );
    expect(tester.getTopLeft(joined).dy, lessThan(tester.getTopLeft(down).dy));
    expect(
      tester
          .getSemantics(
            find.descendant(
              of: joined,
              matching: find.text('phone joined the network'),
            ),
          )
          .label,
      // Once, what happened and then when; the icon stays silent.
      'phone joined the network\nNov 12, 2026 10:15',
    );
    semantics.dispose();
  });
}
