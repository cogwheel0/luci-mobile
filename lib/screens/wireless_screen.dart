import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/models/wireless_config.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/services/wireless_planner.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/state/wireless_notifier.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_apply_progress.dart';
import 'package:luci_mobile/widgets/luci_feature_gate.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';

/// Every SSID on the router, grouped by the radio that hosts it.
class WirelessScreen extends ConsumerStatefulWidget {
  const WirelessScreen({super.key});

  @override
  ConsumerState<WirelessScreen> createState() => _WirelessScreenState();
}

class _WirelessScreenState extends ConsumerState<WirelessScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(wirelessConfigProvider);
    final gate = ref.watch(featureProvider(RouterFeature.wirelessStations));

    return Scaffold(
      appBar: LuciAppBar(title: l10n.wirelessNetworks, showBack: true),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(wirelessConfigProvider),
        child: async.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(LuciSpacing.md),
            children: const [
              LuciCardSkeleton(contentLines: 3),
              SizedBox(height: LuciSpacing.md),
              LuciCardSkeleton(contentLines: 3),
            ],
          ),
          error: (error, _) => _Message(
            icon: Icons.error_outline,
            text: userFacingApiError(error),
            action: l10n.retry,
            onAction: () => ref.invalidate(wirelessConfigProvider),
          ),
          data: (radios) => radios.isEmpty
              ? _Message(
                  icon: Icons.wifi_off_rounded,
                  text: gate.explain(context) ?? l10n.noWirelessRadios,
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: LuciSpacing.xxl),
                  children: [
                    for (final radio in radios)
                      _RadioCard(
                        radio: radio,
                        busy: _busy,
                        onToggleNetwork: (n, on) => _apply(
                          WirelessPlanner.planSetEnabled(
                            network: n,
                            enabled: on,
                          ),
                        ),
                        onToggleRadio: (on) => _apply(
                          WirelessPlanner.planSetRadioEnabled(
                            radio: radio,
                            enabled: on,
                          ),
                        ),
                        onEdit: (n) => _editNetwork(radio, n),
                        onAdd: () => _editNetwork(radio, null),
                        onRadioSettings: () => _editRadio(radio),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _editNetwork(
    WirelessRadio radio,
    WirelessNetwork? existing,
  ) async {
    final ops = await showModalBottomSheet<List<UciOperation>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NetworkSheet(radio: radio, existing: existing),
    );
    if (ops != null) await _apply(ops);
  }

  Future<void> _editRadio(WirelessRadio radio) async {
    final ops = await showModalBottomSheet<List<UciOperation>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RadioSheet(radio: radio),
    );
    if (ops != null) await _apply(ops);
  }

  Future<void> _apply(List<UciOperation> ops) async {
    if (ops.isEmpty || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final progress = ApplyProgress();
    try {
      final outcome = await LuciApplyProgressDialog.run<ApplyOutcome?>(
        context,
        progress: progress,
        work: () => ref
            .read(wirelessMutationsProvider)
            .apply(ops, onPhase: progress.update),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(applyOutcomeMessage(context, outcome))),
      );
    } finally {
      progress.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _RadioCard extends StatelessWidget {
  const _RadioCard({
    required this.radio,
    required this.busy,
    required this.onToggleNetwork,
    required this.onToggleRadio,
    required this.onEdit,
    required this.onAdd,
    required this.onRadioSettings,
  });

  final WirelessRadio radio;
  final bool busy;
  final void Function(WirelessNetwork, bool) onToggleNetwork;
  final void Function(bool) onToggleRadio;
  final void Function(WirelessNetwork) onEdit;
  final VoidCallback onAdd;
  final VoidCallback onRadioSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final aps = radio.networks.where((n) => n.isAccessPoint).toList();
    final others = radio.networks.where((n) => !n.isAccessPoint).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuciSpacing.md,
        LuciSpacing.md,
        LuciSpacing.md,
        0,
      ),
      child: LuciCardStyles.standardCardWrapper(
        context: context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  radio.disabled ? Icons.wifi_off : Icons.wifi,
                  color: radio.disabled
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                ),
                const SizedBox(width: LuciSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        radio.label,
                        style: LuciTextStyles.cardTitle(context),
                      ),
                      Text(
                        _radioSummary(context, radio),
                        style: LuciTextStyles.cardSubtitle(context),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: l10n.radioSettings,
                  onPressed: busy ? null : onRadioSettings,
                ),
                Switch.adaptive(
                  value: !radio.disabled,
                  onChanged: busy ? null : onToggleRadio,
                ),
              ],
            ),
            const Divider(height: LuciSpacing.lg),
            for (final n in aps)
              _NetworkRow(
                network: n,
                busy: busy,
                onToggle: (on) => onToggleNetwork(n, on),
                onEdit: () => onEdit(n),
              ),
            // Station-mode entries are how this router joins someone else's
            // network; editing them here would be a different task.
            for (final n in others)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.link, size: 20),
                title: Text(n.ssid ?? l10n.unknown),
                subtitle: Text(l10n.clientStationMode),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: busy ? null : onAdd,
                icon: const Icon(Icons.add),
                label: Text(l10n.addNetwork),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _radioSummary(BuildContext context, WirelessRadio radio) {
    final l10n = context.l10n;
    final parts = <String>[
      if (radio.channel != null)
        radio.channel == 'auto'
            ? l10n.channelAuto
            : l10n.channelValue(radio.channel!),
      if (radio.htmode != null) radio.htmode!,
      if (radio.country != null) radio.country!,
    ];
    return parts.isEmpty ? l10n.unknown : parts.join(' · ');
  }
}

class _NetworkRow extends StatelessWidget {
  const _NetworkRow({
    required this.network,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
  });

  final WirelessNetwork network;
  final bool busy;
  final void Function(bool) onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final badges = <String>[
      if (network.isOpen) l10n.securityOpen else l10n.secured,
      if (network.hidden) l10n.hiddenSsid,
      if (network.looksLikeGuest) l10n.guestNetwork,
    ];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: busy ? null : onEdit,
      leading: Icon(
        network.isOpen ? Icons.lock_open : Icons.lock_outline,
        size: 20,
        color: network.isOpen ? Theme.of(context).colorScheme.error : null,
      ),
      title: Text(network.ssid ?? l10n.hiddenNetwork),
      subtitle: Text(badges.join(' · ')),
      trailing: Switch.adaptive(
        value: !network.disabled,
        onChanged: busy ? null : onToggle,
      ),
    );
  }
}

/// Create or edit one SSID.
class _NetworkSheet extends StatefulWidget {
  const _NetworkSheet({required this.radio, this.existing});

  final WirelessRadio radio;
  final WirelessNetwork? existing;

  @override
  State<_NetworkSheet> createState() => _NetworkSheetState();
}

class _NetworkSheetState extends State<_NetworkSheet> {
  late final TextEditingController _ssid = TextEditingController(
    text: widget.existing?.ssid ?? '',
  );
  late final TextEditingController _key = TextEditingController(
    text: widget.existing?.key ?? '',
  );
  late WirelessSecurity _security =
      WirelessSecurity.fromUci(widget.existing?.encryption) ??
      WirelessSecurity.wpa2;
  late bool _hidden = widget.existing?.hidden ?? false;
  late bool _isolate = widget.existing?.isolate ?? false;
  bool _showKey = false;

  /// An EAP network carries RADIUS settings this editor does not model, so it
  /// is shown read-only rather than silently rewritten into a PSK network.
  bool get _isEnterprise =>
      WirelessSecurity.isEnterprise(widget.existing?.encryption);

  @override
  void dispose() {
    _ssid.dispose();
    _key.dispose();
    super.dispose();
  }

  String? get _ssidError {
    final v = _ssid.text.trim();
    if (v.isEmpty) return null; // do not shout before they have typed
    return WirelessPlanner.isValidSsid(v) ? null : context.l10n.ssidTooLong;
  }

  String? get _keyError {
    if (!_security.needsPassphrase) return null;
    final v = _key.text;
    if (v.isEmpty) return null;
    return WirelessPlanner.isValidPassphrase(v)
        ? null
        : context.l10n.passwordLengthError;
  }

  bool get _canSave {
    final ssid = _ssid.text.trim();
    if (!WirelessPlanner.isValidSsid(ssid)) return false;
    if (_security.needsPassphrase) {
      final key = _key.text;
      final unchanged =
          widget.existing?.key != null && key == widget.existing!.key;
      if (!unchanged && !WirelessPlanner.isValidPassphrase(key)) return false;
    }
    return true;
  }

  void _save() {
    final ssid = _ssid.text.trim();
    final key = _security.needsPassphrase ? _key.text : null;
    final ops = widget.existing == null
        ? WirelessPlanner.planCreateNetwork(
            radio: widget.radio,
            ssid: ssid,
            security: _security,
            passphrase: key,
            // Isolation is an option on the AP itself. Attaching an isolated
            // SSID to a `guest` network instead would leave it with no
            // bridge and no DHCP on the many routers that have no such
            // interface; the editor for an existing SSID does not move it
            // either.
            hidden: _hidden,
            isolate: _isolate,
          )
        : WirelessPlanner.planUpdateNetwork(
            existing: widget.existing!,
            ssid: ssid,
            security: _security,
            passphrase: key,
            hidden: _hidden,
            isolate: _isolate,
          );
    Navigator.of(context).pop(ops);
  }

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
              widget.existing == null ? l10n.addNetwork : l10n.editNetwork,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                // Large text reads too loose at default tracking.
                letterSpacing: -0.4,
              ),
            ),
            Text(
              widget.radio.label,
              style: LuciTextStyles.cardSubtitle(context),
            ),
            const SizedBox(height: LuciSpacing.lg),

            if (_isEnterprise) ...[
              _Banner(text: l10n.enterpriseNotEditable),
              const SizedBox(height: LuciSpacing.md),
            ],

            TextField(
              controller: _ssid,
              enabled: !_isEnterprise,
              autofocus: widget.existing == null,
              decoration: InputDecoration(
                labelText: l10n.networkNameSsid,
                errorText: _ssidError,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: LuciSpacing.md),

            DropdownButtonFormField<WirelessSecurity>(
              initialValue: _security,
              decoration: InputDecoration(labelText: l10n.encryption),
              items: [
                for (final s in WirelessSecurity.values)
                  DropdownMenuItem(value: s, child: Text(_securityLabel(s))),
              ],
              onChanged: _isEnterprise
                  ? null
                  : (v) => setState(() => _security = v ?? _security),
            ),

            if (_security.needsPassphrase) ...[
              const SizedBox(height: LuciSpacing.md),
              TextField(
                controller: _key,
                enabled: !_isEnterprise,
                obscureText: !_showKey,
                decoration: InputDecoration(
                  labelText: l10n.password,
                  errorText: _keyError,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showKey ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],

            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.hiddenSsid),
              subtitle: Text(l10n.hiddenSsidDescription),
              value: _hidden,
              onChanged: _isEnterprise
                  ? null
                  : (v) => setState(() => _hidden = v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.clientIsolation),
              subtitle: Text(l10n.clientIsolationDescription),
              value: _isolate,
              onChanged: _isEnterprise
                  ? null
                  : (v) => setState(() => _isolate = v),
            ),

            const SizedBox(height: LuciSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.existing != null)
                  TextButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(WirelessPlanner.planDeleteNetwork(widget.existing!)),
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
                  onPressed: _isEnterprise || !_canSave ? null : _save,
                  child: Text(l10n.saveAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _securityLabel(WirelessSecurity s) => switch (s) {
    WirelessSecurity.none => context.l10n.securityOpen,
    WirelessSecurity.wpa2 => 'WPA2-PSK',
    WirelessSecurity.wpa2wpa3 => 'WPA2/WPA3',
    WirelessSecurity.wpa3 => 'WPA3-SAE',
    WirelessSecurity.owe => 'OWE',
  };
}

/// Radio-level settings: channel, width, country.
class _RadioSheet extends StatefulWidget {
  const _RadioSheet({required this.radio});

  final WirelessRadio radio;

  @override
  State<_RadioSheet> createState() => _RadioSheetState();
}

class _RadioSheetState extends State<_RadioSheet> {
  late String _channel = widget.radio.channel ?? 'auto';
  late String _htmode =
      widget.radio.htmode ??
      WirelessPlanner.htmodesFor(widget.radio.band).first;
  late final TextEditingController _country = TextEditingController(
    text: widget.radio.country ?? '',
  );

  @override
  void dispose() {
    _country.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final channels = WirelessPlanner.channelsFor(widget.radio.band);
    final htmodes = WirelessPlanner.htmodesFor(widget.radio.band);

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
              l10n.radioSettings,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              widget.radio.label,
              style: LuciTextStyles.cardSubtitle(context),
            ),
            const SizedBox(height: LuciSpacing.lg),

            DropdownButtonFormField<String>(
              initialValue: channels.contains(_channel) ? _channel : 'auto',
              decoration: InputDecoration(labelText: l10n.channel),
              items: [
                for (final c in channels)
                  DropdownMenuItem(
                    value: c,
                    child: Text(c == 'auto' ? l10n.channelAuto : c),
                  ),
              ],
              onChanged: (v) => setState(() => _channel = v ?? _channel),
            ),
            const SizedBox(height: LuciSpacing.md),

            DropdownButtonFormField<String>(
              initialValue: htmodes.contains(_htmode) ? _htmode : htmodes.first,
              decoration: InputDecoration(labelText: l10n.channelWidth),
              items: [
                for (final m in htmodes)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) => setState(() => _htmode = v ?? _htmode),
            ),
            const SizedBox(height: LuciSpacing.md),

            TextField(
              controller: _country,
              textCapitalization: TextCapitalization.characters,
              maxLength: 2,
              decoration: InputDecoration(
                labelText: l10n.countryCode,
                helperText: l10n.countryCodeDescription,
              ),
            ),

            const SizedBox(height: LuciSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: LuciSpacing.sm),
                FilledButton(
                  onPressed: () {
                    final country = _country.text.trim().toUpperCase();
                    Navigator.of(context).pop(
                      WirelessPlanner.planUpdateRadio(
                        radio: widget.radio,
                        channel: _channel,
                        htmode: _htmode,
                        country: country.isEmpty ? null : country,
                      ),
                    );
                  },
                  child: Text(l10n.saveAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
            child: Text(text, style: LuciTextStyles.cardSubtitle(context)),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const SizedBox(height: LuciSpacing.xxl),
      Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
      const SizedBox(height: LuciSpacing.md),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: LuciSpacing.xl),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: LuciTextStyles.cardSubtitle(context),
        ),
      ),
      if (action != null)
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: LuciSpacing.md),
            child: TextButton(onPressed: onAction, child: Text(action!)),
          ),
        ),
    ],
  );
}
