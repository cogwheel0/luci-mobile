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
  /// [restaged] holds the keys of the rows this operation wrote. A baseline
  /// row with one of those keys has been overwritten by ours — `uci.changes`
  /// keeps one row per option — so it is not foreign. Without this, retrying
  /// an edit whose failed attempt could not be reverted (the stock ACL denies
  /// `uci.revert`) would be refused forever from the app.
  UciChangeSet foreignTo(
    Set<String> ours, {
    UciChangeSet? baseline,
    Set<String> restaged = const {},
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
          if (before.contains(change.key) && !restaged.contains(change.key))
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

  /// The [UciChange.key]s this operation shows up as in `uci.changes` once
  /// staged. An anonymous [UciAdd] only knows its section after the router
  /// has named it, hence [section].
  Set<String> changeKeys({String? section});

  String _key(UciOp op, String section, [String? option]) =>
      '$config|${op.name}|$section|${option ?? ""}';
}

/// Assigns options on an existing section.
final class UciSet extends UciOperation {
  const UciSet(super.config, {required this.section, required this.values});
  final String section;
  final Map<String, String> values;

  @override
  Set<String> changeKeys({String? section}) => {
    for (final option in values.keys)
      _key(UciOp.set, section ?? this.section, option),
  };
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

  // rpcd stages a list assignment as a delete of the option followed by one
  // `list-add` per entry.
  @override
  Set<String> changeKeys({String? section}) => {
    _key(UciOp.remove, section ?? this.section, option),
    _key(UciOp.listAdd, section ?? this.section, option),
  };
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

  @override
  Set<String> changeKeys({String? section}) {
    final id = section ?? name;
    if (id == null) return const {};
    // rpcd reports the add row as `["add", section, type]`, so the type
    // sits where an option would.
    return {
      _key(UciOp.add, id, type),
      for (final option in values.keys) _key(UciOp.set, id, option),
    };
  }
}

/// Removes a whole section, or one [option] of it.
final class UciRemove extends UciOperation {
  const UciRemove(super.config, {required this.section, this.option});
  final String section;
  final String? option;

  @override
  Set<String> changeKeys({String? section}) => {
    _key(UciOp.remove, section ?? this.section, option),
  };
}
