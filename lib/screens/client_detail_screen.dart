import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/failure_text.dart';
import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/client_config.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/models/station_info.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/wol_service.dart';
import 'package:luci_mobile/services/client_config_planner.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/client_detail_notifier.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/utils/format_bytes.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_feature_gate.dart';
import 'package:luci_mobile/widgets/luci_apply_progress.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';

class ClientDetailScreen extends ConsumerStatefulWidget {
  const ClientDetailScreen({super.key, required this.client});

  final Client client;

  @override
  ConsumerState<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends ConsumerState<ClientDetailScreen> {
  bool _busy = false;
  bool _wakeBusy = false;

  Client get client => widget.client;
  String get mac => StationInfo.normalizeMac(client.macAddress);

  /// The name the page shows: the alias if set, else the lease name, else
  /// the MAC. The same name goes on anything written to the router about
  /// this client, so a block rule is recognisable in LuCI.
  String _displayName(String? alias) {
    if (alias != null && alias.isNotEmpty) {
      return alias;
    }

    if (client.hostname.isNotEmpty && client.hostname != 'Unknown') {
      return client.hostname;
    }

    return client.macAddress;
  }

  /// Whether this client belongs to the router currently selected.
  ///
  /// The clients list can aggregate several routers; writing a reservation or
  /// a block rule to whichever router happens to be selected would silently
  /// configure the wrong device.
  bool get _isOwnedBySelectedRouter {
    final owner = client.routerId;
    // An untagged client came from a path that lost provenance (the
    // aggregated wireless-only fallback). Treat it as unknown, not as ours.
    if (owner == null) return false;
    // Fall back to the session's router id: reviewer mode has a live session
    // but no saved router profile.
    final selected =
        ref.read(appStateProvider).selectedRouter?.id ??
        ref.read(sessionProvider)?.routerId;
    return selected != null && owner == selected;
  }

  @override
  Widget build(BuildContext context) {
    final detailState = ref.watch(
      clientDetailProvider(mac).select(
        (async) => (
          hasValue: async.hasValue,
          hasError: async.hasError,
          error: async.error,
        ),
      ),
    );

    final alias = ref.watch(
      clientDetailProvider(mac).select((async) => async.value?.alias),
    );

    final displayName = _displayName(alias);

    Widget content;

    if (!detailState.hasValue && !detailState.hasError) {
      content = Column(
        children: const [
          LuciCardSkeleton(contentLines: 3),
          SizedBox(height: LuciSpacing.md),
          LuciCardSkeleton(contentLines: 4),
        ],
      );
    } else if (detailState.hasError && !detailState.hasValue) {
      content = _MessageCard(
        icon: Icons.error_outline,
        message: apiErrorText(context, detailState.error!),
        action: context.l10n.retry,
        onAction: () => ref.invalidate(clientDetailProvider(mac)),
      );
    } else {
      content = Column(children: _sections(context));
    }

    return Scaffold(
      appBar: LuciAppBar(title: displayName, showBack: true),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(clientDetailProvider(mac));
        },
        child: ListView(
          padding: const EdgeInsets.all(LuciSpacing.md),
          children: [
            _IdentityCard(
              client: client,
              displayName: displayName,
              onRename: _busy
                  ? null
                  : () => _rename(
                      ref.read(clientDetailProvider(mac)).value,
                      displayName,
                    ),
            ),
            if (!_isOwnedBySelectedRouter) _crossRouterBanner(context),
            const SizedBox(height: LuciSpacing.md),
            content,
          ],
        ),
      ),
    );
  }

  Widget _crossRouterBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: LuciSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(LuciSpacing.md),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: LuciCardStyles.standardRadius,
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
            const SizedBox(width: LuciSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (client.routerLabel != null)
                    Text(
                      context.l10n.managedByRouter(client.routerLabel!),
                      style: TextStyle(color: scheme.onSecondaryContainer),
                    ),
                  Text(
                    context.l10n.switchToThisRouter,
                    style: LuciTextStyles.cardSubtitle(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context) => [
    _SignalCard(mac: mac),
    _AddressesCard(client: client, mac: mac),
    _TrafficCard(mac: mac),
    _reservationCard(context),
    _wakeCard(context),
    _blockCard(context),
    const SizedBox(height: LuciSpacing.xl),
  ];

  // ------------------------------------------------------------ write cards

  Widget _reservationCard(BuildContext context) {
    final availability = ref.watch(
      featureProvider(RouterFeature.dhcpReservations),
    );

    final reservationState = ref.watch(
      clientDetailProvider(mac).select(
        (async) => (
          hasReservation: async.value?.hasReservation ?? false,
          reservedIp: async.value?.host?.ip,
          dhcpUnavailable: async.value?.dhcpUnavailable ?? false,
        ),
      ),
    );

    final hasReservation = reservationState.hasReservation;
    final reservedIp = reservationState.reservedIp;
    final dhcpUnavailable = reservationState.dhcpUnavailable;

    return _GatedCard(
      title: context.l10n.staticLeaseSection,
      icon: Icons.bookmark_outline,
      availability: availability,
      writable: _isOwnedBySelectedRouter && !dhcpUnavailable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.reserveThisAddress),
            subtitle: hasReservation && reservedIp != null
                ? Text('${context.l10n.reservedAddress}: $reservedIp')
                : null,
            value: hasReservation,
            onChanged: _canWrite(availability, configReadable: !dhcpUnavailable)
                ? (want) {
                    final detail = ref.read(clientDetailProvider(mac)).value;

                    if (detail != null) {
                      _toggleReservation(detail, want);
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }

  /// Waking a sleeping device.
  ///
  /// It lives here rather than on a screen of its own because the MAC is
  /// already known: a standalone WoL page would make the user type it.
  Widget _wakeCard(BuildContext context) {
    final availability = ref.watch(featureProvider(RouterFeature.wakeOnLan));

    final mac = WolService.normaliseMac(widget.client.macAddress);

    return _GatedCard(
      title: context.l10n.wakeSection,
      icon: Icons.power_settings_new,
      availability: availability,
      writable: _isOwnedBySelectedRouter,
      extraNote: mac == null ? context.l10n.wakeNeedsMac : null,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.l10n.wakeDevice),
        subtitle: Text(
          context.l10n.wakeDeviceDescription,
          style: LuciTextStyles.cardSubtitle(context),
        ),
        trailing: FilledButton.tonal(
          onPressed:
              availability.available &&
                  _isOwnedBySelectedRouter &&
                  mac != null &&
                  !_wakeBusy
              ? () => _wake(mac)
              : null,
          child: Text(context.l10n.wakeAction),
        ),
      ),
    );
  }

  Future<void> _wake(String mac) async {
    final session = ref.read(sessionProvider);
    final wol = ref.read(wolServiceProvider);
    if (session == null || wol == null) return;

    setState(() => _wakeBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final sent = await wol.wake(session, mac);
      if (!mounted) return;
      // Nothing acknowledges a magic packet, so the wording promises only
      // that it was sent — not that anything woke up.
      messenger.showSnackBar(
        SnackBar(content: Text(sent ? l10n.wakeSent : l10n.wakeFailed)),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    } finally {
      if (mounted) setState(() => _wakeBusy = false);
    }
  }

  Widget _blockCard(BuildContext context) {
    final availability = ref.watch(
      featureProvider(RouterFeature.clientBlocking),
    );

    final blockState = ref.watch(
      clientDetailProvider(mac).select(
        (async) => (
          zone: async.value?.zone,
          blockRule: async.value?.blockRule,
          firewallUnavailable: async.value?.firewallUnavailable ?? false,
          isBlocked: async.value?.isBlocked ?? false,
        ),
      ),
    );

    final noZone = blockState.zone == null && blockState.blockRule == null;

    return _GatedCard(
      title: context.l10n.accessSection,
      icon: Icons.block_outlined,
      availability: availability,
      writable: _isOwnedBySelectedRouter && !blockState.firewallUnavailable,
      extraNote: noZone ? context.l10n.noZoneForClient : null,
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(context.l10n.blockClient),
        subtitle: Text(
          context.l10n.blockClientDescription,
          style: LuciTextStyles.cardSubtitle(context),
        ),
        value: blockState.isBlocked,
        onChanged:
            _canWrite(
                  availability,
                  configReadable: !blockState.firewallUnavailable,
                ) &&
                !noZone
            ? (want) {
                final detail = ref.read(clientDetailProvider(mac)).value;

                if (detail != null) {
                  _toggleBlock(detail, want);
                }
              }
            : null,
      ),
    );
  }

  /// Whether a control backed by [configReadable] may write now.
  bool _canWrite(
    FeatureAvailability availability, {
    required bool configReadable,
  }) =>
      availability.available &&
      _isOwnedBySelectedRouter &&
      configReadable &&
      !_busy;

  // ---------------------------------------------------------------- actions

  Future<void> _toggleReservation(ClientDetail detail, bool want) async {
    if (!want) {
      final host = detail.host;
      if (host == null) return;
      await _apply(
        ClientConfigPlanner.planRemoveReservation(
          existing: host,
          keepName: true,
        ),
      );
      return;
    }

    final proposed = await _askForIp(detail);
    if (proposed == null) return;
    await _apply(
      ClientConfigPlanner.planReservation(
        mac: mac,
        ip: proposed,
        existing: detail.host,
      ),
    );
  }

  Future<void> _toggleBlock(ClientDetail detail, bool want) async {
    final rule = detail.blockRule;
    if (!want) {
      if (rule == null) return;
      await _apply(ClientConfigPlanner.planUnblock(existing: rule));
      return;
    }
    // Only a rule that has to be *created* needs a zone; re-enabling one
    // just sets its flag, and refusing there left the switch snapping back
    // with nothing said.
    final zone = detail.zone;
    if (zone == null && rule == null) return;
    await _apply(
      ClientConfigPlanner.planBlock(
        mac: mac,
        zone: zone ?? '',
        displayName: _displayName(detail.alias),
        existing: rule,
      ),
    );
  }

  /// Renames the client: an on-device label, and optionally the DHCP
  /// hostname the router itself hands out.
  ///
  /// The label costs nothing and touches no router config, which is why it
  /// is the default; the hostname is a real change to `dhcp` and goes
  /// through the usual apply.
  Future<void> _rename(ClientDetail? detail, String current) async {
    final result = await showDialog<_RenameResult>(
      context: context,
      builder: (_) => _RenameDialog(
        initialName: detail?.alias ?? '',
        hint: current,
        // Only offered where it can actually be written.
        canSetHostname:
            detail != null &&
            _isOwnedBySelectedRouter &&
            !detail.dhcpUnavailable,
      ),
    );
    if (result == null || !mounted) return;

    final alias = result.name.isEmpty ? null : result.name;
    await ref.read(clientMutationsProvider(mac)).setAlias(alias);
    if (!mounted || !result.alsoSetHostname) return;

    await _apply(
      ClientConfigPlanner.planDhcpName(
        mac: mac,
        name: alias,
        existing: detail?.host,
      ),
    );
  }

  Future<String?> _askForIp(ClientDetail detail) => showDialog<String>(
    context: context,
    builder: (dialogContext) => _ReservationDialog(
      initialText:
          detail.host?.ip ??
          (client.ipAddress == 'N/A' ? '' : client.ipAddress),
      detail: detail,
    ),
  );

  Future<void> _apply(List<UciOperation> ops) async {
    if (ops.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      // The dialog stays up for the whole rollback window, counting down. The
      // router reverts by itself if we cannot confirm in time, and the user
      // should be able to see that coming rather than stare at a dead switch.
      await runApply(
        context,
        work: (progress) => ref
            .read(clientMutationsProvider(mac))
            .applyOperations(ops, onPhase: progress.update),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// --------------------------------------------------------------------- cards

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.client,
    required this.displayName,
    this.onRename,
  });

  final Client client;
  final String displayName;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LuciCardStyles.standardCardWrapper(
      context: context,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            child: Icon(
              client.connectionType == ConnectionType.wired
                  ? Icons.settings_ethernet
                  : Icons.wifi,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: LuciSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: LuciTextStyles.cardTitle(context)),
                Text(
                  client.vendor ?? client.macAddress,
                  style: LuciTextStyles.cardSubtitle(context),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: context.l10n.displayName,
            onPressed: onRename,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.onTap});

  final String label;
  final Widget value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LuciSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: LuciTextStyles.detailLabel(context)),
            Flexible(child: value),
          ],
        ),
      ),
    );
  }
}

class _DetailValue<T> extends ConsumerWidget {
  const _DetailValue({
    required this.mac,
    required this.selector,
    required this.format,
  });

  final String mac;
  final T? Function(ClientDetail?) selector;
  final String Function(T value) format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(
      clientDetailProvider(mac).select((async) => selector(async.value)),
    );

    if (value == null) {
      return const SizedBox.shrink();
    }

    return Text(
      format(value),
      style: LuciTextStyles.detailValue(context),
      textAlign: TextAlign.end,
    );
  }
}

class _ConditionalDetailRow<T> extends ConsumerWidget {
  const _ConditionalDetailRow({
    required this.mac,
    required this.label,
    required this.selector,
    required this.format,
  });

  final String mac;
  final String label;
  final T? Function(ClientDetail?) selector;
  final String Function(T value) format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(
      clientDetailProvider(mac).select((async) => selector(async.value)),
    );

    if (value == null) {
      return const SizedBox.shrink();
    }

    return _DetailRow(
      label: label,
      value: Text(
        format(value),
        style: LuciTextStyles.detailValue(context),
        textAlign: TextAlign.end,
      ),
    );
  }
}

class _SignalCard extends ConsumerWidget {
  const _SignalCard({required this.mac});

  final String mac;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stationExists = ref.watch(
      clientDetailProvider(mac).select((async) => async.value?.station != null),
    );

    final unavailable = ref.watch(
      clientDetailProvider(
        mac,
      ).select((async) => async.value?.stationUnavailable ?? false),
    );

    if (!stationExists) {
      if (unavailable) {
        return _MessageCard(
          icon: Icons.signal_wifi_statusbar_null,
          message: context.l10n.signalUnavailable,
        );
      }

      return const SizedBox.shrink();
    }

    return _SectionCard(
      title: context.l10n.signal,
      icon: Icons.network_wifi,
      rows: [
        _DetailRow(
          label: context.l10n.signal,
          value: _DetailValue<int>(
            mac: mac,
            selector: (detail) => detail?.station?.signal,
            format: (value) => '$value dBm',
          ),
        ),
        _DetailRow(
          label: context.l10n.noiseFloor,
          value: _DetailValue<int>(
            mac: mac,
            selector: (detail) => detail?.station?.noise,
            format: (value) => '$value dBm',
          ),
        ),
        _DetailRow(
          label: context.l10n.signalToNoise,
          value: _DetailValue<int>(
            mac: mac,
            selector: (detail) => detail?.station?.snr,
            format: (value) => '$value dB',
          ),
        ),
        _DetailRow(
          label: context.l10n.downloadRate,
          value: _DetailValue<int>(
            mac: mac,
            selector: (detail) => detail?.station?.rxRateKbps,
            format: _rate,
          ),
        ),
        _DetailRow(
          label: context.l10n.uploadRate,
          value: _DetailValue<int>(
            mac: mac,
            selector: (detail) => detail?.station?.txRateKbps,
            format: _rate,
          ),
        ),
        _DetailRow(
          label: context.l10n.connectedFor,
          value: _DetailValue<int>(
            mac: mac,
            selector: (detail) => detail?.station?.connectedSeconds,
            format: Client.formatDuration,
          ),
        ),
      ],
    );
  }

  static String _rate(int kbps) {
    return kbps >= 1000
        ? '${(kbps / 1000).toStringAsFixed(1)} Mbit/s'
        : '$kbps kbit/s';
  }
}

class _TrafficCard extends ConsumerWidget {
  const _TrafficCard({required this.mac});

  final String mac;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stationExists = ref.watch(
      clientDetailProvider(mac).select((async) => async.value?.station != null),
    );

    if (!stationExists) {
      return const SizedBox.shrink();
    }

    return _SectionCard(
      title: context.l10n.trafficSection,
      icon: Icons.swap_vert,
      rows: [
        _ConditionalDetailRow<int>(
          mac: mac,
          label: context.l10n.downloaded,
          selector: (detail) => detail?.station?.rxBytes,
          format: formatBytes,
        ),
        _ConditionalDetailRow<int>(
          mac: mac,
          label: context.l10n.uploaded,
          selector: (detail) => detail?.station?.txBytes,
          format: formatBytes,
        ),
      ],
    );
  }
}

class _AddressesCard extends ConsumerWidget {
  const _AddressesCard({required this.client, required this.mac});

  final Client client;
  final String mac;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hintIpv6 = ref.watch(
      clientDetailProvider(
        mac,
      ).select((async) => async.value?.hintIpv6 ?? const <String>[]),
    );

    final ipv6 = <String>{...?client.ipv6Addresses, ...hintIpv6};

    return _SectionCard(
      title: context.l10n.addressesSection,
      icon: Icons.language,
      rows: [
        if (client.ipAddress != 'N/A')
          _DetailRow(
            label: context.l10n.ipAddress,
            value: Text(
              client.ipAddress,
              style: LuciTextStyles.detailValue(context),
              textAlign: TextAlign.end,
            ),
            onTap: () => copyToClipboard(
              context,
              client.ipAddress,
              label: context.l10n.ipAddress,
            ),
          ),

        for (final addr in ipv6)
          _DetailRow(
            label: context.l10n.ipv6Address,
            value: Text(
              addr,
              style: LuciTextStyles.detailValue(context),
              textAlign: TextAlign.end,
            ),
            onTap: () =>
                copyToClipboard(context, addr, label: context.l10n.ipv6Address),
          ),

        _DetailRow(
          label: context.l10n.macAddress,
          value: Text(
            client.macAddress,
            style: LuciTextStyles.detailValue(context),
            textAlign: TextAlign.end,
          ),
          onTap: () => copyToClipboard(
            context,
            client.macAddress,
            label: context.l10n.macAddress,
          ),
        ),

        if (client.dnsName != null)
          _DetailRow(
            label: context.l10n.dnsName,
            value: Text(
              client.dnsName!,
              style: LuciTextStyles.detailValue(context),
              textAlign: TextAlign.end,
            ),
            onTap: () => copyToClipboard(
              context,
              client.dnsName!,
              label: context.l10n.dnsName,
            ),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: LuciSpacing.md),
      child: LuciCardStyles.standardCardWrapper(
        context: context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: LuciSpacing.sm),
                Text(title, style: LuciTextStyles.cardTitle(context)),
              ],
            ),
            const SizedBox(height: LuciSpacing.sm),
            ...rows,
          ],
        ),
      ),
    );
  }
}

/// A card whose content is disabled, with a reason, when the router or the
/// account cannot support it.
///
/// Unavailable controls stay visible and explain themselves rather than
/// silently disappearing: a page that differs between routers with no
/// explanation reads as a bug.
class _GatedCard extends StatelessWidget {
  const _GatedCard({
    required this.title,
    required this.icon,
    required this.availability,
    required this.writable,
    required this.child,
    this.extraNote,
  });

  final String title;
  final IconData icon;
  final FeatureAvailability availability;
  final bool writable;
  final Widget child;
  final String? extraNote;

  @override
  Widget build(BuildContext context) {
    final note = _note(context) ?? extraNote;
    return Padding(
      padding: const EdgeInsets.only(bottom: LuciSpacing.md),
      child: LuciCardStyles.standardCardWrapper(
        context: context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: LuciSpacing.sm),
                Text(title, style: LuciTextStyles.cardTitle(context)),
              ],
            ),
            Opacity(
              opacity: availability.available && writable ? 1 : 0.5,
              child: child,
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: LuciSpacing.xs),
                child: Text(note, style: LuciTextStyles.cardSubtitle(context)),
              ),
          ],
        ),
      ),
    );
  }

  String? _note(BuildContext context) {
    if (!writable) return null; // the cross-router banner already explains
    return availability.explain(context);
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: LuciSpacing.md),
    child: LuciCardStyles.standardCardWrapper(
      context: context,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: LuciSpacing.sm),
          Expanded(
            child: Text(message, style: LuciTextStyles.cardSubtitle(context)),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    ),
  );
}

/// Asks for a reservation address, validating it against the subnet, the DHCP
/// pool and the other reservations before letting the user commit.
class _ReservationDialog extends StatefulWidget {
  const _ReservationDialog({required this.initialText, required this.detail});

  final String initialText;
  final ClientDetail detail;

  @override
  State<_ReservationDialog> createState() => _ReservationDialogState();
}

class _ReservationDialogState extends State<_ReservationDialog> {
  // Owned here, so it outlives the route's exit animation and is disposed
  // with the dialog rather than the moment the future resolves.
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  IpCheckResult _check = IpCheckResult.ok;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validate(String value) {
    setState(() {
      _check = ClientConfigPlanner.checkReservationIp(
        value,
        subnets: widget.detail.subnets,
        alreadyReserved: widget.detail.reservedIps,
        pools: widget.detail.pools,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _validate(_controller.text);
  }

  String? _message(BuildContext context) => switch (_check) {
    IpCheckResult.ok => null,
    IpCheckResult.malformed => context.l10n.invalidIpAddress,
    IpCheckResult.outsideSubnet => context.l10n.addressOutsideSubnet,
    IpCheckResult.duplicate => context.l10n.addressAlreadyReserved,
    IpCheckResult.insidePool => context.l10n.addressInsideDhcpPool,
    IpCheckResult.notAssignable => context.l10n.addressNotAssignable,
  };

  @override
  Widget build(BuildContext context) {
    final message = _message(context);
    return AlertDialog(
      title: Text(context.l10n.reserveThisAddress),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: context.l10n.ipAddress,
          errorText: _check.isBlocking ? message : null,
          // An address inside the pool still works, so it is a warning rather
          // than something to refuse.
          helperText: _check.isBlocking ? null : message,
        ),
        onChanged: _validate,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _check.isBlocking
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(context.l10n.saveAction),
        ),
      ],
    );
  }
}

/// What the rename dialog came back with.
class _RenameResult {
  const _RenameResult({required this.name, required this.alsoSetHostname});
  final String name;
  final bool alsoSetHostname;
}

/// Asks for a name for this client.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
    required this.initialName,
    required this.hint,
    required this.canSetHostname,
  });

  final String initialName;

  /// What the client is called now, so an empty field is not a mystery.
  final String hint;
  final bool canSetHostname;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  bool _alsoHostname = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// dnsmasq will not start on a name it cannot use as a DNS label, and the
  /// router stays reachable while it is down - so the rollback timer never
  /// catches it. Only enforced when the name is going to the router.
  bool get _valid {
    final name = _name.text.trim();
    if (!_alsoHostname) return true;
    return name.isEmpty || isValidHostname(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.clientDetails),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.displayName,
              hintText: widget.hint,
              helperText: _alsoHostname
                  ? l10n.dhcpHostnameHint
                  : l10n.displayNameHint,
              errorText: _valid ? null : l10n.invalidHostname,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.canSetHostname)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.setDhcpHostname),
              value: _alsoHostname,
              onChanged: (v) => setState(() => _alsoHostname = v ?? false),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.of(context).pop(
                  _RenameResult(
                    name: _name.text.trim(),
                    alsoSetHostname: _alsoHostname,
                  ),
                )
              : null,
          child: Text(l10n.saveAction),
        ),
      ],
    );
  }
}
