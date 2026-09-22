import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/state/system_settings_notifier.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_apply_progress.dart';
import 'package:luci_mobile/widgets/luci_feature_gate.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';

/// Router identity and clock — LuCI's System → General Settings.
class SystemSettingsScreen extends ConsumerStatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  ConsumerState<SystemSettingsScreen> createState() =>
      _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends ConsumerState<SystemSettingsScreen> {
  final _hostname = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();
  String? _zoneName;
  SystemSettings? _loaded;
  bool _busy = false;

  @override
  void dispose() {
    _hostname.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Seeds the fields once. Re-seeding on every rebuild would overwrite what
  /// the user is in the middle of typing.
  void _seed(SystemSettings settings) {
    if (identical(_loaded, settings)) return;
    _loaded = settings;
    _hostname.text = settings.hostname;
    _description.text = settings.description;
    _notes.text = settings.notes;
    _zoneName = settings.zoneName.isEmpty ? null : settings.zoneName;
  }

  List<UciOperation> _plan(SystemSettings settings) => planSystemSettings(
    current: settings,
    hostname: _hostname.text,
    zoneName: _zoneName ?? settings.zoneName,
    description: _description.text,
    notes: _notes.text,
  );

  Future<void> _save(SystemSettings settings) async {
    final ops = _plan(settings);
    if (ops.isEmpty || _busy) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final progress = ApplyProgress();
    try {
      final outcome = await LuciApplyProgressDialog.run<ApplyOutcome?>(
        context,
        progress: progress,
        work: () => ref
            .read(systemSettingsMutationsProvider)
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

  Future<void> _changePassword() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final error = await ref
          .read(passwordMutationsProvider)
          .change(password, context: mounted ? context : null);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (error) {
            null => l10n.passwordChanged,
            PasswordChangeError.rejected => l10n.passwordRejected,
            _ => l10n.changeFailed,
          }),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gate = ref.watch(featureProvider(RouterFeature.systemSettings));
    final async = ref.watch(systemSettingsProvider);

    return Scaffold(
      appBar: LuciAppBar(title: l10n.systemSettings, showBack: true),
      body: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(LuciSpacing.md),
          child: LuciCardSkeleton(contentLines: 4),
        ),
        error: (error, _) => _Message(
          text: gate.explain(context) ?? userFacingApiError(error),
          action: l10n.retry,
          onAction: () => ref.invalidate(systemSettingsProvider),
        ),
        data: (settings) {
          if (settings == null || settings.section.isEmpty) {
            return _Message(text: gate.explain(context) ?? l10n.noData);
          }
          _seed(settings);
          return _Form(
            settings: settings,
            hostname: _hostname,
            description: _description,
            notes: _notes,
            zoneName: _zoneName,
            editable: gate.available && !_busy,
            gateHint: gate.explain(context),
            onZoneChanged: (zone) => setState(() => _zoneName = zone),
            onChanged: () => setState(() {}),
            dirty: _plan(settings).isNotEmpty,
            valid: isValidHostname(_hostname.text.trim()),
            onSave: () => _save(settings),
            onChangePassword: _busy ? null : _changePassword,
          );
        },
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.settings,
    required this.hostname,
    required this.description,
    required this.notes,
    required this.zoneName,
    required this.editable,
    required this.gateHint,
    required this.onZoneChanged,
    required this.onChanged,
    required this.dirty,
    required this.valid,
    required this.onSave,
    required this.onChangePassword,
  });

  final SystemSettings settings;
  final TextEditingController hostname;
  final TextEditingController description;
  final TextEditingController notes;
  final String? zoneName;
  final bool editable;
  final String? gateHint;
  final ValueChanged<String?> onZoneChanged;
  final VoidCallback onChanged;
  final bool dirty;
  final bool valid;
  final VoidCallback onSave;
  final VoidCallback? onChangePassword;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hostnameError = hostname.text.trim().isEmpty || valid
        ? null
        : l10n.invalidHostname;

    return ListView(
      padding: const EdgeInsets.all(LuciSpacing.md),
      children: [
        if (gateHint != null) ...[
          LuciCardStyles.standardCardWrapper(
            context: context,
            padding: const EdgeInsets.all(LuciSpacing.md),
            child: Text(gateHint!, style: LuciTextStyles.cardSubtitle(context)),
          ),
          const SizedBox(height: LuciSpacing.md),
        ],
        LuciCardStyles.standardCardWrapper(
          context: context,
          padding: const EdgeInsets.all(LuciSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: hostname,
                enabled: editable,
                onChanged: (_) => onChanged(),
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.hostname,
                  helperText: l10n.hostnameHelp,
                  helperMaxLines: 2,
                  errorText: hostnameError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: LuciSpacing.md),
              TextField(
                controller: description,
                enabled: editable,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  labelText: l10n.routerDescription,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: LuciSpacing.md),
              TextField(
                controller: notes,
                enabled: editable,
                onChanged: (_) => onChanged(),
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.routerNotes,
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: LuciSpacing.md),
        LuciCardStyles.standardCardWrapper(
          context: context,
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(l10n.timezone),
            subtitle: Text(
              zoneName ?? settings.zoneName.ifEmpty(l10n.timezoneUtc),
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: editable && settings.timezones.isNotEmpty,
            onTap: editable && settings.timezones.isNotEmpty
                ? () async {
                    final picked = await showModalBottomSheet<String>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => _TimezoneSheet(
                        zones: settings.zoneNames,
                        selected: zoneName ?? settings.zoneName,
                      ),
                    );
                    if (picked != null) onZoneChanged(picked);
                  }
                : null,
          ),
        ),
        const SizedBox(height: LuciSpacing.md),
        LuciCardStyles.standardCardWrapper(
          context: context,
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.key_outlined),
            title: Text(l10n.routerPassword),
            subtitle: Text(l10n.routerPasswordHelp),
            trailing: const Icon(Icons.chevron_right),
            enabled: onChangePassword != null,
            onTap: onChangePassword,
          ),
        ),
        const SizedBox(height: LuciSpacing.lg),
        FilledButton(
          onPressed: editable && dirty && valid ? onSave : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// 890 zones is a list nobody scrolls, so it opens on a search field.
class _TimezoneSheet extends StatefulWidget {
  const _TimezoneSheet({required this.zones, required this.selected});

  final List<String> zones;
  final String selected;

  @override
  State<_TimezoneSheet> createState() => _TimezoneSheetState();
}

class _TimezoneSheetState extends State<_TimezoneSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final needle = _query.trim().toLowerCase();
    final matches = needle.isEmpty
        ? widget.zones
        : [
            for (final z in widget.zones)
              if (z.toLowerCase().contains(needle)) z,
          ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LuciSpacing.md,
              0,
              LuciSpacing.md,
              LuciSpacing.sm,
            ),
            child: TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: l10n.searchTimezone,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: matches.length,
              itemBuilder: (context, i) {
                final zone = matches[i];
                return ListTile(
                  title: Text(zone),
                  trailing: zone == widget.selected
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(zone),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const SizedBox(height: LuciSpacing.xxl),
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
          child: TextButton(onPressed: onAction, child: Text(action!)),
        ),
    ],
  );
}

/// Changing the router's login password.
///
/// It is the same account used for SSH and the LuCI web UI, so the dialog
/// says so rather than letting it read as an app-only setting.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = _password.text;
    final tooShort = value.isNotEmpty && value.length < 5;
    final mismatch = _confirm.text.isNotEmpty && _confirm.text != value;
    final valid = value.length >= 5 && _confirm.text == value;

    return AlertDialog(
      title: Text(l10n.routerPassword),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.routerPasswordWarning,
            style: LuciTextStyles.cardSubtitle(context),
          ),
          const SizedBox(height: LuciSpacing.md),
          TextField(
            controller: _password,
            obscureText: _obscure,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.newPassword,
              errorText: tooShort ? l10n.passwordTooShort : null,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: LuciSpacing.md),
          TextField(
            controller: _confirm,
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.confirmPassword,
              errorText: mismatch ? l10n.passwordsDoNotMatch : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: valid ? () => Navigator.of(context).pop(value) : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
