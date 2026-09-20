import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/navigation/luci_tab.dart';
import 'package:luci_mobile/screens/clients_screen.dart';
import 'package:luci_mobile/screens/dashboard_screen.dart';
import 'package:luci_mobile/screens/insights_screen.dart';
import 'package:luci_mobile/screens/network_screen.dart';
import 'package:luci_mobile/screens/settings_screen.dart';
import 'package:luci_mobile/widgets/luci_navigation_enhancements.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key, this.initialTab, this.interfaceToScroll});

  final LuciTab? initialTab;
  final String? interfaceToScroll;

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  LuciTab _selected = LuciTab.dashboard;
  String? _pendingInterface;

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null) _selected = widget.initialTab!;
    _pendingInterface = widget.interfaceToScroll;
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interfaceToScroll != oldWidget.interfaceToScroll) {
      _pendingInterface = widget.interfaceToScroll;
    }
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _selected = widget.initialTab!;
    }
  }

  void _clearPendingInterface() {
    if (_pendingInterface == null) return;
    setState(() => _pendingInterface = null);
  }

  Widget _bodyFor(LuciTab tab) => switch (tab) {
    LuciTab.dashboard => const DashboardScreen(),
    LuciTab.network => NetworkScreen(
      pendingInterface: _pendingInterface,
      onConsumed: _clearPendingInterface,
    ),
    LuciTab.clients => const ClientsScreen(),
    LuciTab.insights => const InsightsScreen(),
    LuciTab.settings => const SettingsScreen(),
  };

  void _select(LuciTab tab) {
    setState(() => _selected = tab);
    if (tab != LuciTab.network) _clearPendingInterface();
  }

  ({IconData filled, IconData outlined, String label}) _destination(
    LuciTab tab,
    BuildContext context,
  ) {
    final l10n = context.l10n;
    return switch (tab) {
      LuciTab.dashboard => (
        filled: Icons.dashboard,
        outlined: Icons.dashboard_outlined,
        label: l10n.dashboard,
      ),
      LuciTab.network => (
        filled: Icons.lan,
        outlined: Icons.lan_outlined,
        label: l10n.network,
      ),
      LuciTab.clients => (
        filled: Icons.people,
        outlined: Icons.people_outline,
        label: l10n.clients,
      ),
      LuciTab.insights => (
        // `insights` is a chart with a sparkle on it, which now reads as
        // "AI" rather than "logs, traffic and diagnostics". A vitals line
        // says what this tab actually holds.
        filled: Icons.monitor_heart,
        outlined: Icons.monitor_heart_outlined,
        label: l10n.insights,
      ),
      LuciTab.settings => (
        filled: Icons.settings,
        outlined: Icons.settings_outlined,
        label: l10n.settings,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);

    // The dashboard asks for a tab by name; honour it after this frame so the
    // request can be cleared without rebuilding mid-build.
    if (appState.requestedTab != null && appState.requestedTab != _selected) {
      final requested = appState.requestedTab!;
      final requestedInterface = appState.requestedInterfaceToScroll;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selected = requested;
          if (requestedInterface != null) {
            _pendingInterface = requestedInterface;
          }
        });
        appState.requestedTab = null;
        appState.requestedInterfaceToScroll = null;
      });
    }

    return Scaffold(
      body: LuciTabTransition(
        transitionKey: 'tab_${_selected.name}',
        child: _bodyFor(_selected),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final isRebooting = ref.watch(
            appStateProvider.select((state) => state.isRebooting),
          );
          final scheme = Theme.of(context).colorScheme;

          return NavigationBar(
            // Five labels overflow in German and Russian at narrow widths;
            // showing only the selected one keeps them readable without
            // truncating.
            labelBehavior: MediaQuery.sizeOf(context).width < 400
                ? NavigationDestinationLabelBehavior.onlyShowSelected
                : NavigationDestinationLabelBehavior.alwaysShow,
            selectedIndex: _selected.index,
            onDestinationSelected: (index) {
              final tab = LuciTab.fromIndex(index);
              if (isRebooting && !tab.allowedDuringReboot) return;
              _select(tab);
            },
            destinations: [
              for (final tab in LuciTab.values)
                _buildDestination(context, tab, isRebooting, scheme),
            ],
          );
        },
      ),
    );
  }

  NavigationDestination _buildDestination(
    BuildContext context,
    LuciTab tab,
    bool isRebooting,
    ColorScheme scheme,
  ) {
    final d = _destination(tab, context);
    final locked = isRebooting && !tab.allowedDuringReboot;
    // Grey is only correct in a light theme; the disabled tone has to come
    // from the scheme or the bar looks broken in dark mode.
    final lockedColor = scheme.onSurface.withValues(alpha: 0.38);

    Widget wrap(IconData icon) => Opacity(
      opacity: locked ? 0.5 : 1.0,
      child: Icon(icon, color: locked ? lockedColor : null),
    );

    return NavigationDestination(
      selectedIcon: wrap(d.filled),
      icon: wrap(d.outlined),
      label: d.label,
      tooltip: locked ? context.l10n.rebootingConnectionInterrupted : d.label,
    );
  }
}
