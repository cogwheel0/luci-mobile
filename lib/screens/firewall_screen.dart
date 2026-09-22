import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/failure_text.dart';
import 'package:luci_mobile/utils/ipv4.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/firewall_config.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/firewall_planner.dart';
import 'package:luci_mobile/state/firewall_notifier.dart';
import 'package:luci_mobile/widgets/luci_apply_progress.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';

/// Port forwards, traffic rules, zones and static routes.
///
/// One screen with tabs rather than four hub entries: these are four views of
/// the same question — what is allowed in and out — and jumping between them
/// while diagnosing something is the normal case.
class FirewallScreen extends ConsumerStatefulWidget {
  const FirewallScreen({super.key});

  @override
  ConsumerState<FirewallScreen> createState() => _FirewallScreenState();
}

class _FirewallScreenState extends ConsumerState<FirewallScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(firewallProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          // Match LuciAppBar's chrome: a raw AppBar picks a different surface
          // and leaves the status bar reading against the wrong colour.
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 2,
          scrolledUnderElevation: 2,
          title: Text(l10n.firewall),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l10n.portForwards),
              Tab(text: l10n.trafficRules),
              Tab(text: l10n.zones),
              Tab(text: l10n.staticRoutes),
            ],
          ),
        ),
        body: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(LuciSpacing.md),
            child: LuciCardSkeleton(contentLines: 4),
          ),
          error: (error, _) => LuciMessageState(
            scrollable: false,
            icon: Icons.error_outline,
            message: apiErrorText(context, error),
            action: l10n.retry,
            onAction: () => ref.invalidate(firewallProvider),
          ),
          data: (state) => TabBarView(
            children: [
              _ForwardsTab(
                state: state,
                busy: _busy,
                onToggle: (f, on) => _apply(
                  FirewallPlanner.planSetForwardEnabled(
                    forward: f,
                    enabled: on,
                  ),
                ),
                onEdit: (f) => _editForward(state, f),
                onAdd: () => _editForward(state, null),
              ),
              _RulesTab(
                rules: state.rules,
                busy: _busy,
                onToggle: (r, on) => _apply(
                  FirewallPlanner.planSetRuleEnabled(rule: r, enabled: on),
                ),
                onRemove: (r) => _apply(FirewallPlanner.planRemoveRule(r)),
              ),
              _ZonesTab(zones: state.zones),
              _RoutesTab(
                routes: state.routes,
                busy: _busy,
                onRemove: (r) => _apply(FirewallPlanner.planDeleteRoute(r)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editForward(FirewallState state, PortForward? existing) async {
    if (_busy) return;
    // Only a new forward needs a name; an edit keeps its section. Busy for
    // the read, so a second tap cannot open a second sheet holding the same
    // snapshot and name both forwards the same thing.
    Set<String> taken = const {};
    if (existing == null) {
      setState(() => _busy = true);
      try {
        taken = await ref
            .read(firewallMutationsProvider)
            .takenSectionNames(state);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (!mounted) return;
    final ops = await showModalBottomSheet<List<UciOperation>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _ForwardSheet(state: state, existing: existing, taken: taken),
    );
    if (ops != null) await _apply(ops);
  }

  Future<void> _apply(List<UciOperation> ops) async {
    if (ops.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await runApply(
        context,
        work: (progress) => ref
            .read(firewallMutationsProvider)
            .apply(ops, onPhase: progress.update),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ForwardsTab extends StatelessWidget {
  const _ForwardsTab({
    required this.state,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onAdd,
  });

  final FirewallState state;
  final bool busy;
  final void Function(PortForward, bool) onToggle;
  final void Function(PortForward) onEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: state.forwards.isEmpty
          ? LuciMessageState(
              scrollable: false,
              icon: Icons.swap_horiz,
              message: l10n.noPortForwards,
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: state.forwards.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final f = state.forwards[i];
                return ListTile(
                  onTap: busy ? null : () => onEdit(f),
                  leading: Icon(
                    Icons.arrow_forward,
                    color: f.enabled
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  title: Text(f.name ?? '${f.sourceZone}:${f.sourcePort}'),
                  // The whole point of a forward is the mapping, so show it
                  // rather than making the user open the row to find out.
                  subtitle: Text(
                    '${f.protocol.toUpperCase()}  '
                    '${f.sourceZone}:${f.sourcePort ?? "?"}'
                    '  →  ${f.destIp ?? "?"}:${f.effectiveDestPort}',
                  ),
                  trailing: Switch.adaptive(
                    value: f.enabled,
                    onChanged: busy ? null : (v) => onToggle(f, v),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : onAdd,
        icon: const Icon(Icons.add),
        label: Text(l10n.addPortForward),
      ),
    );
  }
}

class _RulesTab extends StatelessWidget {
  const _RulesTab({
    required this.rules,
    required this.busy,
    required this.onToggle,
    required this.onRemove,
  });

  final List<TrafficRule> rules;
  final bool busy;
  final void Function(TrafficRule, bool) onToggle;
  final void Function(TrafficRule) onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (rules.isEmpty) {
      return LuciMessageState(
        scrollable: false,
        icon: Icons.rule,
        message: l10n.noTrafficRules,
      );
    }
    return ListView.separated(
      itemCount: rules.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = rules[i];
        final scheme = Theme.of(context).colorScheme;
        final blocking = r.target == 'REJECT' || r.target == 'DROP';
        return ListTile(
          leading: Icon(
            blocking ? Icons.block : Icons.check_circle_outline,
            color: blocking ? scheme.error : scheme.primary,
          ),
          title: Text(r.name ?? r.section),
          subtitle: Text(
            [
              r.target,
              if (r.sourceMac != null) r.sourceMac!,
              if (r.protocol != null) r.protocol!.toUpperCase(),
              if (r.destPort != null) ':${r.destPort}',
            ].join('  '),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch.adaptive(
                value: r.enabled,
                onChanged: busy ? null : (v) => onToggle(r, v),
              ),
              IconButton(
                // A rule the user wrote is disabled rather than deleted, so
                // the icon says which will happen.
                icon: Icon(r.ownedByApp ? Icons.delete_outline : Icons.pause),
                tooltip: r.ownedByApp ? l10n.remove : l10n.disableRule,
                onPressed: busy ? null : () => onRemove(r),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ZonesTab extends StatelessWidget {
  const _ZonesTab({required this.zones});

  final List<FirewallZone> zones;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (zones.isEmpty) {
      return LuciMessageState(
        scrollable: false,
        icon: Icons.security,
        message: l10n.noZones,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(LuciSpacing.md),
      children: [
        for (final z in zones)
          Padding(
            padding: const EdgeInsets.only(bottom: LuciSpacing.md),
            child: LuciCardStyles.standardCardWrapper(
              context: context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        z.name.toUpperCase(),
                        style: LuciTextStyles.cardTitle(context),
                      ),
                      if (z.masq) ...[
                        const SizedBox(width: LuciSpacing.sm),
                        Chip(
                          label: const Text('NAT'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: LuciSpacing.sm),
                  _policy(context, l10n.zoneInput, z.input),
                  _policy(context, l10n.zoneOutput, z.output),
                  _policy(context, l10n.zoneForward, z.forward),
                  if (z.networks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: LuciSpacing.sm),
                      child: Text(
                        z.networks.join(', '),
                        style: LuciTextStyles.cardSubtitle(context),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _policy(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    final permissive = value.toUpperCase() == 'ACCEPT';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: LuciTextStyles.detailLabel(context)),
          Text(
            value,
            style: LuciTextStyles.detailValue(
              context,
            ).copyWith(color: permissive ? scheme.primary : scheme.error),
          ),
        ],
      ),
    );
  }
}

class _RoutesTab extends StatelessWidget {
  const _RoutesTab({
    required this.routes,
    required this.busy,
    required this.onRemove,
  });

  final List<StaticRoute> routes;
  final bool busy;
  final void Function(StaticRoute) onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (routes.isEmpty) {
      return LuciMessageState(
        scrollable: false,
        icon: Icons.alt_route,
        message: l10n.noStaticRoutes,
      );
    }
    return ListView.separated(
      itemCount: routes.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = routes[i];
        return ListTile(
          leading: const Icon(Icons.alt_route),
          title: Text('${r.target}${r.netmask == null ? '' : '/${r.netmask}'}'),
          subtitle: Text(
            [
              if (r.gateway != null) 'via ${r.gateway}',
              r.interface,
              if (r.metric != null) 'metric ${r.metric}',
            ].join('  '),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.remove,
            onPressed: busy ? null : () => onRemove(r),
          ),
        );
      },
    );
  }
}

/// Create or edit a port forward.
class _ForwardSheet extends StatefulWidget {
  const _ForwardSheet({
    required this.state,
    this.existing,
    this.taken = const {},
  });

  final FirewallState state;
  final PortForward? existing;

  /// Section names a new forward must not take.
  final Set<String> taken;

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _srcPort = TextEditingController(
    text: widget.existing?.sourcePort ?? '',
  );
  late final _destIp = TextEditingController(
    text: widget.existing?.destIp ?? '',
  );
  late final _destPort = TextEditingController(
    text: widget.existing?.destPort ?? '',
  );
  late String _protocol = widget.existing?.protocol ?? 'tcp';

  static String _protoLabel(String proto) => switch (proto) {
    'tcp' => 'TCP',
    'udp' => 'UDP',
    'tcp udp' => 'TCP + UDP',
    _ => proto.toUpperCase(),
  };

  /// The protocols to offer: the usual three, plus whatever this forward is
  /// set to now. A redirect written in LuCI can say `all`, `esp` or a
  /// spelling from an older firewall, and a dropdown handed a value it does
  /// not list asserts in debug and renders blank in release.
  List<String> get _protocols =>
      const ['tcp', 'udp', 'tcp udp'].contains(_protocol)
      ? const ['tcp', 'udp', 'tcp udp']
      : [_protocol, 'tcp', 'udp', 'tcp udp'];
  late String _srcZone =
      widget.existing?.sourceZone ?? widget.state.wanZone ?? 'wan';

  /// Where the traffic is sent. Defaulting to `lan` and never asking meant
  /// that on a router whose internal zone is named anything else the rule
  /// was written against a zone fw4 does not know: applied, confirmed,
  /// reported as done, and silently dropped.
  late String _destZone = widget.existing?.destZone ?? widget.state.lanZone;

  @override
  void dispose() {
    _name.dispose();
    _srcPort.dispose();
    _destIp.dispose();
    _destPort.dispose();
    super.dispose();
  }

  String? get _srcPortError {
    final v = _srcPort.text.trim();
    if (v.isEmpty) return null;
    if (!FirewallPlanner.isValidPort(v)) return context.l10n.invalidPort;
    if (FirewallPlanner.portAlreadyForwarded(
      widget.state.forwards,
      v,
      _protocol,
      exceptSection: widget.existing?.section,
    )) {
      return context.l10n.portAlreadyForwarded;
    }
    return null;
  }

  String? get _destIpError {
    final v = _destIp.text.trim();
    if (v.isEmpty) return null;
    return isValidIpv4(v) ? null : context.l10n.invalidIpAddress;
  }

  String? get _destPortError {
    final v = _destPort.text.trim();
    if (v.isEmpty) return null;
    return FirewallPlanner.isValidPort(v) ? null : context.l10n.invalidPort;
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      FirewallPlanner.isValidPort(_srcPort.text.trim()) &&
      isValidIpv4(_destIp.text.trim()) &&
      FirewallPlanner.isValidPort(_destPort.text.trim()) &&
      _srcPortError == null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        LuciSpacing.lg,
        0,
        LuciSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + LuciSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null
                  ? l10n.addPortForward
                  : l10n.editPortForward,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: LuciSpacing.lg),

            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              decoration: InputDecoration(labelText: l10n.forwardName),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: LuciSpacing.md),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: widget.state.zoneNames.contains(_srcZone)
                        ? _srcZone
                        : null,
                    decoration: InputDecoration(labelText: l10n.sourceZone),
                    items: [
                      for (final z in widget.state.zoneNames)
                        DropdownMenuItem(value: z, child: Text(z)),
                    ],
                    onChanged: (v) => setState(() => _srcZone = v ?? _srcZone),
                  ),
                ),
                const SizedBox(width: LuciSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _protocol,
                    decoration: InputDecoration(labelText: l10n.protocol),
                    items: [
                      for (final p in _protocols)
                        DropdownMenuItem(value: p, child: Text(_protoLabel(p))),
                    ],
                    onChanged: (v) =>
                        setState(() => _protocol = v ?? _protocol),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuciSpacing.md),

            TextField(
              controller: _srcPort,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.externalPort,
                errorText: _srcPortError,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: LuciSpacing.md),

            DropdownButtonFormField<String>(
              initialValue: widget.state.zoneNames.contains(_destZone)
                  ? _destZone
                  : null,
              decoration: InputDecoration(labelText: l10n.destinationZone),
              items: [
                for (final z in widget.state.zoneNames)
                  DropdownMenuItem(value: z, child: Text(z)),
              ],
              onChanged: (v) => setState(() => _destZone = v ?? _destZone),
            ),
            const SizedBox(height: LuciSpacing.md),
            TextField(
              controller: _destIp,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.internalAddress,
                errorText: _destIpError,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: LuciSpacing.md),

            TextField(
              controller: _destPort,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.internalPort,
                errorText: _destPortError,
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: LuciSpacing.lg),
            Row(
              children: [
                if (widget.existing != null)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      FirewallPlanner.planDeletePortForward(widget.existing!),
                    ),
                    child: Text(
                      l10n.remove,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: LuciSpacing.sm),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  child: Text(l10n.saveAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final ops = widget.existing == null
        ? FirewallPlanner.planCreatePortForward(
            name: _name.text.trim(),
            sourceZone: _srcZone,
            sourcePort: _srcPort.text.trim(),
            destIp: _destIp.text.trim(),
            destPort: _destPort.text.trim(),
            protocol: _protocol,
            destZone: _destZone,
            takenSections: widget.taken,
          )
        : FirewallPlanner.planUpdatePortForward(
            existing: widget.existing!,
            name: _name.text.trim(),
            sourceZone: _srcZone,
            sourcePort: _srcPort.text.trim(),
            destIp: _destIp.text.trim(),
            destPort: _destPort.text.trim(),
            protocol: _protocol,
            destZone: _destZone,
          );
    Navigator.of(context).pop(ops);
  }
}
