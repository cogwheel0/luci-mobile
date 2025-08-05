import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/screens/login_screen.dart';
import 'package:luci_mobile/screens/main_screen.dart';
import 'package:luci_mobile/screens/settings_screen.dart';
import 'package:luci_mobile/screens/splash_screen.dart';
import 'package:luci_mobile/screens/app_lock_screen.dart';
import 'package:luci_mobile/screens/pin_setup_screen.dart';
import 'package:luci_mobile/services/app_lock_service.dart';

void main() {
  runApp(ProviderScope(
    child: const LuCIApp(),
  ));
}

final appStateProvider = ChangeNotifierProvider<AppState>((ref) => AppState.instance);

class LuCIApp extends ConsumerStatefulWidget {
  const LuCIApp({super.key});

  @override
  ConsumerState<LuCIApp> createState() => _LuCIAppState();
}

class _LuCIAppState extends ConsumerState<LuCIApp> with WidgetsBindingObserver {
  late AppLockService _appLockService;
  bool _isAppLockEnabled = false;
  bool _isLocked = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAppLock();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  Future<void> _initializeAppLock() async {
    _appLockService = AppLockService();
    await _appLockService.initialize();
    
    setState(() {
      _isAppLockEnabled = _appLockService.isEnabled;
      _isLocked = _appLockService.isLocked;
    });
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      _checkAppLock();
    }
  }
  
  Future<void> _checkAppLock() async {
    if (_isAppLockEnabled) {
      _appLockService.onAppResumed();
      
      if (_appLockService.isLocked) {
        // Navigate to app lock screen
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/app-lock');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    
    return MaterialApp(
      title: 'LuCI Mobile',
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
        '/main': (context) => const MainScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/app-lock': (context) => const AppLockScreen(),
        '/pin-setup': (context) => const PinSetupScreen(),
      },
    );
  }
}
