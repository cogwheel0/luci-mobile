import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/failure_text.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/state/system_settings_notifier.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_apply_progress.dart';
import 'package:luci_mobile/widgets/luci_feature_gate.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

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
    try {
      await runApply(
        context,
        work: (progress) => ref
            .read(systemSettingsMutationsProvider)
            .apply(ops, onPhase: progress.update),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final password = await showAdaptiveFormSheet<String>(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    final l10n = context.l10n;
    try {
      final error = await ref
          .read(passwordMutationsProvider)
          .change(password, context: mounted ? context : null);
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: switch (error) {
          null => l10n.passwordChanged,
          PasswordChangeError.rejected => l10n.passwordRejected,
          _ => l10n.changeFailed,
        },
        type: error == null
            ? AdaptiveSnackBarType.success
            : AdaptiveSnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gate = ref.watch(featureProvider(RouterFeature.systemSettings));
    final session = ref.watch(sessionProvider);
    final async = ref.watch(systemSettingsProvider);

    // iOS lays the settings out as grouped rows, on the grouped background.
    final grouped = PlatformUiCapabilities.isIOS
        ? CupertinoColors.systemGroupedBackground.resolveFrom(context)
        : null;
    return Scaffold(
      backgroundColor: grouped,
      appBar: LuciAppBar(
        title: l10n.systemSettings,
        showBack: true,
        backgroundColor: grouped?.withValues(alpha: 0.94),
      ),
      body: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(LuciSpacing.md),
          child: LuciCardSkeleton(contentLines: 4),
        ),
        error: (error, _) => LuciMessageState(
          message: gate.explain(context) ?? apiErrorText(context, error),
          action: l10n.retry,
          onAction: () => ref.invalidate(systemSettingsProvider),
        ),
        data: (settings) {
          if (settings == null || settings.section.isEmpty) {
            return LuciMessageState(
              message: gate.explain(context) ?? l10n.noData,
            );
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
            // Reviewer mode answers from fixtures, so a "password changed"
            // there would rewrite the saved profile while the real router
            // kept the old one - locking the user out of their own router.
            onChangePassword: _busy || (session?.reviewerMode ?? false)
                ? null
                : _changePassword,
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

  bool get _canPickZone => editable && settings.timezones.isNotEmpty;

  Future<void> _pickZone(BuildContext context) async {
    final zones = settings.zoneNames;
    final selected = zoneName ?? settings.zoneName;
    // iOS pushes a page of its own, as iOS Settings' time zone list.
    final picked = PlatformUiCapabilities.isIOS
        ? await Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (_) => _TimezonePage(zones: zones, selected: selected),
            ),
          )
        : await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _TimezoneSheet(zones: zones, selected: selected),
          );
    if (picked != null) onZoneChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hostnameError = hostname.text.trim().isEmpty || valid
        ? null
        : l10n.invalidHostname;

    if (PlatformUiCapabilities.isIOS) {
      // As iOS Settings lays out a page: the router's identity, then rows
      // leading to its time zone and password, with Save below.
      return ListView(
        padding: const EdgeInsets.all(LuciSpacing.md),
        children: [
          AdaptiveForm(
            sections: [
              AdaptiveFormSection(
                // Why nothing here can be changed, when that is so.
                footer: gateHint,
                children: [
                  AdaptiveFormTextField(
                    label: l10n.hostname,
                    controller: hostname,
                    enabled: editable,
                    helper: l10n.hostnameHelp,
                    error: hostnameError,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => onChanged(),
                  ),
                  AdaptiveFormTextField(
                    label: l10n.routerDescription,
                    controller: description,
                    enabled: editable,
                    onChanged: (_) => onChanged(),
                  ),
                  AdaptiveFormTextField(
                    label: l10n.routerNotes,
                    controller: notes,
                    enabled: editable,
                    maxLines: 3,
                    onChanged: (_) => onChanged(),
                  ),
                ],
              ),
              AdaptiveFormSection(
                children: [
                  AdaptiveFormNavigationRow(
                    label: l10n.timezone,
                    value:
                        zoneName ?? settings.zoneName.ifEmpty(l10n.timezoneUtc),
                    onTap: _canPickZone ? () => _pickZone(context) : null,
                  ),
                  AdaptiveFormNavigationRow(
                    label: l10n.routerPassword,
                    onTap: onChangePassword,
                  ),
                ],
              ),
            ],
          ),
          AdaptiveButton(
            onPressed: editable && dirty && valid ? onSave : null,
            label: l10n.save,
          ),
        ],
      );
    }

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
            onTap: _canPickZone ? () => _pickZone(context) : null,
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
        AdaptiveButton(
          onPressed: editable && dirty && valid ? onSave : null,
          label: l10n.save,
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

/// The time zones on iOS, as a page of grouped rows under a search field,
/// the current one checked. Pops with the zone tapped.
class _TimezonePage extends StatefulWidget {
  const _TimezonePage({required this.zones, required this.selected});

  final List<String> zones;
  final String selected;

  @override
  State<_TimezonePage> createState() => _TimezonePageState();
}

class _TimezonePageState extends State<_TimezonePage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final grouped = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    final needle = _search.text.trim().toLowerCase();
    return Scaffold(
      backgroundColor: grouped,
      appBar: LuciAppBar(
        title: l10n.timezone,
        showBack: true,
        backgroundColor: grouped.withValues(alpha: 0.94),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: AdaptiveSearchField(
                controller: _search,
                placeholder: l10n.searchTimezone,
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: AdaptiveFormChoiceList<String>(
                // A new search starts at its first match, wherever the
                // list was scrolled to before.
                key: ValueKey(needle),
                choices: [
                  for (final zone in widget.zones)
                    if (needle.isEmpty || zone.toLowerCase().contains(needle))
                      AdaptiveFormChoice(zone, zone),
                ],
                value: widget.selected,
                onSelected: (zone) => Navigator.of(context).pop(zone),
              ),
            ),
          ],
        ),
      ),
    );
  }
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

    return AdaptiveFormSheet(
      title: l10n.routerPassword,
      cancelLabel: l10n.cancel,
      confirmLabel: l10n.saveAction,
      onConfirm: valid ? () => Navigator.of(context).pop(value) : null,
      grouped: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Above the fields on Android; iOS explains a group under it.
          if (!PlatformUiCapabilities.isIOS) ...[
            Text(
              l10n.routerPasswordWarning,
              style: LuciTextStyles.cardSubtitle(context),
            ),
            const SizedBox(height: LuciSpacing.md),
          ],
          AdaptiveFormSection(
            footer: l10n.routerPasswordWarning,
            children: [
              AdaptiveFormTextField(
                label: l10n.newPassword,
                controller: _password,
                obscureText: _obscure,
                autofocus: true,
                error: tooShort ? l10n.passwordTooShort : null,
                materialDecoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                suffix: AdaptiveObscureToggle(
                  obscured: _obscure,
                  materialOutlined: true,
                  semanticLabel: _obscure
                      ? l10n.showPassword
                      : l10n.hidePassword,
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                onChanged: (_) => setState(() {}),
              ),
              AdaptiveFormTextField(
                label: l10n.confirmPassword,
                controller: _confirm,
                obscureText: _obscure,
                error: mismatch ? l10n.passwordsDoNotMatch : null,
                materialDecoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
