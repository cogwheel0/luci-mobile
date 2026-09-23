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
    this.subjectKey,
  });

  final RouterEventKind kind;
  final DateTime at;
  final String routerId;

  /// What the event is about — an interface name, a client's name or MAC.
  final String? subject;

  /// The stable identity behind [subject], when there is one: a client's
  /// MAC, where [subject] is the lease name two devices can share. Used to
  /// tell two records of one thing from two things.
  final String? subjectKey;

  /// What this event is about, as precisely as it can be said. An event
  /// with no subject - a reboot, a WAN transition - is about the router,
  /// and its kind is the only thing that distinguishes it from another
  /// such event.
  String get identity => subjectKey ?? subject ?? kind.name;

  EventSeverity get severity => switch (kind) {
    RouterEventKind.routerUnreachable ||
    RouterEventKind.wanDown => EventSeverity.problem,
    RouterEventKind.rebooted ||
    RouterEventKind.clientLeft => EventSeverity.warning,
    _ => EventSeverity.info,
  };

  /// A stable identity, so the same event is not recorded twice when a poll
  /// repeats. On [identity] rather than [subject]: one poll stamps every
  /// event it derives with the same instant, so two devices sharing a lease
  /// name would otherwise collapse into one record - and one notification,
  /// whose id is derived from this.
  String get dedupeKey =>
      '$routerId|${kind.name}|$identity|'
      '${at.millisecondsSinceEpoch ~/ 1000}';

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'at': at.millisecondsSinceEpoch,
    'routerId': routerId,
    if (subject != null) 'subject': subject,
    if (subjectKey != null) 'subjectKey': subjectKey,
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
      subjectKey: json['subjectKey']?.toString(),
    );
  }
}
