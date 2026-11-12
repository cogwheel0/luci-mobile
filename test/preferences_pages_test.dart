import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/app_preferences_screen.dart';
import 'package:luci_mobile/screens/notifications_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/notifications_notifier.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

/// The app in reviewer mode, recording the themes chosen.
class _Preferences extends AppState {
  _Preferences()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  final chosen = <ThemeMode>[];

  @override
  bool get reviewerModeEnabled => true;

  @override
  ThemeMode get themeMode => ThemeMode.system;

  @override
  Future<void> setThemeMode(ThemeMode mode) async => chosen.add(mode);
}

/// Notifications switched off, the permission refused.
class _Refused extends NotificationSettingsNotifier {
  @override
  Future<NotificationSettings> build() async =>
      const NotificationSettings(permissionDenied: true);
}

Future<void> _pump(WidgetTester tester, Widget page, {AppState? state}) async {
  tester.view
    ..physicalSize = const Size(1800, 3600)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStateProvider.overrideWith((ref) => state ?? _Preferences()),
        notificationSettingsProvider.overrideWith(_Refused.new),
      ],
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  group('app preferences', () {
    testWidgets('Android: radio tiles and a card', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
      await _pump(tester, const AppPreferencesScreen());

      expect(find.byType(RadioListTile<ThemeMode>), findsNWidgets(3));
      expect(find.byType(AdaptiveFormSection), findsNothing);
    });

    testWidgets('before iOS 26: the theme as checked rows, the dashboard as '
        'a row that opens, and leaving reviewer mode as a red row', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      final state = _Preferences();
      await _pump(tester, const AppPreferencesScreen(), state: state);

      expect(find.byType(RadioListTile<ThemeMode>), findsNothing);
      final system = find.widgetWithText(AdaptiveListRow, 'System Default');
      expect(tester.widget<AdaptiveListRow>(system).selected, isTrue);
      await tester.tap(find.text('Dark'));
      expect(state.chosen, [ThemeMode.dark]);

      expect(
        find.descendant(
          of: find.widgetWithText(AdaptiveListRow, 'Customize Dashboard'),
          matching: find.byIcon(CupertinoIcons.chevron_right),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AdaptiveFormButtonRow>(
              find.widgetWithText(AdaptiveFormButtonRow, 'Exit Reviewer Mode'),
            )
            .destructive,
        isTrue,
      );
    });
  });

  group('notifications', () {
    testWidgets('Android: switch tiles in cards', (tester) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
      await _pump(tester, const NotificationsScreen());

      expect(find.byType(AdaptiveSwitchListTile), findsWidgets);
      expect(find.byType(AdaptiveFormSection), findsNothing);
    });

    testWidgets('before iOS 26: switch rows, the refusal in red under the '
        'first group, and an event\'s switch off while checks are', (
      tester,
    ) async {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
      await _pump(tester, const NotificationsScreen());

      expect(find.byType(AdaptiveSwitchListTile), findsNothing);
      expect(
        find.widgetWithText(AdaptiveFormSwitch, 'Notify in the background'),
        findsOneWidget,
      );
      final first = find.byType(AdaptiveFormSection).first;
      expect(first, findsOneWidget);
      expect(
        tester.widget<AdaptiveFormSection>(first).error,
        contains('notification permission'),
      );
      expect(
        tester
            .widget<AdaptiveFormSwitch>(
              find.widgetWithText(AdaptiveFormSwitch, 'Internet goes down'),
            )
            .onChanged,
        isNull,
      );
    });
  });
}
