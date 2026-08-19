import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/screens/dashboard_screen.dart';
import 'package:luci_mobile/screens/services_screen.dart';
import 'package:luci_mobile/screens/network_screen.dart';
import 'package:luci_mobile/screens/system_screen.dart';
import 'package:luci_mobile/screens/terminal_screen.dart';

void main() {
  runApp(const ProviderScope(child: LuciApp()));
}

class LuciApp extends StatelessWidget {
  const LuciApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Luci Mobile',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          surface: Color(0x15FFFFFF),
        ),
      ),
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    ServicesScreen(),
    NetworkScreen(),
    SystemScreen(),
    TerminalScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // خلفية بتصميم Liquid Glass مع تدرجات لونية هادئة
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF0B0F19),
                    Color(0xFF04060A),
                  ],
                ),
              ),
            ),
          ),
          _screens[_currentIndex],
        ],
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: const Color(0xFF38BDF8),
            unselectedItemColor: Colors.white54,
            selectedFontSize: 12,
            unselectedFontSize: 11,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_rounded),
                label: 'Dashboard',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.room_service_rounded),
                label: 'Services',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.hub_rounded),
                label: 'Network',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_suggest_rounded),
                label: 'System',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.terminal_rounded),
                label: 'Terminal',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
