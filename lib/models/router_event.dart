import 'package:flutter/foundation.dart';

enum RouterEventKind {
  routerUnreachable,
  routerBack,
  wanDown,
  wanUp,
  clientJoined,
  clientLeft,
  rebooted,
}

enum EventSeverity { info, warning, problem }

/// Something worth telling the user about, derived from data the app already
/// polls while it is open.
@immutable
class RouterEvent {
  const RouterEvent({
    required this.kind,
    required this.at,
    required this.routerId,
    this.subject,
  });

  final RouterEventKind kind;
  final DateTime at;
  final String routerId;

  /// What the event is about — an interface name, a client's name or MAC.
  final String? subject;

  EventSeverity get severity => switch (kind) {
    RouterEventKind.routerUnreachable ||
    RouterEventKind.wanDown => EventSeverity.problem,
    RouterEventKind.rebooted ||
    RouterEventKind.clientLeft => EventSeverity.warning,
    _ => EventSeverity.info,
  };

  /// A stable identity, so the same event is not recorded twice when a poll
  /// repeats.
  String get dedupeKey =>
      '$routerId|${kind.name}|${subject ?? ""}|${at.millisecondsSinceEpoch ~/ 1000}';

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'at': at.millisecondsSinceEpoch,
    'routerId': routerId,
    if (subject != null) 'subject': subject,
  };

  static RouterEvent? fromJson(Map<String, dynamic> json) {
    final kind = RouterEventKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    final at = json['at'];
    final routerId = json['routerId'];
    if (kind == null || at is! int || routerId is! String) return null;
    return RouterEvent(
      kind: kind,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      routerId: routerId,
      subject: json['subject']?.toString(),
    );
  }
}
