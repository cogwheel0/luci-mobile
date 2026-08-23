import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/l10n/app_localizations.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/screens/login_screen.dart';
import 'package:luci_mobile/screens/main_screen.dart';
import 'package:luci_mobile/screens/settings_screen.dart';
import 'package:luci_mobile/screens/splash_screen.dart';

void main() {
  runApp(ProviderScope(child: const LuCIApp()));
}

final appStateProvider = ChangeNotifierProvider<AppState>(
  (ref) => AppState.instance,
);

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
