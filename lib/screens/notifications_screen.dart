import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/app_localizations.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/services/background_monitor.dart';
import 'package:luci_mobile/state/notifications_notifier.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

/// Whether — and what — the app may notify about while it is closed.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);

    // iOS lays the settings out as iOS Settings: grouped rows on the
    // grouped background.
    final grouped = PlatformUiCapabilities.isIOS
        ? CupertinoColors.systemGroupedBackground.resolveFrom(context)
        : null;
    return Scaffold(
      backgroundColor: grouped,
      appBar: LuciAppBar(
        title: l10n.notifications,
        showBack: true,
        backgroundColor: grouped?.withValues(alpha: 0.94),
      ),
      body: async.when(
        loading: () => const Center(child: AdaptiveProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (settings) => PlatformUiCapabilities.isIOS
            ? _iosSettings(context, settings, notifier)
            : ListView(
                padding: const EdgeInsets.all(LuciSpacing.md),
                children: [
                  LuciCardStyles.standardCardWrapper(
                    context: context,
                    padding: EdgeInsets.zero,
                    child: AdaptiveSwitchListTile(
                      title: Text(l10n.notifyInBackground),
                      subtitle: Text(l10n.notifyInBackgroundHelp),
                      value: settings.enabled,
                      onChanged: notifier.setEnabled,
                    ),
                  ),
                  if (settings.permissionDenied ||
                      settings.schedulingFailed ||
                      settings.needsRouter ||
                      settings.saveFailed) ...[
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
                                  : settings.needsRouter
                                  ? l10n.notifyNeedsRouter
                                  : settings.saveFailed
                                  ? l10n.notifySaveFailed
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
                          AdaptiveSwitchListTile(
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: LuciSpacing.sm,
                    ),
                    child: Text(
                      // Both limits are the platform's, not choices — saying so
                      // stops "it didn't tell me instantly" reading as a bug.
                      l10n.notifyIntervalNote,
                      style: LuciTextStyles.cardSubtitle(context),
                    ),
                  ),
                  const SizedBox(height: LuciSpacing.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LuciSpacing.sm,
                    ),
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

  /// What stops notifications, if anything.
  static String? _problem(AppLocalizations l10n, NotificationSettings s) =>
      s.permissionDenied
      ? l10n.notifyPermissionDenied
      : s.needsRouter
      ? l10n.notifyNeedsRouter
      : s.saveFailed
      ? l10n.notifySaveFailed
      : s.schedulingFailed
      ? l10n.notifySchedulingFailed
      : null;

  /// The settings as iOS Settings lays out a notification page: the switch
  /// with its help and any problem under it, then a switch per event, the
  /// platform's limits under them.
  Widget _iosSettings(
    BuildContext context,
    NotificationSettings settings,
    NotificationSettingsNotifier notifier,
  ) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(LuciSpacing.md),
      children: [
        AdaptiveFormSection(
          error: _problem(l10n, settings),
          children: [
            AdaptiveFormSwitch(
              label: l10n.notifyInBackground,
              description: l10n.notifyInBackgroundHelp,
              value: settings.enabled,
              onChanged: notifier.setEnabled,
            ),
          ],
        ),
        AdaptiveFormSection(
          header: l10n.notifyAbout,
          // Both limits are the platform's, not choices — saying so stops
          // "it didn't tell me instantly" reading as a bug.
          footer: '${l10n.notifyIntervalNote}\n\n${l10n.notifyAwayNote}',
          children: [
            for (final kind in notifiableKinds)
              AdaptiveFormSwitch(
                label: _label(l10n, kind),
                value: settings.kinds.contains(kind),
                onChanged: settings.enabled
                    ? (on) => notifier.setKind(kind, on)
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  static String _label(AppLocalizations l10n, RouterEventKind kind) =>
      switch (kind) {
        RouterEventKind.wanDown => l10n.notifyWanDown,
        RouterEventKind.wanUp => l10n.notifyWanUp,
        RouterEventKind.rebooted => l10n.notifyRebooted,
        RouterEventKind.clientJoined => l10n.notifyClientJoined,
        _ => kind.name,
      };
}
