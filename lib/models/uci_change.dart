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
  String get sectionId => sectionIdOf(config, section);

  /// The [sectionId] a row on [section] of [config] would carry.
  static String sectionIdOf(String config, String section) =>
      '$config|$section';

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

  /// True when [section] of [config] is a live uncommitted add in this set.
  bool hasAdd(String config, String section) =>
      liveAdds(config).containsKey(section);

  /// The sections that are live uncommitted adds of [type] in [config].
  List<String> addedSections(String config, String type) => [
    for (final e in liveAdds(config).entries)
      if (e.value == type) e.key,
  ];

  /// Section -> type for every add in [config] that no later row removed.
  ///
  /// libuci keeps the `add` and its options in the delta when the section
  /// is deleted again, and appends a `remove`; only the last word counts.
  Map<String, String> liveAdds(String config) {
    final live = <String, String>{};
    for (final c in forConfig(config)) {
      if (c.op == UciOp.add) {
        live[c.section] = c.option ?? '';
      } else if (c.op == UciOp.remove && c.option == null) {
        live.remove(c.section);
      }
    }
    return live;
  }

  /// The subset of this changeset that this operation did not stage.
  ///
  /// A row counts as foreign when it is in a config the operation never
  /// touched, or when it was already staged before the operation began —
  /// [baseline] captured just before staging. Without the baseline every
  /// row in our configs is suspect, and only the ones the operation itself
  /// accounts for pass: a stray row in a config we happen to be editing must
  /// not be committed along with it.
  ///
  /// Two things make a baseline row ours rather than foreign, both from the
  /// staging step: [writtenKeys], the rows this operation itself wrote
  /// (`uci.changes` keeps one row per option, so ours has replaced the old
  /// one), and [ownedSections], the [UciChange.sectionId]s of sections this
  /// operation created, adopted, or edited while they were still uncommitted
  /// adds. An uncommitted section in our own rpcd session can only be this
  /// app's earlier attempt at the same edit — one whose failed apply could
  /// not be reverted, because the stock ACL denies `uci.revert` — so once
  /// the planner edits it, its `add` row and the options it carried are ours
  /// too. A leftover option on a *committed* section is not covered by
  /// either: editing `dhcp.lan.start` must not silently commit a stale
  /// `dhcp.lan.leasetime` from an unrelated earlier failure.
  UciChangeSet foreignTo(
    Set<String> ours, {
    UciChangeSet? baseline,
    Set<String> writtenKeys = const {},
    Set<String> ownedSections = const {},
  }) {
    final out = <String, List<UciChange>>{};
    for (final entry in byConfig.entries) {
      if (!ours.contains(entry.key)) {
        if (entry.value.isNotEmpty) out[entry.key] = entry.value;
        continue;
      }
      final before = baseline == null
          ? null
          : {for (final c in baseline.forConfig(entry.key)) c.key};
      final stale = [
        for (final change in entry.value)
          if ((before == null || before.contains(change.key)) &&
              !writtenKeys.contains(change.key) &&
              !ownedSections.contains(change.sectionId))
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

  /// The [UciChange.key]s this operation shows up as once staged. Empty for
  /// [UciAdd], whose section is only known once the router has named it;
  /// the whole section is owned instead.
  Set<String> get writtenKeys => const {};

  String _keyOf(UciOp op, String section, [String? option]) =>
      UciChange(op: op, config: config, section: section, option: option).key;
}

/// Assigns options on an existing section.
final class UciSet extends UciOperation {
  const UciSet(super.config, {required this.section, required this.values});
  final String section;
  final Map<String, String> values;

  @override
  Set<String> get writtenKeys => {
    for (final option in values.keys) _keyOf(UciOp.set, section, option),
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
  Set<String> get writtenKeys => {
    _keyOf(UciOp.remove, section, option),
    _keyOf(UciOp.listAdd, section, option),
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
    this.identity = const [],
  });
  final String type;
  final Map<String, dynamic> values;
  final String? name;

  /// The options that say which thing this section is about - the MAC of
  /// a reservation, the SSID and radio of a network. An anonymous add whose
  /// earlier attempt was left staged by a failed apply is recognised by
  /// these, so the retry replaces it instead of adding a duplicate. Empty
  /// means no such recognition; a leftover then stands in the way of the
  /// apply, which names it.
  final List<String> identity;
}

/// Removes a whole section, or one [option] of it.
final class UciRemove extends UciOperation {
  const UciRemove(super.config, {required this.section, this.option});
  final String section;
  final String? option;

  @override
  Set<String> get writtenKeys => {_keyOf(UciOp.remove, section, option)};
}
