import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/failure_text.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/models/service_status.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_feature_gate.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

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
      AdaptiveSnackBar.show(
        context,
        message: l10n.serviceActionDone(service.name),
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: apiErrorText(context, e),
        type: AdaptiveSnackBarType.error,
      );
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
    return AdaptiveAlertDialog.confirm(
      context: context,
      title: l10n.serviceCriticalTitle,
      message: l10n.serviceCriticalBody(service.name),
      cancelLabel: l10n.cancel,
      confirmLabel: l10n.continueAnyway,
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gate = ref.watch(featureProvider(RouterFeature.serviceControl));
    final async = ref.watch(servicesProvider);
    Widget row(ServiceStatus service) => _ServiceRow(
      service: service,
      busy: _busyService == service.name,
      enabled: gate.available && _busyService == null,
      onAction: (action) async {
        if (await _confirmIfSelfCritical(service, action)) {
          await _act(service, action);
        }
      },
    );

    // iOS lists the services as one inset group, on the grouped background.
    final grouped = PlatformUiCapabilities.isIOS
        ? CupertinoColors.systemGroupedBackground.resolveFrom(context)
        : null;
    return Scaffold(
      backgroundColor: grouped,
      appBar: LuciAppBar(
        title: l10n.services,
        showBack: true,
        backgroundColor: grouped?.withValues(alpha: 0.94),
      ),
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
              : PlatformUiCapabilities.isIOS
              ? AdaptiveGroupedListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  // The hairlines start at the names, past the icons.
                  separatorIndent: 52,
                  itemCount: services.length,
                  itemBuilder: (context, i) => row(services[i]),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: services.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => row(services[i]),
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

    final leading = busy
        ? const SizedBox(
            width: 24,
            height: 24,
            child: AdaptiveProgressIndicator(strokeWidth: 2.5),
          )
        : Icon(switch (service.running) {
            true => Icons.play_circle,
            false => Icons.stop_circle_outlined,
            // A one-shot script has no daemon to be up or down.
            null => Icons.task_alt,
          }, color: service.running == true ? scheme.primary : scheme.outline);
    final status = [
      // Omitted entirely when the router did not report it: saying
      // "Stopped" about a boot script that ran fine is simply untrue.
      ?switch (service.running) {
        true => l10n.serviceRunning,
        false => l10n.serviceStopped,
        null => null,
      },
      service.enabled ? l10n.serviceStartsAtBoot : l10n.serviceNotAtBoot,
    ].join(' · ');

    if (PlatformUiCapabilities.isIOS) {
      return AdaptiveListRow(
        leading: leading,
        title: service.name,
        subtitle: status,
        trailing: _iosMenu(context),
      );
    }
    return ListTile(
      leading: leading,
      title: Text(service.name),
      subtitle: Text(status),
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

  /// The same actions behind the ellipsis of an iOS row: the system
  /// pull-down menu from iOS 26, an action sheet before.
  Widget _iosMenu(BuildContext context) {
    final l10n = context.l10n;
    final tint = Theme.of(context).colorScheme.primary;
    return AdaptivePopupMenuButton.icon<String>(
      icon: 'ellipsis',
      semanticLabel: l10n.more,
      enabled: enabled,
      tint: tint,
      iconColor: enabled
          ? tint
          : CupertinoColors.tertiaryLabel.resolveFrom(context),
      buttonStyle: PopupButtonStyle.plain,
      // Sections, not a divider: a menu with sections keeps its order when
      // it opens upward, so the boot setting stays last.
      items: [
        AdaptivePopupMenuSection<String>(
          items: [
            AdaptivePopupMenuItem(
              label: l10n.serviceStart,
              value: 'start',
              icon: 'play.fill',
            ),
            AdaptivePopupMenuItem(
              label: l10n.serviceRestart,
              value: 'restart',
              icon: 'arrow.clockwise',
            ),
            AdaptivePopupMenuItem(
              label: l10n.serviceStop,
              value: 'stop',
              icon: 'stop.fill',
            ),
          ],
        ),
        AdaptivePopupMenuSection<String>(
          items: [
            AdaptivePopupMenuItem(
              label: service.enabled ? l10n.serviceDisable : l10n.serviceEnable,
              value: service.enabled ? 'disable' : 'enable',
              icon: 'power',
            ),
          ],
        ),
      ],
      onSelected: (_, item) => onAction(item.value!),
    );
  }
}
