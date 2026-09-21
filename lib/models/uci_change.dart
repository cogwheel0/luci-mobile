import 'package:flutter/foundation.dart';

/// The operations rpcd reports in a `uci.changes` row.
enum UciOp {
  add,
  set,
  remove,
  listAdd,
  listDel,
  order,
  rename;

  static UciOp? fromWire(String raw) {
    switch (raw) {
      case 'add':
        return UciOp.add;
      case 'set':
        return UciOp.set;
      case 'remove':
        return UciOp.remove;
      case 'list-add':
        return UciOp.listAdd;
      case 'list-del':
        return UciOp.listDel;
      case 'order':
        return UciOp.order;
      case 'rename':
        return UciOp.rename;
      default:
        return null;
    }
  }
}

/// One staged-but-unapplied change, as reported by `uci.changes`.
///
/// Row shapes rpcd emits:
/// - `["add", section, type]` — a new section
/// - `["set", section, option, value]` — an option assignment
/// - `["remove", section]` — a whole section
/// - `["remove", section, option]` — a single option
@immutable
class UciChange {
  const UciChange({
    required this.op,
    required this.config,
    required this.section,
    this.option,
    this.value,
  });

  final UciOp op;
  final String config;
  final String section;
  final String? option;
  final String? value;

  /// Identifies the row independently of the value it carries.
  ///
  /// Ownership has to be decided per row, not per config: a change left
  /// staged in `dhcp` by an earlier failed operation is not ours just
  /// because this operation also touches `dhcp`. The config is part of the
  /// key for the same reason: `network.lan.ipaddr` and `dhcp.lan.ipaddr`
  /// are different rows.
  String get key => '$config|${op.name}|$section|${option ?? ""}';

  /// The section this row belongs to, qualified by config.
  String get sectionId => '$config|$section';

  /// Parses one wire row, or returns null when the row is malformed or uses an
  /// operation this version does not model.
  static UciChange? fromWire(String config, List<String> row) {
    if (row.isEmpty) return null;
    final op = UciOp.fromWire(row[0]);
    if (op == null || row.length < 2) return null;
    return UciChange(
      op: op,
      config: config,
      section: row[1],
      option: row.length > 2 ? row[2] : null,
      value: row.length > 3 ? row[3] : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UciChange &&
          other.op == op &&
          other.config == config &&
          other.section == section &&
          other.option == option &&
          other.value == value;

  @override
  int get hashCode => Object.hash(op, config, section, option, value);

  @override
  String toString() =>
      'UciChange(${op.name} $config.$section'
      '${option == null ? '' : '.$option'}'
      '${value == null ? '' : '=$value'})';
}

/// Everything currently staged on a router, grouped by config.
///
/// Note that `uci.apply` is global: applying commits *all* of this, including
/// changes staged by another client such as an open LuCI browser tab.
@immutable
class UciChangeSet {
  const UciChangeSet({required this.byConfig, required this.fetchedAt});

  const UciChangeSet.empty()
    : byConfig = const <String, List<UciChange>>{},
      fetchedAt = null;

  final Map<String, List<UciChange>> byConfig;
  final DateTime? fetchedAt;

  bool get isEmpty => byConfig.values.every((rows) => rows.isEmpty);

  bool get isNotEmpty => !isEmpty;

  int get count => byConfig.values.fold(0, (sum, rows) => sum + rows.length);

  Set<String> get configs => byConfig.entries
      .where((e) => e.value.isNotEmpty)
      .map((e) => e.key)
      .toSet();

  List<UciChange> forConfig(String config) =>
      byConfig[config] ?? const <UciChange>[];

  /// The subset of this changeset that this operation did not stage.
  ///
  /// A row counts as foreign when it is in a config the operation never
  /// touched, or when it was already staged before the operation began —
  /// [baseline] captured just before staging. Without the baseline, a stray
  /// row in a config we happen to be editing would be treated as ours and
  /// committed along with it.
  ///
  /// [writtenSections] holds the [UciChange.sectionId]s this operation wrote
  /// to. Staging is per rpcd session, so a baseline row on a section we are
  /// writing again is our own earlier attempt at the same edit — one whose
  /// failed apply could not be reverted, because the stock ACL denies
  /// `uci.revert`. Refusing it would leave that edit impossible to retry
  /// from the app. Ownership is per section rather than per option because
  /// the retry does not always repeat the same rows: once the router shows
  /// the staged section, the planner edits it instead of adding it again.
  UciChangeSet foreignTo(
    Set<String> ours, {
    UciChangeSet? baseline,
    Set<String> writtenSections = const {},
  }) {
    final out = <String, List<UciChange>>{};
    for (final entry in byConfig.entries) {
      if (!ours.contains(entry.key)) {
        if (entry.value.isNotEmpty) out[entry.key] = entry.value;
        continue;
      }
      if (baseline == null) continue;
      final before = {for (final c in baseline.forConfig(entry.key)) c.key};
      final stale = [
        for (final change in entry.value)
          if (before.contains(change.key) &&
              !writtenSections.contains(change.sectionId))
            change,
      ];
      if (stale.isNotEmpty) out[entry.key] = stale;
    }
    return UciChangeSet(byConfig: out, fetchedAt: fetchedAt);
  }

  static UciChangeSet fromWire(
    Map<String, List<List<String>>> raw, {
    DateTime? fetchedAt,
  }) {
    final byConfig = <String, List<UciChange>>{};
    for (final entry in raw.entries) {
      final parsed = <UciChange>[];
      for (final row in entry.value) {
        final change = UciChange.fromWire(entry.key, row);
        if (change != null) parsed.add(change);
      }
      if (parsed.isNotEmpty) byConfig[entry.key] = parsed;
    }
    return UciChangeSet(byConfig: byConfig, fetchedAt: fetchedAt);
  }
}

/// A change the app wants to stage, as opposed to one the router reports.
sealed class UciOperation {
  const UciOperation(this.config);
  final String config;
}

/// Assigns options on an existing section.
final class UciSet extends UciOperation {
  const UciSet(super.config, {required this.section, required this.values});
  final String section;
  final Map<String, String> values;
}

/// Replaces a UCI list option (`list foo 'a'`) wholesale.
///
/// Separate from [UciSet] because a list cannot be emptied by assignment —
/// removing every entry means deleting the option, which is [UciRemove].
final class UciSetList extends UciOperation {
  const UciSetList(
    super.config, {
    required this.section,
    required this.option,
    required this.values,
  });
  final String section;
  final String option;
  final List<String> values;
}

/// Creates a section. When [name] is null the router generates an anonymous
/// section id, which `UciChangesetService.stage` returns to the caller so that
/// later operations in the same batch can reference it.
final class UciAdd extends UciOperation {
  const UciAdd(
    super.config, {
    required this.type,
    required this.values,
    this.name,
  });
  final String type;
  final Map<String, dynamic> values;
  final String? name;
}

/// Removes a whole section, or one [option] of it.
final class UciRemove extends UciOperation {
  const UciRemove(super.config, {required this.section, this.option});
  final String section;
  final String? option;
}
