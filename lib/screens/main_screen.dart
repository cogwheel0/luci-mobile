import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/navigation/luci_tab.dart';
import 'package:luci_mobile/navigation/tab_bar_inset.dart';
import 'package:luci_mobile/screens/clients_screen.dart';
import 'package:luci_mobile/screens/dashboard_screen.dart';
import 'package:luci_mobile/screens/insights_screen.dart';
import 'package:luci_mobile/screens/network_screen.dart';
import 'package:luci_mobile/screens/settings_screen.dart';
import 'package:luci_mobile/widgets/luci_navigation_enhancements.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

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

  ({
    IconData filled,
    IconData outlined,
    String symbol,
    String selectedSymbol,
    String label,
  })
  _destination(LuciTab tab, BuildContext context) {
    final l10n = context.l10n;
    return switch (tab) {
      LuciTab.dashboard => (
        filled: Icons.dashboard,
        outlined: Icons.dashboard_outlined,
        symbol: 'square.grid.2x2',
        selectedSymbol: 'square.grid.2x2.fill',
        label: l10n.dashboard,
      ),
      LuciTab.network => (
        filled: Icons.lan,
        outlined: Icons.lan_outlined,
        symbol: 'network',
        selectedSymbol: 'network',
        label: l10n.network,
      ),
      LuciTab.clients => (
        filled: Icons.people,
        outlined: Icons.people_outline,
        symbol: 'person.2',
        selectedSymbol: 'person.2.fill',
        label: l10n.clients,
      ),
      LuciTab.insights => (
        // `insights` is a chart with a sparkle on it, which now reads as
        // "AI" rather than "logs, traffic and diagnostics". A vitals line
        // says what this tab actually holds.
        filled: Icons.monitor_heart,
        outlined: Icons.monitor_heart_outlined,
        symbol: 'waveform.path.ecg',
        selectedSymbol: 'waveform.path.ecg',
        label: l10n.insights,
      ),
      LuciTab.settings => (
        filled: Icons.settings,
        outlined: Icons.settings_outlined,
        symbol: 'gearshape',
        selectedSymbol: 'gearshape.fill',
        label: l10n.settings,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);

    // The dashboard asks for a tab by name; honour it after this frame so the
    // request can be cleared without rebuilding mid-build.
    if (appState.requestedTab != null) {
      final requested = appState.requestedTab!;
      final requestedInterface = appState.requestedInterfaceToScroll;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Cleared whatever happens: a request left standing replays on the
        // next mount, jumping the user to a tab they asked for before
        // logging out - or latches when it names the tab already showing.
        appState.requestedTab = null;
        appState.requestedInterfaceToScroll = null;
        if (!mounted || requested == _selected) return;
        setState(() {
          _selected = requested;
          if (requestedInterface != null) {
            _pendingInterface = requestedInterface;
          }
        });
      });
    }

    final isRebooting = ref.watch(
      appStateProvider.select((state) => state.isRebooting),
    );
    void onTap(int index) {
      final tab = LuciTab.fromIndex(index);
      if (isRebooting && !tab.allowedDuringReboot) return;
      _select(tab);
    }

    Widget body = LuciTabTransition(
      transitionKey: 'tab_${_selected.name}',
      child: _bodyFor(_selected),
    );
    // The iOS 26 tab bar floats over the page instead of sitting under it
    // (AdaptiveScaffold uses it there); pages get its height to clear.
    if (PlatformUiCapabilities.usesNativeIOS26) {
      final media = MediaQuery.of(context);
      final inset = media.padding.bottom + _nativeTabBarHeight;
      body = TabBarInset(
        bottom: inset,
        child: MediaQuery(
          data: media.copyWith(padding: media.padding.copyWith(bottom: inset)),
          child: body,
        ),
      );
    }

    return AdaptiveScaffold(
      body: body,
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        items: [
          for (final tab in LuciTab.values) _adaptiveDestination(context, tab),
        ],
        selectedIndex: _selected.index,
        onTap: onTap,
        // Android keeps its Material bar: a label only on the selected tab
        // when five do not fit, and the reboot lock drawn on each tab.
        bottomNavigationBar: Builder(
          builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            return NavigationBar(
              // Five labels overflow in German and Russian at narrow widths;
              // showing only the selected one keeps them readable without
              // truncating.
              labelBehavior: MediaQuery.sizeOf(context).width < 400
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _selected.index,
              onDestinationSelected: onTap,
              destinations: [
                for (final tab in LuciTab.values)
                  _buildDestination(context, tab, isRebooting, scheme),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Height of the iOS 26 tab bar above the home indicator, with the room
  /// it keeps over its glass for the selection pill: the package measures
  /// the whole bar at about 97 pt on a current iPhone, 34 of them the home
  /// indicator's.
  static const double _nativeTabBarHeight = 64;

  /// A tab as the iOS bars show it: SF Symbols on iOS 26's native bar, and
  /// their Cupertino equivalents on the Flutter one before it.
  AdaptiveNavigationDestination _adaptiveDestination(
    BuildContext context,
    LuciTab tab,
  ) {
    final d = _destination(tab, context);
    return AdaptiveNavigationDestination(
      icon: AdaptiveNavigationIcon.symbol(d.symbol),
      selectedIcon: AdaptiveNavigationIcon.symbol(d.selectedSymbol),
      label: d.label,
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
