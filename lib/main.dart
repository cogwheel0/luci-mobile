import 'dart:async';

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
    // background poll is the only thing lost.
    Logger.exception('Background monitoring is unavailable', e, stack);
  }
}

class LuCIApp extends ConsumerWidget {
  const LuCIApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      localizationsDelegates: luciLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: (locales, supported) =>
          resolveLuciLocale(locales, supported) ?? supported.first,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        // Edge-to-edge display handled natively in MainActivity
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        // Edge-to-edge display handled natively in MainActivity
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      themeMode: appState.themeMode,
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
