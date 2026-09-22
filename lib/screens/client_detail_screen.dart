import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/client_config.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/models/station_info.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/api_service.dart';
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
  String _displayName(ClientDetail? detail) {
    final alias = detail?.alias;
    if (alias != null && alias.isNotEmpty) return alias;
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
    final detailAsync = ref.watch(clientDetailProvider(mac));
    final displayName = _displayName(detailAsync.value);

    return Scaffold(
      appBar: LuciAppBar(title: displayName, showBack: true),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(clientDetailProvider(mac)),
        child: ListView(
          padding: const EdgeInsets.all(LuciSpacing.md),
          children: [
            _IdentityCard(client: client, displayName: displayName),
            if (!_isOwnedBySelectedRouter) _crossRouterBanner(context),
            const SizedBox(height: LuciSpacing.md),
            ...detailAsync.when(
              loading: () => const [
                LuciCardSkeleton(contentLines: 3),
                SizedBox(height: LuciSpacing.md),
                LuciCardSkeleton(contentLines: 4),
              ],
              error: (error, _) => [
                _MessageCard(
                  icon: Icons.error_outline,
                  message: userFacingApiError(error),
                  action: context.l10n.retry,
                  onAction: () => ref.invalidate(clientDetailProvider(mac)),
                ),
              ],
              data: (detail) => _sections(context, detail),
            ),
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

  List<Widget> _sections(BuildContext context, ClientDetail detail) => [
    if (detail.station != null || detail.stationUnavailable)
      _SignalCard(detail: detail),
    if (detail.station != null) _TrafficCard(station: detail.station!),
    _AddressesCard(client: client, detail: detail),
    _reservationCard(context, detail),
    _wakeCard(context, detail),
    _blockCard(context, detail),
    const SizedBox(height: LuciSpacing.xl),
  ];

  // ------------------------------------------------------------ write cards

  Widget _reservationCard(BuildContext context, ClientDetail detail) {
    final availability = ref.watch(
      featureProvider(RouterFeature.dhcpReservations),
    );
    return _GatedCard(
      title: context.l10n.staticLeaseSection,
      icon: Icons.bookmark_outline,
      availability: availability,
      writable: _isOwnedBySelectedRouter && !detail.dhcpUnavailable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.reserveThisAddress),
            subtitle: detail.hasReservation
                ? Text('${context.l10n.reservedAddress}: ${detail.host!.ip}')
                : null,
            value: detail.hasReservation,
            onChanged:
                _canWrite(availability, configReadable: !detail.dhcpUnavailable)
                ? (want) => _toggleReservation(detail, want)
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
  Widget _wakeCard(BuildContext context, ClientDetail detail) {
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
      messenger.showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
    } finally {
      if (mounted) setState(() => _wakeBusy = false);
    }
  }

  Widget _blockCard(BuildContext context, ClientDetail detail) {
    final availability = ref.watch(
      featureProvider(RouterFeature.clientBlocking),
    );
    final noZone = detail.zone == null && detail.blockRule == null;
    return _GatedCard(
      title: context.l10n.accessSection,
      icon: Icons.block_outlined,
      availability: availability,
      writable: _isOwnedBySelectedRouter && !detail.firewallUnavailable,
      // Without a resolvable zone the rule would have to guess `lan`, which
      // is wrong on any guest-VLAN or multi-zone router.
      extraNote: noZone ? context.l10n.noZoneForClient : null,
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(context.l10n.blockClient),
        subtitle: Text(
          context.l10n.blockClientDescription,
          style: LuciTextStyles.cardSubtitle(context),
        ),
        value: detail.isBlocked,
        onChanged:
            _canWrite(
                  availability,
                  configReadable: !detail.firewallUnavailable,
                ) &&
                !noZone
            ? (want) => _toggleBlock(detail, want)
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
        displayName: _displayName(detail),
        existing: rule,
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
  const _IdentityCard({required this.client, required this.displayName});

  final Client client;
  final String displayName;

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
        ],
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.detail});

  final ClientDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.station == null) {
      return _MessageCard(
        icon: Icons.signal_wifi_statusbar_null,
        message: context.l10n.signalUnavailable,
      );
    }
    final s = detail.station!;
    return _SectionCard(
      title: context.l10n.signal,
      icon: Icons.network_wifi,
      rows: [
        if (s.signal != null) (context.l10n.signal, '${s.signal} dBm'),
        if (s.noise != null) (context.l10n.noiseFloor, '${s.noise} dBm'),
        if (s.snr != null) (context.l10n.signalToNoise, '${s.snr} dB'),
        if (s.rxRateKbps != null)
          (context.l10n.downloadRate, _rate(s.rxRateKbps!)),
        if (s.txRateKbps != null)
          (context.l10n.uploadRate, _rate(s.txRateKbps!)),
        if (s.connectedSeconds != null)
          (
            context.l10n.connectedFor,
            Client.formatDuration(s.connectedSeconds!),
          ),
      ],
    );
  }

  static String _rate(int kbps) => kbps >= 1000
      ? '${(kbps / 1000).toStringAsFixed(1)} Mbit/s'
      : '$kbps kbit/s';
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.station});

  final StationInfo station;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: context.l10n.trafficSection,
    icon: Icons.swap_vert,
    rows: [
      if (station.rxBytes != null)
        (context.l10n.downloaded, formatBytes(station.rxBytes!)),
      if (station.txBytes != null)
        (context.l10n.uploaded, formatBytes(station.txBytes!)),
    ],
  );
}

class _AddressesCard extends StatelessWidget {
  const _AddressesCard({required this.client, required this.detail});

  final Client client;
  final ClientDetail detail;

  @override
  Widget build(BuildContext context) {
    final ipv6 = <String>{...?client.ipv6Addresses, ...detail.hintIpv6};
    return _SectionCard(
      title: context.l10n.addressesSection,
      icon: Icons.language,
      copyable: true,
      rows: [
        if (client.ipAddress != 'N/A')
          (context.l10n.ipAddress, client.ipAddress),
        for (final addr in ipv6) (context.l10n.ipv6Address, addr),
        (context.l10n.macAddress, client.macAddress),
        if (client.dnsName != null) (context.l10n.dnsName, client.dnsName!),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.rows,
    this.copyable = false,
  });

  final String title;
  final IconData icon;
  final List<(String, String)> rows;
  final bool copyable;

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
            for (final (label, value) in rows)
              InkWell(
                onTap: copyable
                    ? () => copyToClipboard(context, value, label: label)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: LuciSpacing.xs),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label, style: LuciTextStyles.detailLabel(context)),
                      Flexible(
                        child: Text(
                          value,
                          style: LuciTextStyles.detailValue(context),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
