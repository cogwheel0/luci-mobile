import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/api_error_text.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/services/traffic_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_feature_gate.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';
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

    return Scaffold(
      appBar: LuciAppBar(title: l10n.trafficHistory, showBack: true),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(trafficRecordsProvider(period));

    return Column(
      children: [
        if (periods.length > 1)
          Padding(
            padding: const EdgeInsets.all(LuciSpacing.md),
            child: DropdownButtonFormField<String>(
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
              Text(
                '${l10n.download} ${formatBytes(row.rxBytes)} · '
                '${l10n.upload} ${formatBytes(row.txBytes)}',
                style: LuciTextStyles.cardSubtitle(context),
              ),
              const SizedBox(height: LuciSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: biggest == 0 ? 0 : row.totalBytes / biggest,
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
