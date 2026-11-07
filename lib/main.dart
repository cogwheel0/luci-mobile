import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

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
import 'package:luci_mobile/widgets/app_lock_gate.dart';

export 'package:luci_mobile/state/app_state_provider.dart'
    show appStateProvider;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

  static const _appBarTheme = AppBarTheme(
    // Edge-to-edge display handled natively in MainActivity
    backgroundColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
  );

  /// Pure black surfaces for OLED screens: black pixels are switched off,
  /// which saves power and reads as true black rather than dark grey.
  static ColorScheme _amoled(ColorScheme scheme) => scheme.copyWith(
    surface: Colors.black,
    surfaceDim: Colors.black,
    surfaceContainerLowest: Colors.black,
    surfaceContainerLow: const Color(0xFF0A0A0A),
    surfaceContainer: const Color(0xFF111111),
    surfaceContainerHigh: const Color(0xFF181818),
    surfaceContainerHighest: const Color(0xFF202020),
  );

  static ThemeData _theme(ColorScheme scheme, {bool amoled = false}) =>
      ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        appBarTheme: _appBarTheme,
        scaffoldBackgroundColor: amoled ? Colors.black : null,
        canvasColor: amoled ? Colors.black : null,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // Material You: the wallpaper's palette on Android 12+, when the
        // user wants it and the platform has one; the chosen accent
        // otherwise.
        final useDynamic =
            appState.dynamicColor && lightDynamic != null && darkDynamic != null;
        final seed = appState.accentColor;
        final light = useDynamic
            ? lightDynamic.harmonized()
            : ColorScheme.fromSeed(seedColor: seed);
        var dark = useDynamic
            ? darkDynamic.harmonized()
            : ColorScheme.fromSeed(
                seedColor: seed,
                brightness: Brightness.dark,
              );
        if (appState.amoledBlack) dark = _amoled(dark);

        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          localizationsDelegates: luciLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // A language picked in the app wins over the system's.
          locale: appState.locale,
          localeListResolutionCallback: (locales, supported) =>
              resolveLuciLocale(locales, supported) ?? supported.first,
          theme: _theme(light),
          darkTheme: _theme(dark, amoled: appState.amoledBlack),
          themeMode: appState.themeMode,
          builder: (context, child) => AppLockGate(
            enabled: appState.appLockEnabled,
            ready: appState.appearanceLoaded,
            child: child ?? const SizedBox.shrink(),
          ),
          initialRoute: '/splash',
          routes: {
            '/splash': (context) => const SplashScreen(),
            '/login': (context) => const LoginScreen(),
            '/': (context) => const MainScreen(),
            '/settings': (context) => const SettingsScreen(),
          },
        );
      },
    );
  }
}
