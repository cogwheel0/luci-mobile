import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/api_error_text.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/models/service_status.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_feature_gate.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';

final servicesProvider = FutureProvider<List<ServiceStatus>>((ref) async {
  final session = ref.watch(sessionProvider);
  final api = ref.watch(apiServiceProvider);
  if (session == null || api == null) return const [];
  final map = await api.rcList(
    session.ipAddress,
    session.sysauth,
    session.useHttps,
  );
  final list = map.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  return list;
}, retry: (_, _) => null);

/// Start, stop and enable the router's services.
class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  String? _busyService;

  Future<void> _act(ServiceStatus service, String action) async {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return;

    setState(() => _busyService = service.name);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await api.rcInit(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        name: service.name,
        action: action,
      );
      if (!mounted) return;
      ref.invalidate(servicesProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.serviceActionDone(service.name))),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    } finally {
      if (mounted) setState(() => _busyService = null);
    }
  }

  /// Stopping the service the app is talking through cuts the connection
  /// mid-call, so it asks first.
  static const _selfCritical = {'uhttpd', 'rpcd', 'network', 'firewall'};

  Future<bool> _confirmIfSelfCritical(
    ServiceStatus service,
    String action,
  ) async {
    if (!_selfCritical.contains(service.name)) return true;
    if (action != 'stop' && action != 'disable' && action != 'restart') {
      return true;
    }
    final l10n = context.l10n;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.serviceCriticalTitle),
            content: Text(l10n.serviceCriticalBody(service.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.continueAnyway),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gate = ref.watch(featureProvider(RouterFeature.serviceControl));
    final async = ref.watch(servicesProvider);

    return Scaffold(
      appBar: LuciAppBar(title: l10n.services, showBack: true),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(servicesProvider),
        child: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(LuciSpacing.md),
            child: LuciCardSkeleton(contentLines: 5),
          ),
          error: (error, _) => LuciMessageState(
            message: gate.explain(context) ?? apiErrorText(context, error),
            action: l10n.retry,
            onAction: () => ref.invalidate(servicesProvider),
          ),
          data: (services) => services.isEmpty
              ? LuciMessageState(
                  message: gate.explain(context) ?? l10n.noServices,
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: services.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _ServiceRow(
                    service: services[i],
                    busy: _busyService == services[i].name,
                    enabled: gate.available && _busyService == null,
                    onAction: (action) async {
                      if (await _confirmIfSelfCritical(services[i], action)) {
                        await _act(services[i], action);
                      }
                    },
                  ),
                ),
        ),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.busy,
    required this.enabled,
    required this.onAction,
  });

  final ServiceStatus service;
  final bool busy;
  final bool enabled;
  final Future<void> Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Icon(
              switch (service.running) {
                true => Icons.play_circle,
                false => Icons.stop_circle_outlined,
                // A one-shot script has no daemon to be up or down.
                null => Icons.task_alt,
              },
              color: service.running == true ? scheme.primary : scheme.outline,
            ),
      title: Text(service.name),
      subtitle: Text(
        [
          // Omitted entirely when the router did not report it: saying
          // "Stopped" about a boot script that ran fine is simply untrue.
          ?switch (service.running) {
            true => l10n.serviceRunning,
            false => l10n.serviceStopped,
            null => null,
          },
          service.enabled ? l10n.serviceStartsAtBoot : l10n.serviceNotAtBoot,
        ].join(' · '),
      ),
      trailing: PopupMenuButton<String>(
        enabled: enabled,
        onSelected: onAction,
        itemBuilder: (context) => [
          PopupMenuItem(value: 'start', child: Text(l10n.serviceStart)),
          PopupMenuItem(value: 'restart', child: Text(l10n.serviceRestart)),
          PopupMenuItem(value: 'stop', child: Text(l10n.serviceStop)),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: service.enabled ? 'disable' : 'enable',
            child: Text(
              service.enabled ? l10n.serviceDisable : l10n.serviceEnable,
            ),
          ),
        ],
      ),
    );
  }
}
