import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/addon_strings.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/addon_spec.dart';
import 'package:luci_mobile/screens/addon_screen.dart';
import 'package:luci_mobile/screens/traffic_screen.dart';
import 'package:luci_mobile/services/addon_catalog.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_feature_gate.dart';
import 'package:luci_mobile/widgets/luci_hub_tile.dart';

/// The add-on packages this router has, and what to do about the ones it
/// does not.
class AddonsScreen extends ConsumerWidget {
  const AddonsScreen({super.key});

  static const _icons = {
    Addon.sqm: Icons.speed,
    Addon.adblock: Icons.block,
    Addon.upnp: Icons.settings_input_antenna,
    Addon.ddns: Icons.dns_outlined,
    Addon.nlbwmon: Icons.data_usage,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: LuciAppBar(title: l10n.addons, showBack: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: LuciSpacing.sm),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LuciSpacing.md,
              LuciSpacing.sm,
              LuciSpacing.md,
              LuciSpacing.md,
            ),
            child: Text(
              l10n.addonsSubtitle,
              style: LuciTextStyles.cardSubtitle(context),
            ),
          ),
          LuciHubSection(
            tiles: [
              for (final spec in AddonCatalog.all)
                _tile(
                  context,
                  ref,
                  addon: spec.addon,
                  title: l10n.string(spec.titleKey),
                  subtitle: l10n.string(spec.subtitleKey),
                  scheme: scheme,
                  open: () => AddonScreen(spec: spec),
                ),
              // Traffic history is a read-only view, not a form, so it has
              // no spec — but it belongs in the same list.
              _tile(
                context,
                ref,
                addon: Addon.nlbwmon,
                title: l10n.trafficHistory,
                subtitle: l10n.trafficHistorySubtitle,
                scheme: scheme,
                open: () => const TrafficScreen(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  LuciHubTile _tile(
    BuildContext context,
    WidgetRef ref, {
    required Addon addon,
    required String title,
    required String subtitle,
    required ColorScheme scheme,
    required Widget Function() open,
  }) {
    final gate = ref.watch(featureProvider(AddonCatalog.feature(addon)));
    return LuciHubTile(
      icon: gate.available
          ? (_icons[addon] ?? Icons.extension_outlined)
          : Icons.download_outlined,
      iconColor: gate.available ? scheme.primary : scheme.outline,
      title: title,
      // An unavailable add-on says which package to install rather than
      // just vanishing, which would read as the app not supporting it.
      subtitle: gate.explain(context) ?? subtitle,
      enabled: gate.available,
      onTap: gate.available
          ? () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => open()))
          : null,
    );
  }
}
