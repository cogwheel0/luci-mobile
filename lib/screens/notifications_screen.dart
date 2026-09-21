import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/services/background_monitor.dart';
import 'package:luci_mobile/state/notifications_notifier.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

/// Whether — and what — the app may notify about while it is closed.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);

    return Scaffold(
      appBar: LuciAppBar(title: l10n.notifications, showBack: true),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(LuciSpacing.md),
          children: [
            LuciCardStyles.standardCardWrapper(
              context: context,
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                title: Text(l10n.notifyInBackground),
                subtitle: Text(l10n.notifyInBackgroundHelp),
                value: settings.enabled,
                onChanged: notifier.setEnabled,
              ),
            ),
            if (settings.permissionDenied || settings.schedulingFailed) ...[
              const SizedBox(height: LuciSpacing.md),
              LuciCardStyles.standardCardWrapper(
                context: context,
                padding: const EdgeInsets.all(LuciSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: LuciSpacing.md),
                    Expanded(
                      child: Text(
                        settings.permissionDenied
                            ? l10n.notifyPermissionDenied
                            : l10n.notifySchedulingFailed,
                        style: LuciTextStyles.cardSubtitle(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: LuciSpacing.lg),
            LuciSectionHeader(l10n.notifyAbout),
            LuciCardStyles.standardCardWrapper(
              context: context,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final kind in notifiableKinds)
                    SwitchListTile(
                      dense: true,
                      title: Text(_label(l10n, kind)),
                      value: settings.kinds.contains(kind),
                      onChanged: settings.enabled
                          ? (on) => notifier.setKind(kind, on)
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: LuciSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LuciSpacing.sm),
              child: Text(
                // Both limits are the platform's, not choices — saying so
                // stops "it didn't tell me instantly" reading as a bug.
                l10n.notifyIntervalNote,
                style: LuciTextStyles.cardSubtitle(context),
              ),
            ),
            const SizedBox(height: LuciSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LuciSpacing.sm),
              child: Text(
                l10n.notifyAwayNote,
                style: LuciTextStyles.cardSubtitle(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _label(dynamic l10n, RouterEventKind kind) => switch (kind) {
    RouterEventKind.wanDown => l10n.notifyWanDown as String,
    RouterEventKind.wanUp => l10n.notifyWanUp as String,
    RouterEventKind.rebooted => l10n.notifyRebooted as String,
    RouterEventKind.clientJoined => l10n.notifyClientJoined as String,
    _ => kind.name,
  };
}
