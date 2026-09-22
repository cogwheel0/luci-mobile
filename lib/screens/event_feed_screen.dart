import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:luci_mobile/widgets/luci_loading_states.dart';
import 'package:luci_mobile/l10n/app_localizations.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/state/event_feed_notifier.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

/// What has changed on the router while the app was watching.
class EventFeedScreen extends ConsumerWidget {
  const EventFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(eventFeedProvider);

    return Scaffold(
      appBar: LuciAppBar(
        title: l10n.activity,
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.clearActivity,
            onPressed: (async.value?.isEmpty ?? true)
                ? null
                : () => ref.read(eventFeedProvider.notifier).clear(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (events) => events.isEmpty
            ? LuciMessageState(
                scrollable: false,
                icon: Icons.history,
                title: l10n.noActivityYet,
                // Saying plainly that this only records while the app is
                // open stops an empty feed reading as a broken feature.
                message: l10n.activityOnlyWhileOpen,
              )
            : ListView.separated(
                itemCount: events.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                // Newest first: the reason you opened this screen is almost
                // always the most recent thing that happened.
                itemBuilder: (context, i) =>
                    _EventRow(event: events[events.length - 1 - i]),
              ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final RouterEvent event;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final color = switch (event.severity) {
      EventSeverity.problem => scheme.error,
      EventSeverity.warning => scheme.tertiary,
      EventSeverity.info => scheme.primary,
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(_icon(event.kind), color: color, size: 20),
      ),
      title: Text(_title(l10n, event)),
      subtitle: Text(
        DateFormat.yMMMd().add_Hm().format(event.at),
        style: LuciTextStyles.cardSubtitle(context),
      ),
    );
  }

  static IconData _icon(RouterEventKind kind) => switch (kind) {
    RouterEventKind.routerUnreachable => Icons.cloud_off,
    RouterEventKind.routerBack => Icons.cloud_done,
    RouterEventKind.wanDown => Icons.public_off,
    RouterEventKind.wanUp => Icons.public,
    RouterEventKind.clientJoined => Icons.login,
    RouterEventKind.clientLeft => Icons.logout,
    RouterEventKind.rebooted => Icons.restart_alt,
  };

  /// Typed, not `dynamic`: a key that loses its translation has to be a
  /// compile error, not a blank row - the same rule `addon_strings.dart`
  /// writes down and for the same reason. Nothing here is covered by a
  /// widget test.
  static String _title(AppLocalizations l10n, RouterEvent e) =>
      switch (e.kind) {
        RouterEventKind.routerUnreachable => l10n.eventRouterUnreachable,
        RouterEventKind.routerBack => l10n.eventRouterBack,
        RouterEventKind.wanDown => l10n.eventWanDown,
        RouterEventKind.wanUp => l10n.eventWanUp,
        RouterEventKind.clientJoined => l10n.eventClientJoined(
          e.subject ?? '?',
        ),
        RouterEventKind.clientLeft => l10n.eventClientLeft(e.subject ?? '?'),
        RouterEventKind.rebooted => l10n.eventRebooted,
      };
}
