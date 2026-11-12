import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/failure_text.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/services/traffic_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_feature_gate.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:luci_mobile/utils/format_bytes.dart';

final trafficServiceProvider = Provider<TrafficService?>((ref) {
  final api = ref.watch(apiServiceProvider);
  return api == null ? null : TrafficService(api);
});

final trafficPeriodsProvider = FutureProvider<List<String>>((ref) async {
  final session = ref.watch(sessionProvider);
  final service = ref.watch(trafficServiceProvider);
  if (session == null || service == null) return const [];
  return service.periods(session);
}, retry: (_, _) => null);

final trafficRecordsProvider = FutureProvider.family<List<TrafficRow>, String>((
  ref,
  period,
) async {
  final session = ref.watch(sessionProvider);
  final service = ref.watch(trafficServiceProvider);
  if (session == null || service == null) return const [];
  return service.records(session, period);
}, retry: (_, _) => null);

/// Which devices used the connection, from nlbwmon's accounting database.
class TrafficScreen extends ConsumerStatefulWidget {
  const TrafficScreen({super.key});

  @override
  ConsumerState<TrafficScreen> createState() => _TrafficScreenState();
}

class _TrafficScreenState extends ConsumerState<TrafficScreen> {
  String? _period;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gate = ref.watch(featureProvider(RouterFeature.trafficAccounting));
    final periods = ref.watch(trafficPeriodsProvider);

    // iOS lists the devices as one inset group, on the grouped background.
    final grouped = PlatformUiCapabilities.isIOS
        ? CupertinoColors.systemGroupedBackground.resolveFrom(context)
        : null;
    return Scaffold(
      backgroundColor: grouped,
      appBar: LuciAppBar(
        title: l10n.trafficHistory,
        showBack: true,
        backgroundColor: grouped?.withValues(alpha: 0.94),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(trafficPeriodsProvider);
          final p = _period;
          if (p != null) ref.invalidate(trafficRecordsProvider(p));
        },
        child: periods.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(LuciSpacing.md),
            child: LuciCardSkeleton(contentLines: 5),
          ),
          error: (error, _) => LuciMessageState(
            message: gate.explain(context) ?? apiErrorText(context, error),
            action: l10n.retry,
            onAction: () => ref.invalidate(trafficPeriodsProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return LuciMessageState(
                message: gate.explain(context) ?? l10n.trafficNoPeriods,
              );
            }
            final period = list.contains(_period) ? _period! : list.first;
            return _Records(
              periods: list,
              period: period,
              onPeriod: (p) => setState(() => _period = p),
            );
          },
        ),
      ),
    );
  }
}

class _Records extends ConsumerWidget {
  const _Records({
    required this.periods,
    required this.period,
    required this.onPeriod,
  });

  final List<String> periods;
  final String period;
  final ValueChanged<String> onPeriod;

  /// The period as an iOS picker row, a group of its own above the list:
  /// the system pull-down menu from iOS 26, an action sheet before.
  Widget _iosPeriodPicker(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(adaptiveFormCornerRadius),
    ),
    child: AdaptiveFormPicker<String>(
      label: context.l10n.trafficPeriod,
      value: period,
      choices: [for (final p in periods) AdaptiveFormChoice(p, p)],
      onChanged: (p) {
        if (p != null) onPeriod(p);
      },
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(trafficRecordsProvider(period));

    return Column(
      children: [
        if (periods.length > 1)
          Padding(
            padding: const EdgeInsets.all(LuciSpacing.md),
            child: PlatformUiCapabilities.isIOS
                ? _iosPeriodPicker(context)
                : DropdownButtonFormField<String>(
                    initialValue: period,
                    decoration: InputDecoration(
                      labelText: l10n.trafficPeriod,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final p in periods)
                        DropdownMenuItem(value: p, child: Text(p)),
                    ],
                    onChanged: (p) {
                      if (p != null) onPeriod(p);
                    },
                  ),
          ),
        Expanded(
          child: async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(LuciSpacing.md),
              child: LuciCardSkeleton(contentLines: 5),
            ),
            error: (error, _) => LuciMessageState(
              message: apiErrorText(context, error),
              action: l10n.retry,
              onAction: () => ref.invalidate(trafficRecordsProvider(period)),
            ),
            data: (rows) => rows.isEmpty
                ? LuciMessageState(message: l10n.trafficNoRecords)
                : _RowList(rows: rows),
          ),
        ),
      ],
    );
  }
}

class _RowList extends StatelessWidget {
  const _RowList({required this.rows});

  final List<TrafficRow> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Relative bars make "who used the most" readable at a glance in a way
    // a column of byte counts does not.
    final biggest = rows.first.totalBytes;
    String usage(TrafficRow row) =>
        '${l10n.download} ${formatBytes(row.rxBytes)} · '
        '${l10n.upload} ${formatBytes(row.txBytes)}';
    double share(TrafficRow row) => biggest == 0 ? 0 : row.totalBytes / biggest;

    if (PlatformUiCapabilities.isIOS) {
      return AdaptiveGroupedListView(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final row = rows[i];
          return AdaptiveListRow(
            title: row.ip.isEmpty ? row.mac : row.ip,
            subtitle: usage(row),
            below: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: AdaptiveProgressIndicator.linear(
                value: share(row),
                minHeight: 4,
                backgroundColor: CupertinoColors.systemFill.resolveFrom(
                  context,
                ),
              ),
            ),
            trailing: Text(
              formatBytes(row.totalBytes),
              style: TextStyle(
                fontSize: 17,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          );
        },
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final row = rows[i];
        final scheme = Theme.of(context).colorScheme;
        return ListTile(
          title: Text(row.ip.isEmpty ? row.mac : row.ip),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(usage(row), style: LuciTextStyles.cardSubtitle(context)),
              const SizedBox(height: LuciSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: share(row),
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
          trailing: Text(
            formatBytes(row.totalBytes),
            style: LuciTextStyles.cardTitle(context),
          ),
        );
      },
    );
  }
}
