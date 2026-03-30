import 'package:flutter/material.dart';
import 'package:luci_mobile/screens/dashboard_screen.dart';
import 'package:luci_mobile/screens/clients_screen.dart';
import 'package:luci_mobile/screens/interfaces_screen.dart';
import 'package:luci_mobile/screens/more_screen.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/widgets/luci_navigation_enhancements.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int? initialTab;
  final String? interfaceToScroll;

  const MainScreen({super.key, this.initialTab, this.interfaceToScroll});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;
  String? _currentInterfaceToScroll;

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null) {
      _selectedIndex = widget.initialTab!;
    }
    _currentInterfaceToScroll = widget.interfaceToScroll;
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle parameter changes (important for iOS navigation)
    if (widget.interfaceToScroll != oldWidget.interfaceToScroll) {
      _currentInterfaceToScroll = widget.interfaceToScroll;
    }

    // Handle initial tab changes
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _selectedIndex = widget.initialTab!;
    }
  }

  void _clearInterfaceToScroll() {
    if (_currentInterfaceToScroll != null) {
      setState(() {
        _currentInterfaceToScroll = null;
      });
    }
  }

  List<Widget> get _widgetOptions => [
    const DashboardScreen(),
    const ClientsScreen(),
    InterfacesScreen(
      scrollToInterface: _currentInterfaceToScroll,
      onScrollComplete: _clearInterfaceToScroll,
    ),
    const MoreScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    // Clear interface scroll state when navigating away from Interfaces tab
    if (_selectedIndex != 2 && _currentInterfaceToScroll != null) {
      _clearInterfaceToScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for requestedTab in AppState
    final appState = ref.watch(appStateProvider);
    if (appState.requestedTab != null &&
        appState.requestedTab != _selectedIndex) {
      // Store the values before the callback to avoid null reference issues
      final requestedTab = appState.requestedTab!;
      final requestedInterface = appState.requestedInterfaceToScroll;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedIndex = requestedTab;
          // Update interface to scroll if provided
          if (requestedInterface != null) {
            _currentInterfaceToScroll = requestedInterface;
          }
        });
        appState.requestedTab = null;
        appState.requestedInterfaceToScroll = null;
      });
    }
    return Scaffold(
      body: Center(
        child: LuciTabTransition(
          transitionKey: 'tab_$_selectedIndex',
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final isRebooting = ref.watch(
            appStateProvider.select((state) => state.isRebooting),
          );
          Color? getTabColor(int index) =>
              (isRebooting && index != 3) ? Colors.grey.withAlpha(128) : null;
          double getTabOpacity(int index) =>
              (isRebooting && index != 3) ? 0.5 : 1.0;
          return NavigationBar(
            onDestinationSelected: (index) {
              if (isRebooting && index != 3) return; // Only allow 'More' tab
              _onItemTapped(index);
            },
            selectedIndex: _selectedIndex,
            destinations: [
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(0),
                  child: Icon(Icons.dashboard, color: getTabColor(0)),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(0),
                  child: Icon(Icons.dashboard_outlined, color: getTabColor(0)),
                ),
                label: 'Dashboard',
              ),
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(1),
                  child: Icon(Icons.people, color: getTabColor(1)),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(1),
                  child: Icon(Icons.people_outline, color: getTabColor(1)),
                ),
                label: 'Clients',
              ),
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(2),
                  child: Icon(Icons.lan, color: getTabColor(2)),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(2),
                  child: Icon(Icons.lan_outlined, color: getTabColor(2)),
                ),
                label: 'Interfaces',
              ),
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(3),
                  child: Icon(Icons.more_horiz),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(3),
                  child: Icon(Icons.more_horiz_outlined),
                ),
                label: 'More',
              ),
            ],
          );
        },
      ),
    );
  }
}
