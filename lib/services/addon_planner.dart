import 'package:flutter/foundation.dart';

import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/models/addon_spec.dart';
import 'package:luci_mobile/models/uci_change.dart';

/// One editable section of an add-on's config.
@immutable
class AddonSection {
  const AddonSection({
    required this.name,
    required this.label,
    required this.values,
  });

  /// The real UCI section name, which writes must target.
  final String name;

  /// What to call it in a list.
  final String label;

  /// option -> value. A list option arrives as `List<String>`.
  final Map<String, Object> values;

  // Through the shared readers, so an add-on option is read exactly as the
  // same option would be on any other screen. The private copies these
  // replaced disagreed with them: a flag rpcd returned as a one-element
  // list read as off here and on everywhere else, and a list joined with
  // commas round-tripped commas back into the config.
  String text(String option) => uciText(values[option]) ?? '';

  bool flag(String option, {bool orElse = false}) =>
      uciBool(values[option], orElse: orElse);

  List<String> list(String option) => uciList(values[option]);
}

/// Reads and writes add-on configs.
///
/// Pure on purpose: every rule here is about UCI's shape, which is testable
/// without a router.
class AddonPlanner {
  const AddonPlanner._();

  /// The sections of [spec]'s type found in a `uci.get` payload.
  static List<AddonSection> sections(
    AddonSpec spec,
    Map<String, dynamic> values,
  ) {
    final out = <AddonSection>[];
    for (final entry in values.entries) {
      final raw = entry.value;
      if (raw is! Map) continue;
      if (raw['.type'] != spec.sectionType) continue;

      final name = (raw['.name'] as String?) ?? entry.key;
      final parsed = <String, Object>{};
      for (final o in raw.entries) {
        final key = o.key.toString();
        if (key.startsWith('.')) continue;
        final v = o.value;
        if (v is List) {
          parsed[key] = [for (final e in v) e.toString()];
        } else if (v != null) {
          parsed[key] = v.toString();
        }
      }

      final labelOption = spec.nameOption;
      final label = labelOption == null
          ? name
          : (parsed[labelOption] is String
                    ? parsed[labelOption] as String
                    : name)
                .trim();
      out.add(
        AddonSection(
          name: name,
          label: label.isEmpty ? name : label,
          values: parsed,
        ),
      );
    }
    out.sort((a, b) => a.label.compareTo(b.label));
    return out;
  }

  /// The operations that turn [current] into [edited].
  ///
  /// Only changed options are emitted: applying a no-op would still run the
  /// whole rollback-protected apply and make the user wait through it.
  static List<UciOperation> plan({
    required AddonSpec spec,
    required AddonSection current,
    required Map<String, Object> edited,
  }) {
    final changed = <String, String>{};
    final lists = <UciOperation>[];

    for (final field in spec.fields) {
      if (!edited.containsKey(field.option)) continue;
      final next = edited[field.option];
      final was = current.values[field.option];

      if (field is AddonMultiChoice) {
        final a = current.list(field.option);
        final b = next is List
            ? [for (final e in next) e.toString()]
            : <String>[];
        if (!listEquals(a, b)) {
          // A list option cannot be set to empty by assignment; the option
          // has to go away, or UCI keeps the old entries.
          lists.add(
            b.isEmpty
                ? UciRemove(
                    spec.config,
                    section: current.name,
                    option: field.option,
                  )
                : UciSetList(
                    spec.config,
                    section: current.name,
                    option: field.option,
                    values: b,
                  ),
          );
        }
        continue;
      }

      final value = _normalise(field, next);
      final before = was is String ? was : '';
      if (value == before) continue;
      changed[field.option] = value;
    }

    return [
      if (changed.isNotEmpty)
        UciSet(spec.config, section: current.name, values: changed),
      ...lists,
    ];
  }

  static String _normalise(AddonField field, Object? value) {
    if (field is AddonSwitch) return value == true ? '1' : '0';
    final text = value?.toString().trim() ?? '';
    // sqm-scripts documents 0 as the way to disable shaping in a direction;
    // an empty or absent option is undefined and can leave the queue
    // half-configured. So a cleared number field writes the value that
    // actually means "none" rather than a blank.
    if (field is AddonNumber && text.isEmpty) return '0';
    return text;
  }

  /// Whether [value] is a number the field will accept.
  static bool validNumber(AddonNumber field, String value) {
    if (value.trim().isEmpty) return true;
    final n = int.tryParse(value.trim());
    return n != null && n >= field.min && n <= field.max;
  }
}
