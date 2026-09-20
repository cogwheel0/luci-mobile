import 'package:flutter/foundation.dart';

/// An init.d service, as `rc.list` reports it.
@immutable
class ServiceStatus {
  const ServiceStatus({
    required this.name,
    required this.enabled,
    required this.running,
    this.start,
    this.stop,
  });

  final String name;

  /// Starts at boot.
  final bool enabled;

  /// Running right now, or null when the router did not say.
  ///
  /// `rc.list` omits `running` for one-shot boot scripts like `boot` and
  /// `done`, which have no daemon to report on. Measured on OpenWrt 24.10:
  /// 2 of 23 services. Collapsing that to false would label a script that
  /// completed successfully as stopped, so it stays a third state.
  final bool? running;

  final int? start;
  final int? stop;

  static ServiceStatus fromJson(String name, Map<String, dynamic> json) =>
      ServiceStatus(
        name: name,
        enabled: json['enabled'] == true,
        running: json['running'] is bool ? json['running'] as bool : null,
        start: (json['start'] as num?)?.toInt(),
        stop: (json['stop'] as num?)?.toInt(),
      );
}
