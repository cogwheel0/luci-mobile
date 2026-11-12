import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/screens/diagnostics_screen.dart';
import 'package:luci_mobile/screens/traffic_screen.dart';
import 'package:luci_mobile/screens/event_feed_screen.dart';
import 'package:luci_mobile/screens/log_screen.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_hub_tile.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

/// Read-only visibility into what the router is doing: logs, diagnostics and
/// activity.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // iOS lays the hub out as iOS Settings: inset groups on the grouped
    // background.
    final grouped = PlatformUiCapabilities.isIOS
        ? CupertinoColors.systemGroupedBackground.resolveFrom(context)
        : null;
    return Scaffold(
      backgroundColor: grouped,
      appBar: LuciAppBar(
        title: l10n.insights,
        backgroundColor: grouped?.withValues(alpha: 0.94),
      ),
      body: ListView(
        children: [
          LuciSectionHeader(l10n.insights),
          LuciHubSection(
            tiles: [
              LuciHubTile(
                icon: Icons.history,
                title: l10n.activity,
                subtitle: l10n.activityHubSubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EventFeedScreen(),
                  ),
                ),
              ),
              LuciHubTile(
                icon: Icons.article_outlined,
                title: l10n.systemLog,
                subtitle: l10n.logHubSubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LogScreen()),
                ),
              ),
              LuciHubTile(
                icon: Icons.data_usage,
                title: l10n.trafficHistory,
                subtitle: l10n.trafficHistorySubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TrafficScreen(),
                  ),
                ),
              ),
              LuciHubTile(
                icon: Icons.network_ping,
                title: l10n.diagnostics,
                subtitle: l10n.diagnosticsHubSubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DiagnosticsScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LuciSpacing.lg),
        ],
      ),
    );
  }
}
