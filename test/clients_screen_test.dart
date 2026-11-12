import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/models/station_info.dart';
import 'package:luci_mobile/screens/client_detail_screen.dart';
import 'package:luci_mobile/screens/clients_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/client_detail_notifier.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

final _router = model.Router(
  id: 'home',
  ipAddress: '192.168.1.1',
  username: 'root',
  password: 'password',
  useHttps: false,
);

/// One router, with a phone on 5 GHz Wi-Fi and a laptop that has left.
class _TwoClients extends AppState {
  _TwoClients({this.phoneLease = 3600})
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  /// The phone's lease as the router now reports it, in seconds; 0 for
  /// one with no end.
  final int phoneLease;

  @override
  List<model.Router> get routers => [_router];

  @override
  model.Router? get selectedRouter => _router;

  @override
  Future<List<Client>> fetchClientsForSelectedRouter() async => [
    Client(
      ipAddress: '192.168.1.20',
      macAddress: 'AA:BB:CC:00:00:01',
      hostname: 'phone',
      vendor: 'Apple',
      leaseTime: phoneLease,
      connectionType: ConnectionType.wireless,
      wifiBand: '5g',
      isOnline: true,
    ),
    Client(
      ipAddress: '192.168.1.30',
      macAddress: 'AA:BB:CC:00:00:02',
      hostname: 'laptop',
      isOnline: false,
    ),
  ];
}

Future<void> _pumpClients(WidgetTester tester) async {
  // Wide enough for the test font.
  tester.view
    ..physicalSize = const Size(1800, 2400)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => _TwoClients())],
      child: MaterialApp(
        localizationsDelegates: luciLocalizationsDelegates,
        home: const ClientsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: the cards, which expand in place', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await _pumpClients(tester);

    expect(find.byType(Card), findsNWidgets(2));
    expect(find.byType(AdaptiveGroupedListView), findsNothing);
    expect(find.text('Lease Time Remaining'), findsNothing);

    await tester.tap(find.byTooltip('Expand details').first);
    await tester.pumpAndSettle();
    expect(find.text('Lease Time Remaining'), findsOneWidget);
  });

  testWidgets('before iOS 26: a grouped row per client, which opens its '
      'details', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    final semantics = tester.ensureSemantics();
    await _pumpClients(tester);

    expect(find.byType(Card), findsNothing);
    expect(find.byType(AdaptiveGroupedListView), findsOneWidget);
    final phone = find.widgetWithText(AdaptiveListRow, 'phone');
    // Its address and maker, how it is connected, and a chevron.
    expect(
      find.descendant(of: phone, matching: find.text('192.168.1.20\nApple')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: phone, matching: find.text('5 GHz')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(AdaptiveListRow, 'laptop'),
        matching: find.text('Offline'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: phone,
        matching: find.byIcon(CupertinoIcons.chevron_right),
      ),
      findsOneWidget,
    );
    // No expanding in place on iOS: the row opens the details.
    expect(find.bySemanticsLabel('Expand details'), findsNothing);
    // Read once: its name, address and maker, and how it is connected.
    expect(
      tester.getSemantics(
        find.descendant(of: phone, matching: find.text('phone')),
      ),
      isSemantics(label: 'phone\n192.168.1.20\nApple\n5 GHz', isButton: true),
    );

    await tester.tap(phone);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ClientDetailScreen), findsOneWidget);
    semantics.dispose();
  });

  group('the lease on the details', () {
    int now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

    /// The phone's details, its own reads faked by [detail].
    Future<void> pumpDetails(
      WidgetTester tester,
      Client phone, {
      Future<ClientDetail> Function()? detail,
      int routerLease = 3600,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appStateProvider.overrideWith(
              (ref) => _TwoClients(phoneLease: routerLease),
            ),
            clientDetailProvider(StationInfo.normalizeMac(phone.macAddress))
                .overrideWith(
                  (ref) => detail?.call() ?? Future.value(const ClientDetail()),
                ),
          ],
          child: MaterialApp(
            localizationsDelegates: luciLocalizationsDelegates,
            home: ClientDetailScreen(client: phone),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    /// The lease row's value.
    String lease(WidgetTester tester) {
      final row = find
          .ancestor(
            of: find.text('Lease Time Remaining'),
            matching: find.byType(Row),
          )
          .first;
      return tester
          .widgetList<Text>(
            find.descendant(of: row, matching: find.byType(Text)),
          )
          .last
          .data!;
    }

    Future<void> unmount(WidgetTester tester) async {
      // Let the page's own timers run out once it is gone.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    }

    testWidgets('counts from when the lease ends, not from when the list '
        'was read', (tester) async {
      // Read an hour from its end, but that end has since come.
      await pumpDetails(
        tester,
        Client(
          ipAddress: '192.168.1.20',
          macAddress: 'AA:BB:CC:00:00:01',
          hostname: 'phone',
          leaseTime: 3600,
          expiresAt: now() - 10,
        ),
      );
      await tester.dragUntilVisible(
        find.text('Lease Time Remaining'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      expect(lease(tester), 'Expired');
      await unmount(tester);
    });

    testWidgets('shows while the rest of the details load', (tester) async {
      final never = Completer<ClientDetail>();
      await pumpDetails(
        tester,
        Client(
          ipAddress: '192.168.1.20',
          macAddress: 'AA:BB:CC:00:00:01',
          hostname: 'phone',
          leaseTime: 3600,
        ),
        detail: () => never.future,
      );

      expect(find.byType(LuciCardSkeleton), findsWidgets);
      expect(lease(tester), Client.formatDuration(3600));
      await unmount(tester);
    });

    Future<void> pullToRefresh(WidgetTester tester) async {
      await tester.flingFrom(
        const Offset(400, 100),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('a refresh to a lease with no end shows Unlimited, not the '
        'old end', (tester) async {
      await pumpDetails(
        tester,
        Client(
          ipAddress: '192.168.1.20',
          macAddress: 'AA:BB:CC:00:00:01',
          hostname: 'phone',
          leaseTime: 3600,
          expiresAt: now() + 3600,
          routerId: 'home',
        ),
        routerLease: 0,
      );
      expect(lease(tester), isNot('Unlimited'));

      await pullToRefresh(tester);
      expect(lease(tester), 'Unlimited');
      await unmount(tester);
    });

    testWidgets('an open page counts the lease down to Expired by itself', (
      tester,
    ) async {
      await pumpDetails(
        tester,
        Client(
          ipAddress: '192.168.1.20',
          macAddress: 'AA:BB:CC:00:00:01',
          hostname: 'phone',
          leaseTime: 2,
          expiresAt: now() + 2,
        ),
      );
      // Whatever else the page loads settles first, so nothing but the
      // lease's own tick redraws it below.
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      expect(lease(tester), isNot('Expired'));

      // The lease's end passes in real time; the page's own tick redraws it.
      await tester.runAsync(() => Future.delayed(const Duration(seconds: 3)));
      await tester.pump(const Duration(seconds: 31));
      expect(lease(tester), 'Expired');
      await unmount(tester);
    });

    testWidgets('a refresh reads the lease again from the router', (
      tester,
    ) async {
      // A minute left when the list was read; the router has since renewed
      // it to an hour (see _TwoClients).
      await pumpDetails(
        tester,
        Client(
          ipAddress: '192.168.1.20',
          macAddress: 'AA:BB:CC:00:00:01',
          hostname: 'phone',
          leaseTime: 60,
          routerId: 'home',
        ),
      );
      expect(lease(tester), Client.formatDuration(60));

      await pullToRefresh(tester);
      expect(lease(tester), Client.formatDuration(3600));
      await unmount(tester);
    });
  });
}
