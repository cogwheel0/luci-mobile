import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/screens/addons_screen.dart';
import 'package:luci_mobile/screens/firewall_screen.dart';
import 'package:luci_mobile/screens/interfaces_screen.dart';
import 'package:luci_mobile/screens/wifi_scan_screen.dart';
import 'package:luci_mobile/screens/wireless_screen.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_feature_gate.dart';
import 'package:luci_mobile/widgets/luci_hub_tile.dart';

/// The configuration hub: interfaces, wireless, DHCP, firewall and routing.
///
/// This is a hub rather than a single screen because the things underneath it
/// are genuinely separate tasks. It still leads with live state — a hub made
/// only of links tells you nothing and costs a tap.
class NetworkScreen extends ConsumerStatefulWidget {
  const NetworkScreen({super.key, this.pendingInterface, this.onConsumed});

  /// An interface the dashboard asked us to open directly.
  final String? pendingInterface;

  /// Called once [pendingInterface] has been handled, so the shell can clear
  /// it and a rebuild does not push the screen twice.
  final VoidCallback? onConsumed;

  @override
  ConsumerState<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends ConsumerState<NetworkScreen> {
  bool _deepLinkHandled = false;

  @override
  void initState() {
    super.initState();
    _maybeOpenPendingInterface();
  }

  @override
  void didUpdateWidget(NetworkScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pendingInterface != oldWidget.pendingInterface) {
      _deepLinkHandled = false;
      _maybeOpenPendingInterface();
    }
  }

  /// Opens Interfaces scrolled to the requested card.
  ///
  /// The dashboard used to deep-link straight to the Interfaces *tab*. Now
  /// that Interfaces is pushed from here, the deep link pushes it too — which
  /// is better, because it leaves a back button instead of stranding the user
  /// on a tab they did not choose.
  void _maybeOpenPendingInterface() {
    final name = widget.pendingInterface;
    if (name == null || _deepLinkHandled) return;
    _deepLinkHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onConsumed?.call();
      _openInterfaces(scrollTo: name);
    });
  }

  void _openInterfaces({String? scrollTo}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            InterfacesScreen(scrollToInterface: scrollTo, showBack: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final l10n = context.l10n;
    final wireless = ref.watch(featureProvider(RouterFeature.wirelessScan));

    final interfaces = _interfaceSummary(appState.dashboardData);

    return Scaffold(
      appBar: LuciAppBar(title: l10n.network),
      body: RefreshIndicator(
        onRefresh: () => ref.read(appStateProvider).fetchDashboardData(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (interfaces.isNotEmpty) _OverviewStrip(summary: interfaces),
            LuciSectionHeader(l10n.interfaces),
            LuciHubSection(
              tiles: [
                LuciHubTile(
                  icon: Icons.lan_outlined,
                  title: l10n.interfaces,
                  subtitle: l10n.interfacesHubSubtitle,
                  onTap: _openInterfaces,
                ),
                LuciHubTile(
                  icon: Icons.wifi_outlined,
                  title: l10n.wirelessNetworks,
                  subtitle: l10n.wirelessNetworksHubSubtitle,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WirelessScreen(),
                    ),
                  ),
                ),
                LuciHubTile(
                  icon: Icons.security_outlined,
                  title: l10n.firewall,
                  subtitle: l10n.firewallHubSubtitle,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FirewallScreen(),
                    ),
                  ),
                ),
                LuciHubTile(
                  icon: Icons.extension_outlined,
                  title: l10n.addons,
                  subtitle: l10n.addonsSubtitle,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AddonsScreen(),
                    ),
                  ),
                ),
                LuciHubTile(
                  icon: Icons.wifi_find_outlined,
                  title: l10n.wifiScanner,
                  subtitle: wireless.subtitle(
                    context,
                    l10n.wifiScannerDescription,
                  ),
                  enabled: wireless.available,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WifiScanScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuciSpacing.lg),
          ],
        ),
      ),
    );
  }

  /// A one-line count of what is up, so the hub leads with state.
  List<({String name, bool up})> _interfaceSummary(
    Map<String, dynamic>? dashboardData,
  ) {
    final dump = dashboardData?['interfaceDump'];
    if (dump is! Map) return const [];
    final list = dump['interface'];
    if (list is! List) return const [];
    return [
      for (final iface in list)
        if (iface is Map && iface['interface'] != 'loopback')
          (name: iface['interface'].toString(), up: iface['up'] == true),
    ];
  }
}

/// Live interface state at the top of the hub.
class _OverviewStrip extends StatelessWidget {
  const _OverviewStrip({required this.summary});

  final List<({String name, bool up})> summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuciSpacing.md,
        LuciSpacing.md,
        LuciSpacing.md,
        0,
      ),
      child: Wrap(
        spacing: LuciSpacing.sm,
        runSpacing: LuciSpacing.sm,
        children: [
          for (final iface in summary)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LuciSpacing.md,
                vertical: LuciSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: iface.up
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LuciStatusIndicators.statusDot(context, iface.up),
                  const SizedBox(width: LuciSpacing.sm),
                  Text(
                    iface.name.toUpperCase(),
                    style: LuciTextStyles.detailValue(context),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
