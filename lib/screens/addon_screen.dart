import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/failure_text.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/addon_strings.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/addon_spec.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/addon_catalog.dart';
import 'package:luci_mobile/services/addon_planner.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/addon_notifier.dart';
import 'package:luci_mobile/state/feature_providers.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_apply_progress.dart';
import 'package:luci_mobile/widgets/luci_feature_gate.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

/// Configures one add-on package.
///
/// Every field comes from a hand-written [AddonSpec], so this renders a
/// curated form — not an arbitrary UCI config.
class AddonScreen extends ConsumerStatefulWidget {
  const AddonScreen({super.key, required this.spec});

  final AddonSpec spec;

  @override
  ConsumerState<AddonScreen> createState() => _AddonScreenState();
}

class _AddonScreenState extends ConsumerState<AddonScreen> {
  /// Edits not yet written, per section name.
  final Map<String, Map<String, Object>> _edits = {};
  final Map<String, TextEditingController> _controllers = {};
  String? _selectedSection;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Object> _editsFor(String section) =>
      _edits.putIfAbsent(section, () => <String, Object>{});

  TextEditingController _controllerFor(AddonSection section, String option) =>
      _controllers.putIfAbsent(
        '${section.name}.$option',
        () => TextEditingController(text: section.text(option)),
      );

  List<UciOperation> _plan(AddonSection section) => AddonPlanner.plan(
    spec: widget.spec,
    current: section,
    edited: _editsFor(section.name),
  );

  bool _valid(AddonSection section) {
    final edits = _editsFor(section.name);
    for (final field in widget.spec.fields) {
      if (field is! AddonNumber) continue;
      final value = edits[field.option];
      if (value is String && !AddonPlanner.validNumber(field, value)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _save(AddonSection section) async {
    final ops = _plan(section);
    if (ops.isEmpty || _busy) return;

    setState(() => _busy = true);
    try {
      final outcome = await runApply(
        context,
        work: (progress) => ref
            .read(addonMutationsProvider)
            .apply(widget.spec, ops, onPhase: progress.update),
      );
      if (outcome?.phase == ApplyPhase.confirmed) {
        // The saved values are now the router's, so the form is clean again.
        _edits.remove(section.name);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spec = widget.spec;
    final gate = ref.watch(featureProvider(AddonCatalog.feature(spec.addon)));
    final async = ref.watch(addonProvider(spec));

    // iOS lays an add-on's settings out as grouped rows, on the grouped
    // background.
    final grouped = PlatformUiCapabilities.isIOS
        ? CupertinoColors.systemGroupedBackground.resolveFrom(context)
        : null;
    return Scaffold(
      backgroundColor: grouped,
      appBar: LuciAppBar(
        title: l10n.string(spec.titleKey),
        showBack: true,
        backgroundColor: grouped?.withValues(alpha: 0.94),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(addonProvider(spec)),
        child: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(LuciSpacing.md),
            child: LuciCardSkeleton(contentLines: 5),
          ),
          error: (error, _) => LuciMessageState(
            message: gate.explain(context) ?? apiErrorText(context, error),
            action: l10n.retry,
            onAction: () => ref.invalidate(addonProvider(spec)),
          ),
          data: (sections) {
            if (sections.isEmpty) {
              return LuciMessageState(
                message: gate.explain(context) ?? l10n.addonNotConfigured,
              );
            }
            final selected = sections.firstWhere(
              (s) => s.name == _selectedSection,
              orElse: () => sections.first,
            );
            return _Form(
              spec: spec,
              sections: sections,
              section: selected,
              editable: gate.available && !_busy,
              gateHint: gate.explain(context),
              dirty: _plan(selected).isNotEmpty,
              valid: _valid(selected),
              edits: _editsFor(selected.name),
              controllerFor: _controllerFor,
              onSelect: (s) => setState(() => _selectedSection = s.name),
              onChanged: () => setState(() {}),
              onSave: () => _save(selected),
            );
          },
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.spec,
    required this.sections,
    required this.section,
    required this.editable,
    required this.gateHint,
    required this.dirty,
    required this.valid,
    required this.edits,
    required this.controllerFor,
    required this.onSelect,
    required this.onChanged,
    required this.onSave,
  });

  final AddonSpec spec;
  final List<AddonSection> sections;
  final AddonSection section;
  final bool editable;
  final String? gateHint;
  final bool dirty;
  final bool valid;
  final Map<String, Object> edits;
  final TextEditingController Function(AddonSection, String) controllerFor;
  final ValueChanged<AddonSection> onSelect;
  final VoidCallback onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ListView(
      padding: const EdgeInsets.all(LuciSpacing.md),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Text(
          l10n.string(spec.subtitleKey),
          style: LuciTextStyles.cardSubtitle(context),
        ),
        const SizedBox(height: LuciSpacing.md),
        if (gateHint != null) ...[
          LuciCardStyles.standardCardWrapper(
            context: context,
            padding: const EdgeInsets.all(LuciSpacing.md),
            child: Text(gateHint!, style: LuciTextStyles.cardSubtitle(context)),
          ),
          const SizedBox(height: LuciSpacing.md),
        ],
        // Only shown when there is a choice to make; a single queue or a
        // single service should not look like a picker.
        if (!spec.singleSection && sections.length > 1) ...[
          AdaptiveSegmentedControl(
            labels: [for (final s in sections) s.label],
            selectedIndex: sections.indexWhere((s) => s.name == section.name),
            onValueChanged: (index) => onSelect(sections[index]),
          ),
          const SizedBox(height: LuciSpacing.md),
        ],
        for (final field in spec.fields) ...[
          _FieldTile(
            field: field,
            section: section,
            edits: edits,
            editable: editable,
            controllerFor: controllerFor,
            onChanged: onChanged,
          ),
          const SizedBox(height: LuciSpacing.sm),
        ],
        const SizedBox(height: LuciSpacing.md),
        AdaptiveButton(
          onPressed: editable && dirty && valid ? onSave : null,
          label: l10n.save,
        ),
      ],
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.field,
    required this.section,
    required this.edits,
    required this.editable,
    required this.controllerFor,
    required this.onChanged,
  });

  final AddonField field;
  final AddonSection section;
  final Map<String, Object> edits;
  final bool editable;
  final TextEditingController Function(AddonSection, String) controllerFor;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = l10n.string(field.labelKey);
    final help = field.helpKey == null ? null : l10n.string(field.helpKey!);

    if (PlatformUiCapabilities.isIOS) {
      // A group each, so each setting's explanation sits under it, as iOS
      // Settings explains an option.
      final row = _iosRow(context, label, help);
      if (row != null) return AdaptiveFormSection(children: [row]);
    }

    switch (field) {
      case AddonSwitch():
        final value =
            edits[field.option] as bool? ?? section.flag(field.option);
        return LuciCardStyles.standardCardWrapper(
          context: context,
          padding: EdgeInsets.zero,
          child: AdaptiveSwitchListTile(
            title: Text(label),
            subtitle: help == null ? null : Text(help),
            value: value,
            onChanged: editable
                ? (v) {
                    edits[field.option] = v;
                    onChanged();
                  }
                : null,
          ),
        );

      case final AddonNumber field:
        final controller = controllerFor(section, field.option);
        final text = (edits[field.option] as String?) ?? controller.text;
        final bad = !AddonPlanner.validNumber(field, text);
        return TextField(
          controller: controller,
          enabled: editable,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) {
            edits[field.option] = v;
            onChanged();
          },
          decoration: InputDecoration(
            labelText: label,
            helperText: help,
            helperMaxLines: 2,
            suffixText: field.suffix,
            errorText: bad ? l10n.addonOutOfRange(field.min, field.max) : null,
            border: const OutlineInputBorder(),
          ),
        );

      case final AddonText field:
        final controller = controllerFor(section, field.option);
        return TextField(
          controller: controller,
          enabled: editable,
          obscureText: field.obscure,
          onChanged: (v) {
            edits[field.option] = v;
            onChanged();
          },
          decoration: InputDecoration(
            labelText: label,
            helperText: help,
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
        );

      case final AddonChoice field:
        final current =
            (edits[field.option] as String?) ?? section.text(field.option);
        return DropdownButtonFormField<String>(
          initialValue: field.values.contains(current) ? current : null,
          decoration: InputDecoration(
            labelText: label,
            helperText: help,
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final v in field.values)
              DropdownMenuItem(value: v, child: Text(v)),
          ],
          onChanged: editable
              ? (v) {
                  if (v == null) return;
                  edits[field.option] = v;
                  onChanged();
                }
              : null,
        );

      case final AddonMultiChoice field:
        final current = Set<String>.from(
          (edits[field.option] as List<String>?) ?? section.list(field.option),
        );
        return LuciCardStyles.standardCardWrapper(
          context: context,
          padding: const EdgeInsets.symmetric(vertical: LuciSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  LuciSpacing.md,
                  LuciSpacing.sm,
                  LuciSpacing.md,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: LuciTextStyles.cardTitle(context)),
                    if (help != null)
                      Text(help, style: LuciTextStyles.cardSubtitle(context)),
                  ],
                ),
              ),
              for (final v in field.values)
                AdaptiveCheckboxListTile(
                  dense: true,
                  title: Text(v),
                  value: current.contains(v),
                  onChanged: editable
                      ? (on) {
                          final next = Set<String>.from(current);
                          if (on) {
                            next.add(v);
                          } else {
                            next.remove(v);
                          }
                          edits[field.option] = next.toList()..sort();
                          onChanged();
                        }
                      : null,
                ),
            ],
          ),
        );
    }
  }

  /// The field as a grouped row on iOS, or null for one that keeps its own
  /// layout there (a list of choices to tick).
  Widget? _iosRow(BuildContext context, String label, String? help) {
    final l10n = context.l10n;
    switch (field) {
      case AddonSwitch():
        return AdaptiveFormSwitch(
          label: label,
          description: help,
          value: edits[field.option] as bool? ?? section.flag(field.option),
          onChanged: editable
              ? (v) {
                  edits[field.option] = v;
                  onChanged();
                }
              : null,
        );
      case final AddonNumber field:
        final controller = controllerFor(section, field.option);
        final text = (edits[field.option] as String?) ?? controller.text;
        return AdaptiveFormTextField(
          label: label,
          controller: controller,
          enabled: editable,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          helper: help,
          error: AddonPlanner.validNumber(field, text)
              ? null
              : l10n.addonOutOfRange(field.min, field.max),
          suffix: field.suffix == null
              ? null
              : Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6, end: 12),
                  child: Text(
                    field.suffix!,
                    style: TextStyle(
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                ),
          onChanged: (v) {
            edits[field.option] = v;
            onChanged();
          },
        );
      case final AddonText field:
        return AdaptiveFormTextField(
          label: label,
          controller: controllerFor(section, field.option),
          enabled: editable,
          obscureText: field.obscure,
          helper: help,
          onChanged: (v) {
            edits[field.option] = v;
            onChanged();
          },
        );
      case final AddonChoice field:
        final current =
            (edits[field.option] as String?) ?? section.text(field.option);
        return AdaptiveFormPicker<String>(
          label: label,
          value: current,
          helper: help,
          choices: [for (final v in field.values) AdaptiveFormChoice(v, v)],
          onChanged: editable
              ? (v) {
                  if (v == null) return;
                  edits[field.option] = v;
                  onChanged();
                }
              : null,
        );
      case AddonMultiChoice():
        return null;
    }
  }
}
