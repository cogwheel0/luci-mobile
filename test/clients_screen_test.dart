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
  _TwoClients()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

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
      leaseTime: 3600,
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

  testWidgets('the details show how long the lease has left, as the '
      'Android card did expanded', (tester) async {
    final phone = Client(
      ipAddress: '192.168.1.20',
      macAddress: 'AA:BB:CC:00:00:01',
      hostname: 'phone',
      leaseTime: 3600,
      isOnline: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStateProvider.overrideWith((ref) => _TwoClients()),
          clientDetailProvider(StationInfo.normalizeMac(phone.macAddress))
              .overrideWith((ref) async => const ClientDetail()),
        ],
        child: MaterialApp(
          localizationsDelegates: luciLocalizationsDelegates,
          home: ClientDetailScreen(client: phone),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.dragUntilVisible(
      find.text('Lease Time Remaining'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    final row = find.ancestor(
      of: find.text('Lease Time Remaining'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(
        of: row.first,
        matching: find.text(Client.formatDuration(3600)),
      ),
      findsOneWidget,
    );
    // Let the page's own timers run out once it is gone.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
