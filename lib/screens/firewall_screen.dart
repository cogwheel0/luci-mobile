import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/app_localizations.dart';
import 'package:luci_mobile/l10n/failure_text.dart';
import 'package:luci_mobile/utils/ipv4.dart';
import 'package:luci_mobile/utils/keyboards.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/firewall_config.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/firewall_planner.dart';
import 'package:luci_mobile/state/firewall_notifier.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_apply_progress.dart';
import 'package:luci_mobile/widgets/luci_hub_tile.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

/// Port forwards, traffic rules, zones and static routes.
///
/// On Android, one screen with tabs rather than four hub entries: these are
/// four views of the same question — what is allowed in and out — and
/// jumping between them while diagnosing something is the normal case. On
/// iOS, where tabs under a navigation bar are not how settings are laid
/// out, a list of the four that each push their own page, as iOS Settings
/// does; each row says what is in it.
class FirewallScreen extends ConsumerStatefulWidget {
  const FirewallScreen({super.key});

  @override
  ConsumerState<FirewallScreen> createState() => _FirewallScreenState();
}

/// The four parts of the firewall: a tab each on Android, a page each on iOS.
enum _FirewallSection { forwards, rules, zones, routes }

extension on _FirewallSection {
  String title(AppLocalizations l10n) => switch (this) {
    _FirewallSection.forwards => l10n.portForwards,
    _FirewallSection.rules => l10n.trafficRules,
    _FirewallSection.zones => l10n.zones,
    _FirewallSection.routes => l10n.staticRoutes,
  };

  IconData get icon => switch (this) {
    _FirewallSection.forwards => Icons.swap_horiz,
    _FirewallSection.rules => Icons.rule,
    _FirewallSection.zones => Icons.security,
    _FirewallSection.routes => Icons.alt_route,
  };
}

String _forwardName(PortForward f) =>
    f.name ?? '${f.sourceZone}:${f.sourcePort ?? "?"}';

/// The first few of [names], for a row that shows two lines and is read
/// out whole by VoiceOver: a router with dozens of rules should not have
/// them all built and announced. The row's count gives the total.
String _preview(List<String> names) {
  const shown = 5;
  if (names.length <= shown) return names.join(', ');
  return '${names.take(shown).join(', ')}, …';
}

String _routeName(StaticRoute r) =>
    '${r.target}${r.netmask == null ? '' : '/${r.netmask}'}';

/// What every firewall view does with the state: apply a change, or open a
/// port forward. One change at a time per view.
mixin _FirewallActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool _busy = false;

  /// The firewall as [build] shows it, with the screens' shared loading and
  /// error states.
  Widget _firewallBody(Widget Function(FirewallState state) data) {
    final l10n = context.l10n;
    return ref
        .watch(firewallProvider)
        .when(
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
          data: data,
        );
  }

  /// One part of the firewall, wired to these actions. [showAddButton] is
  /// false where the port forwards' page has its own add action.
  Widget _section(
    _FirewallSection section,
    FirewallState state, {
    bool showAddButton = true,
  }) => switch (section) {
    _FirewallSection.forwards => _ForwardsTab(
      state: state,
      busy: _busy,
      showAddButton: showAddButton,
      onToggle: (f, on) => _apply(
        FirewallPlanner.planSetForwardEnabled(forward: f, enabled: on),
      ),
      onEdit: (f) => _editForward(state, f),
      onAdd: () => _editForward(state, null),
    ),
    _FirewallSection.rules => _RulesTab(
      rules: state.rules,
      busy: _busy,
      onToggle: (r, on) =>
          _apply(FirewallPlanner.planSetRuleEnabled(rule: r, enabled: on)),
      onRemove: (r) => _apply(FirewallPlanner.planRemoveRule(r)),
    ),
    _FirewallSection.zones => _ZonesTab(zones: state.zones),
    _FirewallSection.routes => _RoutesTab(
      routes: state.routes,
      busy: _busy,
      onRemove: (r) => _apply(FirewallPlanner.planDeleteRoute(r)),
    ),
  };

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
    final ops = await showAdaptiveFormSheet<List<UciOperation>>(
      context: context,
      material: const AdaptiveFormMaterialPresentation.bottomSheet(),
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

class _FirewallScreenState extends ConsumerState<FirewallScreen>
    with _FirewallActions {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (PlatformUiCapabilities.isIOS) {
      final grouped = CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      );
      return Scaffold(
        backgroundColor: grouped,
        appBar: LuciAppBar(
          title: l10n.firewall,
          showBack: true,
          backgroundColor: grouped.withValues(alpha: 0.94),
        ),
        body: _firewallBody(
          (state) => ListView(
            padding: const EdgeInsets.symmetric(vertical: LuciSpacing.sm),
            children: [
              LuciHubSection(
                tiles: [
                  for (final section in _FirewallSection.values)
                    _hubTile(context, section, state),
                ],
              ),
            ],
          ),
        ),
      );
    }

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
              for (final section in _FirewallSection.values)
                Tab(text: section.title(l10n)),
            ],
          ),
        ),
        body: _firewallBody(
          (state) => TabBarView(
            children: [
              for (final section in _FirewallSection.values)
                _section(section, state),
            ],
          ),
        ),
      ),
    );
  }

  /// A row of the iOS list: the part's name, what is in it, and how many.
  Widget _hubTile(
    BuildContext context,
    _FirewallSection section,
    FirewallState state,
  ) {
    final l10n = context.l10n;
    final (names, empty) = switch (section) {
      _FirewallSection.forwards => (
        [for (final f in state.forwards) _forwardName(f)],
        l10n.noPortForwards,
      ),
      _FirewallSection.rules => (
        [for (final r in state.rules) r.name ?? r.section],
        l10n.noTrafficRules,
      ),
      _FirewallSection.zones => (
        [for (final z in state.zones) z.name],
        l10n.noZones,
      ),
      _FirewallSection.routes => (
        [for (final r in state.routes) _routeName(r)],
        l10n.noStaticRoutes,
      ),
    };
    return LuciHubTile(
      icon: section.icon,
      title: section.title(l10n),
      subtitle: names.isEmpty ? empty : _preview(names),
      subtitleMaxLines: 2,
      // How many there are; the hub row adds its own chevron.
      trailing: names.isEmpty
          ? null
          : Text(
              '${names.length}',
              style: TextStyle(
                fontSize: 17,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _FirewallSectionPage(section: section),
        ),
      ),
    );
  }
}

/// One part of the firewall on its own page, pushed from the iOS list.
class _FirewallSectionPage extends ConsumerStatefulWidget {
  const _FirewallSectionPage({required this.section});

  final _FirewallSection section;

  @override
  ConsumerState<_FirewallSectionPage> createState() =>
      _FirewallSectionPageState();
}

class _FirewallSectionPageState extends ConsumerState<_FirewallSectionPage>
    with _FirewallActions {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(firewallProvider).value;
    final forwards = widget.section == _FirewallSection.forwards;
    // iOS only: each part is a page of grouped rows.
    final grouped = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    return Scaffold(
      backgroundColor: grouped,
      appBar: LuciAppBar(
        title: widget.section.title(l10n),
        showBack: true,
        backgroundColor: grouped.withValues(alpha: 0.94),
        actions: [
          // Adding a forward is the navigation bar's +, as on iOS, rather
          // than a floating button.
          if (forwards)
            LuciAppBarAction(
              sfSymbol: 'plus',
              materialIcon: Icons.add,
              tooltip: l10n.addPortForward,
              onPressed: _busy || state == null
                  ? null
                  : () => _editForward(state, null),
            ),
        ],
      ),
      body: _firewallBody(
        (state) => _section(widget.section, state, showAddButton: false),
      ),
    );
  }
}

class _ForwardsTab extends StatelessWidget {
  const _ForwardsTab({
    required this.state,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onAdd,
    this.showAddButton = true,
  });

  final FirewallState state;
  final bool busy;
  final bool showAddButton;
  final void Function(PortForward, bool) onToggle;
  final void Function(PortForward) onEdit;
  final VoidCallback onAdd;

  /// What a forward maps: shown rather than making the user open the row.
  static String _mapping(BuildContext context, PortForward f) =>
      '${f.protocol.toUpperCase()}  '
      '${f.sourceZone}:${f.sourcePort ?? "?"}'
      '  →  ${f.destIp ?? "?"}:${f.effectiveDestPort}'
      // A restricted forward reads as open without this.
      '${f.sourceIp == null ? '' : '\n${context.l10n.sourceAddress}: ${f.sourceIp}'}';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (PlatformUiCapabilities.isIOS) {
      // On the page's grouped background; adding is the navigation bar's +.
      if (state.forwards.isEmpty) {
        return LuciMessageState(
          scrollable: false,
          icon: Icons.swap_horiz,
          message: l10n.noPortForwards,
        );
      }
      // A row per forward, opening it to edit, its switch outside the row's
      // tap so a native switch keeps its own tap.
      return AdaptiveGroupedListView(
        separatorIndent: 52,
        itemCount: state.forwards.length,
        itemBuilder: (context, i) {
          final f = state.forwards[i];
          final name = _forwardName(f);
          return AdaptiveListRow(
            leading: Icon(
              Icons.arrow_forward,
              color: f.enabled
                  ? Theme.of(context).colorScheme.primary
                  : CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
            title: name,
            subtitle: _mapping(context, f),
            onTap: busy ? null : () => onEdit(f),
            actions: [
              AdaptiveSwitch(
                value: f.enabled,
                semanticLabel: name,
                onChanged: busy ? null : (v) => onToggle(f, v),
              ),
            ],
          );
        },
      );
    }
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
                final name = _forwardName(f);
                return ListTile(
                  onTap: busy ? null : () => onEdit(f),
                  leading: Icon(
                    Icons.arrow_forward,
                    color: f.enabled
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  title: Text(name),
                  subtitle: Text(_mapping(context, f)),
                  trailing: AdaptiveSwitch(
                    value: f.enabled,
                    semanticLabel: name,
                    onChanged: busy ? null : (v) => onToggle(f, v),
                  ),
                );
              },
            ),
      floatingActionButton: showAddButton
          ? FloatingActionButton.extended(
              onPressed: busy ? null : onAdd,
              icon: const Icon(Icons.add),
              label: Text(l10n.addPortForward),
            )
          : null,
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
    Widget icon(TrafficRule r) {
      final scheme = Theme.of(context).colorScheme;
      final blocking = r.target == 'REJECT' || r.target == 'DROP';
      return Icon(
        blocking ? Icons.block : Icons.check_circle_outline,
        color: blocking ? scheme.error : scheme.primary,
      );
    }

    String summary(TrafficRule r) => [
      r.target,
      if (r.sourceMac != null) r.sourceMac!,
      if (r.protocol != null) r.protocol!.toUpperCase(),
      if (r.destPort != null) ':${r.destPort}',
    ].join('  ');

    List<Widget> actions(TrafficRule r) => [
      AdaptiveSwitch(
        value: r.enabled,
        semanticLabel: r.name ?? r.section,
        onChanged: busy ? null : (v) => onToggle(r, v),
      ),
      // A rule the user wrote is disabled rather than deleted, so the icon
      // says which will happen.
      AdaptiveButton.sfSymbol(
        onPressed: busy ? null : () => onRemove(r),
        sfSymbol: SFSymbol(r.ownedByApp ? 'trash' : 'pause'),
        materialIcon: r.ownedByApp ? Icons.delete_outline : Icons.pause,
        semanticLabel: r.ownedByApp ? l10n.remove : l10n.disableRule,
        style: AdaptiveButtonStyle.plain,
      ),
    ];

    if (PlatformUiCapabilities.isIOS) {
      return AdaptiveGroupedListView(
        separatorIndent: 52,
        itemCount: rules.length,
        itemBuilder: (context, i) => AdaptiveListRow(
          leading: icon(rules[i]),
          title: rules[i].name ?? rules[i].section,
          subtitle: summary(rules[i]),
          actions: actions(rules[i]),
        ),
      );
    }
    return ListView.separated(
      itemCount: rules.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = rules[i];
        return ListTile(
          leading: icon(r),
          title: Text(r.name ?? r.section),
          subtitle: Text(summary(r)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: actions(r)),
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
    if (PlatformUiCapabilities.isIOS) {
      // A group per zone, as iOS Settings groups a thing's facts: its name
      // over it, its policies as rows, and its networks under it.
      final scheme = Theme.of(context).colorScheme;
      Widget policy(String label, String value) => AdaptiveFormValueRow(
        label: label,
        value: value,
        valueColor: value.toUpperCase() == 'ACCEPT'
            ? scheme.primary
            : CupertinoColors.systemRed.resolveFrom(context),
      );
      return ListView(
        padding: const EdgeInsets.all(LuciSpacing.md),
        children: [
          for (final z in zones)
            AdaptiveFormSection(
              header: z.masq ? '${z.name} · NAT' : z.name,
              footer: z.networks.isEmpty ? null : z.networks.join(', '),
              children: [
                policy(l10n.zoneInput, z.input),
                policy(l10n.zoneOutput, z.output),
                policy(l10n.zoneForward, z.forward),
              ],
            ),
        ],
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
            style: LuciTextStyles.detailValue(context)
                .copyWith(color: permissive ? scheme.primary : scheme.error),
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
    String summary(StaticRoute r) => [
      if (r.gateway != null) 'via ${r.gateway}',
      r.interface,
      if (r.metric != null) 'metric ${r.metric}',
    ].join('  ');
    Widget remove(StaticRoute r) => AdaptiveButton.sfSymbol(
      onPressed: busy ? null : () => onRemove(r),
      sfSymbol: const SFSymbol('trash'),
      materialIcon: Icons.delete_outline,
      semanticLabel: l10n.remove,
      style: AdaptiveButtonStyle.plain,
    );

    if (PlatformUiCapabilities.isIOS) {
      return AdaptiveGroupedListView(
        separatorIndent: 52,
        itemCount: routes.length,
        itemBuilder: (context, i) => AdaptiveListRow(
          leading: Icon(
            Icons.alt_route,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: _routeName(routes[i]),
          subtitle: summary(routes[i]),
          actions: [remove(routes[i])],
        ),
      );
    }
    return ListView.separated(
      itemCount: routes.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = routes[i];
        return ListTile(
          leading: const Icon(Icons.alt_route),
          title: Text(_routeName(r)),
          subtitle: Text(summary(r)),
          trailing: remove(r),
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
  late final _srcIp = TextEditingController(
    text: widget.existing?.sourceIp ?? '',
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
    _srcIp.dispose();
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
      sourceIp: _srcIp.text.trim().isEmpty ? null : _srcIp.text.trim(),
    )) {
      return context.l10n.portAlreadyForwarded;
    }
    return null;
  }

  String? get _srcIpError {
    final v = _srcIp.text.trim();
    // One the router already has is left as it is, even in a form this
    // sheet would not write - a list, or a netmask set in LuCI.
    if (v.isEmpty || v == widget.existing?.sourceIp) return null;
    return FirewallPlanner.isValidSourceAddress(v)
        ? null
        : context.l10n.invalidSourceAddress;
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
      _srcPortError == null &&
      _srcIpError == null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final existing = widget.existing;
    return AdaptiveFormSheet(
      title: existing == null ? l10n.addPortForward : l10n.editPortForward,
      cancelLabel: l10n.cancel,
      confirmLabel: l10n.saveAction,
      onConfirm: _canSave ? _save : null,
      destructiveLabel: existing == null ? null : l10n.remove,
      onDestructive: existing == null ? null : () => _remove(existing),
      grouped: true,
      child: AdaptiveForm(
        sections: [
          AdaptiveFormSection(
            children: [
              AdaptiveFormTextField(
                label: l10n.forwardName,
                controller: _name,
                autofocus: widget.existing == null,
                onChanged: (_) => setState(() {}),
              ),
              AdaptiveFormPair(
                first: AdaptiveFormPicker<String>(
                  label: l10n.sourceZone,
                  value: _srcZone,
                  choices: [
                    for (final z in widget.state.zoneNames)
                      AdaptiveFormChoice(z, z),
                  ],
                  onChanged: (v) => setState(() => _srcZone = v ?? _srcZone),
                ),
                second: AdaptiveFormPicker<String>(
                  label: l10n.protocol,
                  value: _protocol,
                  choices: [
                    for (final p in _protocols)
                      AdaptiveFormChoice(p, _protoLabel(p)),
                  ],
                  onChanged: (v) => setState(() => _protocol = v ?? _protocol),
                ),
              ),
              AdaptiveFormTextField(
                label: l10n.externalPort,
                controller: _srcPort,
                keyboardType: numericAddressKeyboard,
                error: _srcPortError,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          AdaptiveFormSection(
            children: [
              AdaptiveFormTextField(
                label: l10n.sourceAddress,
                controller: _srcIp,
                // Not a number pad: a subnet needs `/`.
                keyboardType: TextInputType.text,
                autocorrect: false,
                placeholder: '203.0.113.0/24',
                helper: l10n.sourceAddressHint,
                helperMaxLines: 2,
                error: _srcIpError,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          AdaptiveFormSection(
            children: [
              AdaptiveFormPicker<String>(
                label: l10n.destinationZone,
                value: _destZone,
                choices: [
                  for (final z in widget.state.zoneNames)
                    AdaptiveFormChoice(z, z),
                ],
                onChanged: (v) => setState(() => _destZone = v ?? _destZone),
              ),
              AdaptiveFormTextField(
                label: l10n.internalAddress,
                controller: _destIp,
                keyboardType: numericAddressKeyboard,
                error: _destIpError,
                onChanged: (_) => setState(() {}),
              ),
              AdaptiveFormTextField(
                label: l10n.internalPort,
                controller: _destPort,
                keyboardType: numericAddressKeyboard,
                error: _destPortError,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Removes [forward] once the user confirms: Remove sits beside Save, and
  /// a forward deleted by a slip would have to be typed in again.
  Future<void> _remove(PortForward forward) async {
    final l10n = context.l10n;
    final confirmed = await AdaptiveAlertDialog.confirm(
      context: context,
      title: l10n.removePortForwardQuestion,
      message: l10n.removePortForwardDescription(_forwardName(forward)),
      confirmLabel: l10n.remove,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(FirewallPlanner.planDeletePortForward(forward));
  }

  void _save() {
    final srcIp = _srcIp.text.trim();
    final ops = widget.existing == null
        ? FirewallPlanner.planCreatePortForward(
            name: _name.text.trim(),
            sourceZone: _srcZone,
            sourceIp: srcIp.isEmpty ? null : srcIp,
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
            sourceIp: srcIp,
            sourcePort: _srcPort.text.trim(),
            destIp: _destIp.text.trim(),
            destPort: _destPort.text.trim(),
            protocol: _protocol,
            destZone: _destZone,
          );
    Navigator.of(context).pop(ops);
  }
}
