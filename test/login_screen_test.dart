import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/login_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// An app state with no saved session, which records sign-ins.
class _TestAppState extends AppState {
  _TestAppState()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  final logins = <String>[];

  @override
  Future<bool> tryAutoLogin({BuildContext? context}) async => false;

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
    return true;
  }
}

/// Shows the login screen, signed out. Completes with its app state.
Future<_TestAppState> _pumpLogin(WidgetTester tester) async {
  FlutterSecureStorage.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
    appName: 'LuCI Mobile',
    packageName: 'app.test',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  // Tall enough for the whole form, wide enough for the test font.
  tester.view
    ..physicalSize = const Size(1800, 3600)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final state = _TestAppState();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => state)],
      child: MaterialApp(
        home: const LoginScreen(),
        routes: {'/main': (_) => const Text('Signed in')},
        onGenerateRoute: (settings) =>
            MaterialPageRoute<void>(builder: (_) => const Text('Signed in')),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  return state;
}

/// The login form's field labelled [label].
Finder _field(String label) => PlatformUiCapabilities.isIOS
    ? find.descendant(
        of: find.widgetWithText(AdaptiveFormTextField, label),
        matching: find.byType(CupertinoTextField),
      )
    : find.widgetWithText(TextFormField, label);

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: the frosted card of Material fields, which '
      'validate before signing in', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    final state = await _pumpLogin(tester);

    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.byType(AdaptiveFormSection), findsNothing);

    await tester.enterText(_field('Router Address'), '');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('Please enter the router address'), findsOneWidget);
    expect(state.logins, isEmpty);
  });

  testWidgets('before iOS 26: grouped rows on the gradient, which say what '
      'is wrong and sign in', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    final state = await _pumpLogin(tester);

    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(AdaptiveFormSection), findsNWidgets(2));

    await tester.enterText(_field('Router Address'), '');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('Please enter the router address'), findsOneWidget);
    expect(state.logins, isEmpty);

    await tester.enterText(_field('Router Address'), '10.0.0.1');
    await tester.pump();
    expect(find.text('Please enter the router address'), findsNothing);
    await tester.enterText(_field('Password'), 'secret');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(state.logins, ['10.0.0.1 root secret']);
  });
}
