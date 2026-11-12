import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/settings_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Shows Settings, then opens About.
Future<void> _openAbout(WidgetTester tester) async {
  PackageInfo.setMockInitialValues(
    appName: 'LuCI Mobile',
    packageName: 'app.test',
    version: '2.0.1',
    buildNumber: '1',
    buildSignature: '',
  );
  tester.view
    ..physicalSize = const Size(1800, 3600)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStateProvider.overrideWith(
          (ref) => AppState.forTesting(
            apiService: MockApiService(),
            authService: MockAuthService(),
          ),
        ),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('About'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: About is a dialog', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await _openAbout(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Version 2.0.1'), findsOneWidget);
    expect(find.byType(AdaptiveFormValueRow), findsNothing);
  });

  testWidgets('before iOS 26: About opens a page of groups, as its chevron '
      'promises', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
    PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    await _openAbout(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text('LUCI MOBILE'), findsOneWidget);
    final version = tester.widget<AdaptiveFormValueRow>(
      find.byType(AdaptiveFormValueRow),
    );
    expect((version.label, version.value), ('Version', '2.0.1'));
    expect(
      find.text(
        'A mobile client for OpenWrt routers. Open source and free to use.',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(AdaptiveFormButtonRow, 'GitHub Repository'),
      findsOneWidget,
    );
  });
}
