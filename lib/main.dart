import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'package:luci_mobile/services/background_worker.dart';
import 'package:luci_mobile/utils/logger.dart';

import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/l10n/app_localizations.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/screens/login_screen.dart';
import 'package:luci_mobile/screens/main_screen.dart';
import 'package:luci_mobile/screens/settings_screen.dart';
import 'package:luci_mobile/screens/splash_screen.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

export 'package:luci_mobile/state/app_state_provider.dart'
    show appStateProvider;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Mac detection and the screen's corner radius, for the platform UI layer.
  // Best-effort, and nothing waits on it: until it answers, the layer uses
  // its defaults.
  unawaited(PlatformUiCapabilities.initialize());
  // Registers the entry point WorkManager calls in its own isolate. Cheap
  // and idempotent; nothing is scheduled until the user opts in.
  unawaited(_initBackgroundMonitor());
  runApp(ProviderScope(child: const LuCIApp()));
}

Future<void> _initBackgroundMonitor() async {
  try {
    await Workmanager().initialize(backgroundDispatcher);
    await ensureScheduled();
  } catch (e, stack) {
    // A device without WorkManager must still get a working app; the
    // background poll is the only thing lost - and the switch must say so
    // rather than reading "on" over a task that was never registered.
    Logger.exception('Background monitoring is unavailable', e, stack);
    await backgroundPollUnavailable();
  } finally {
    // Whatever happened, the settings screen must not wait forever.
    settleBackgroundStartup();
  }
}

class LuCIApp extends ConsumerWidget {
  const LuCIApp({super.key});

  static ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: brightness,
    ),
    useMaterial3: true,
    // Edge-to-edge display handled natively in MainActivity
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );

  static final _lightTheme = _theme(Brightness.light);
  static final _darkTheme = _theme(Brightness.dark);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      appStateProvider.select((state) => state.themeMode),
    );
    // CupertinoApp on iOS, MaterialApp elsewhere (see AdaptiveApp).
    return AdaptiveApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      localizationsDelegates: luciLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: (locales, supported) =>
          resolveLuciLocale(locales, supported) ?? supported.first,
      materialLightTheme: _lightTheme,
      materialDarkTheme: _darkTheme,
      themeMode: themeMode,
      material: (_, _) =>
          const MaterialAppData(debugShowCheckedModeBanner: false),
      cupertino: (_, _) =>
          const CupertinoAppData(debugShowCheckedModeBanner: false),
      // The screens are Material and read Theme.of(context). On iOS the root
      // is a CupertinoApp, which provides no Material theme, so every screen
      // would get the light fallback; the app's own theme goes in here, for
      // the brightness the theme mode asks for. On Android this is the theme
      // MaterialApp already applies.
      builder: (context, child) {
        final brightness = switch (themeMode) {
          ThemeMode.dark => Brightness.dark,
          ThemeMode.light => Brightness.light,
          ThemeMode.system => MediaQuery.platformBrightnessOf(context),
        };
        return Theme(
          data: brightness == Brightness.dark ? _darkTheme : _lightTheme,
          child: child ?? const SizedBox.shrink(),
        );
      },
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/': (context) => const MainScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
