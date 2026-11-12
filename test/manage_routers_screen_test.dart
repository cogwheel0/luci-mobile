import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoIcons, CupertinoNavigationBar, CupertinoTextField;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/screens/manage_routers_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

void main() {
  testWidgets('fallback removal requires confirmation', (tester) async {
    final state = _TestAppState(
      model.Router(
        id: 'router',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
        alternateAddress: 'router.example.com',
        alternateUseHttps: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(home: ManageRoutersScreen()),
      ),
    );

    await tester.tap(find.byTooltip('Remove fallback address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(state.updatedRouter, isNull);

    await tester.tap(find.byTooltip('Remove fallback address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(state.updatedRouter?.hasFallback, isFalse);
  });

  group('the list', () {
    tearDown(PlatformUiCapabilities.resetDebugOverrides);

    Future<void> pumpList(WidgetTester tester) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStateProvider.overrideWith(
            (ref) => _TestAppState(_existing, inUse: true),
          ),
        ],
        child: const MaterialApp(home: ManageRoutersScreen()),
      ),
    );

    testWidgets('Android: the cards and the filled Add Router button', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
      await pumpList(tester);

      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Add Router'), findsOne);
      expect(find.byType(AdaptiveListRow), findsNothing);
    });

    testWidgets('before iOS 26: the routers as grouped rows, the one in use '
        'checked, and Add Router as a row of its own', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final semantics = tester.ensureSemantics();
      await pumpList(tester);

      expect(find.byType(Card), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.text('Active'), findsNothing);
      final row = find.widgetWithText(AdaptiveListRow, '192.168.1.1');
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(CupertinoIcons.checkmark_alt),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(row),
        isSemantics(isSelected: true, isButton: true),
      );
      expect(
        find.widgetWithText(AdaptiveFormButtonRow, 'Add Router'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('adding a router', () {
    tearDown(PlatformUiCapabilities.resetDebugOverrides);

    testWidgets('Android: a dialog that validates, refuses a duplicate, and '
        'signs in', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
      final state = await _openAddRouter(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      final add = find.widgetWithText(FilledButton, 'Add');

      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Please enter the router address'), findsOneWidget);
      expect(state.logins, isEmpty);

      await tester.enterText(_field('Router Address'), '192.168.1.1');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Router already exists.'), findsOneWidget);
      expect(state.logins, isEmpty);

      await tester.enterText(_field('Router Address'), '10.0.0.1');
      await tester.enterText(_field('Password'), 'secret');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(state.logins, ['10.0.0.1 root secret']);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('before iOS 26: a sheet whose Add signs in', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final state = await _openAddRouter(tester);
      expect(find.byType(AlertDialog), findsNothing);
      final bar = find.byType(CupertinoNavigationBar).last;
      expect(
        find.descendant(of: bar, matching: find.text('Add Router')),
        findsOneWidget,
      );

      await tester.enterText(_field('Router Address'), '10.0.0.1');
      await tester.enterText(_field('Password'), 'secret');
      await tester.tap(find.descendant(of: bar, matching: find.text('Add')));
      await tester.pumpAndSettle();
      expect(state.logins, ['10.0.0.1 root secret']);
      expect(find.text('Router Address'), findsNothing);
    });

    testWidgets('before iOS 26: the rows say what is wrong, and a failed '
        'check signs nothing in', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final state = await _openAddRouter(tester);
      final bar = find.byType(CupertinoNavigationBar).last;
      Future<void> add() async {
        await tester.tap(find.descendant(of: bar, matching: find.text('Add')));
        await tester.pumpAndSettle();
      }

      expect(find.byType(TextFormField), findsNothing);
      await add();
      expect(find.text('Please enter the router address'), findsOneWidget);
      expect(state.logins, isEmpty);

      // Editing the field clears its error.
      await tester.enterText(_field('Router Address'), '192.168.1.1');
      await tester.pump();
      expect(find.text('Please enter the router address'), findsNothing);

      // A router already saved: the form's own error, under the sign-in.
      await add();
      expect(find.text('Router already exists.'), findsOneWidget);
      expect(state.logins, isEmpty);

      // The fallback address, once added, must differ from the address.
      await tester.tap(find.text('Add fallback address'));
      await tester.pump();
      await tester.enterText(_field('Router Address'), '10.0.0.1');
      await tester.enterText(_field('Fallback Address'), '10.0.0.1');
      await add();
      // Two notes in that group now, so each names its row.
      expect(
        find.text('Fallback Address: Must differ from primary address'),
        findsOneWidget,
      );
      expect(state.logins, isEmpty);

      // Changing the address clears the fallback's "must differ" too.
      await tester.enterText(_field('Router Address'), '10.0.0.2');
      await tester.pump();
      expect(
        find.text('Fallback Address: Must differ from primary address'),
        findsNothing,
      );

      // A username of spaces is no username.
      await tester.enterText(_field('Username'), '   ');
      await add();
      expect(find.text('Required'), findsOneWidget);
      expect(state.logins, isEmpty);

      await tester.enterText(_field('Username'), 'root');
      await tester.enterText(_field('Fallback Address'), 'router.example.com');
      await tester.enterText(_field('Password'), 'secret');
      await add();
      expect(state.logins, ['10.0.0.2 root secret']);
    });

    testWidgets('before iOS 26: Return while signing in starts no second '
        'sign-in', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final state = await _openAddRouter(tester);
      final pending = state.pendingLogin = Completer<bool>();

      await tester.enterText(_field('Router Address'), '10.0.0.1');
      await tester.enterText(_field('Password'), 'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      // Done closes the keyboard; back in the field, Return again.
      await tester.tap(_field('Password'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(state.logins, ['10.0.0.1 root secret']);

      pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Router Address'), findsNothing);
    });
  });
}

/// The add-router form's field labelled [label]: a Material field on
/// Android, the text field of a grouped row on iOS.
Finder _field(String label) => PlatformUiCapabilities.isIOS
    ? find.descendant(
        of: find.widgetWithText(AdaptiveFormTextField, label),
        matching: find.byType(CupertinoTextField),
      )
    : find.widgetWithText(TextFormField, label);

final _existing = model.Router(
  id: '192.168.1.1-root',
  ipAddress: '192.168.1.1',
  username: 'root',
  password: 'password',
  useHttps: false,
);

Future<_TestAppState> _openAddRouter(WidgetTester tester) async {
  final state = _TestAppState(_existing);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => state)],
      child: const MaterialApp(home: ManageRoutersScreen()),
    ),
  );
  await tester.tap(find.text('Add Router'));
  await tester.pumpAndSettle();
  return state;
}

class _TestAppState extends AppState {
  _TestAppState(this.router, {this.inUse = false})
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  final model.Router router;

  /// Whether [router] is the one the app is connected to.
  final bool inUse;
  model.Router? updatedRouter;

  @override
  List<model.Router> get routers => [router];

  @override
  model.Router? get selectedRouter => inUse ? router : null;

  @override
  Future<void> updateRouter(model.Router router) async =>
      updatedRouter = router;

  final logins = <String>[];

  /// When set, a sign-in waits for it, as one over the network does.
  Completer<bool>? pendingLogin;

  @override
  Future<bool> login(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    bool fromRouter = false,
    String? alternateAddress,
    bool? alternateUseHttps,
    int activeAddressIndex = 0,
    BuildContext? context,
  }) async {
    logins.add('$ip $user $pass');
    return pendingLogin?.future ?? true;
  }
}
