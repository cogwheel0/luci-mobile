import 'package:flutter/foundation.dart';

import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/state/router_session.dart';

/// A network tool the router can run on the user's behalf.
enum DiagnosticTool {
  ping('/bin/ping'),
  traceroute('/usr/bin/traceroute'),
  nslookup('/usr/bin/nslookup');

  const DiagnosticTool(this.path);

  /// Absolute path, because rpcd's `file.exec` resolves nothing.
  final String path;
}

@immutable
class DiagnosticResult {
  const DiagnosticResult({
    required this.output,
    required this.exitCode,
    this.stderr,
  });

  final String output;
  final int exitCode;
  final String? stderr;

  bool get succeeded => exitCode == 0;
}

/// Runs the router's own network tools and reads its logs.
class DiagnosticsService {
  const DiagnosticsService(this._api);

  final IApiService _api;

  /// Arguments for [tool] against [target].
  ///
  /// Counts and deadlines are bounded on purpose: `file.exec` is synchronous
  /// and rpcd times it out, so an unbounded `ping` would hang the call and
  /// return nothing at all.
  static List<String> argsFor(DiagnosticTool tool, String target) =>
      switch (tool) {
        DiagnosticTool.ping => ['-c', '5', '-W', '2', target],
        DiagnosticTool.traceroute => [
          '-n',
          '-w',
          '1',
          '-q',
          '1',
          '-m',
          '15',
          target,
        ],
        DiagnosticTool.nslookup => [target],
      };

  Future<DiagnosticResult> run(
    RouterSession session,
    DiagnosticTool tool,
    String target,
  ) async {
    final result = await _api.systemExec(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      command: tool.path,
      params: argsFor(tool, target),
    );
    return _parseExec(result);
  }

  /// Reads the kernel ring buffer.
  Future<DiagnosticResult> kernelLog(RouterSession session) async {
    final result = await _api.systemExec(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      command: '/bin/dmesg',
    );
    return _parseExec(result);
  }

  /// Reads the system log.
  ///
  /// `logread` talks to ubus itself, and on some builds doing that from inside
  /// an `file.exec` — which is already a ubus call — deadlocks until rpcd
  /// times out. Callers must be ready for this to fail and say so rather than
  /// showing an empty log as if the router had nothing to report.
  Future<DiagnosticResult> systemLog(
    RouterSession session, {
    int lines = 200,
  }) async {
    final result = await _api.systemExec(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      command: '/sbin/logread',
      params: ['-l', '$lines'],
    );
    return _parseExec(result);
  }

  static DiagnosticResult _parseExec(dynamic raw) {
    // systemExec already throws on a non-zero exit, so anything arriving here
    // ran; still parse defensively because the envelope shape varies.
    if (raw is! List || raw.length < 2 || raw[1] is! Map) {
      return const DiagnosticResult(output: '', exitCode: -1);
    }
    final data = raw[1] as Map;
    return DiagnosticResult(
      output: data['stdout']?.toString() ?? '',
      exitCode: (data['code'] as num?)?.toInt() ?? 0,
      stderr: data['stderr']?.toString(),
    );
  }
}

/// One parsed syslog line.
@immutable
class LogEntry {
  const LogEntry({
    required this.raw,
    this.timestamp,
    this.facility,
    this.level,
    this.message,
  });

  final String raw;
  final String? timestamp;
  final String? facility;
  final String? level;
  final String? message;

  /// True for anything the user would want to notice.
  bool get isProblem {
    final l = level?.toLowerCase();
    return l == 'err' || l == 'crit' || l == 'alert' || l == 'emerg';
  }

  bool get isWarning => level?.toLowerCase() == 'warn';

  /// Parses `Sun Sep 20 08:53:53 2026 daemon.notice netifd: ...`.
  ///
  /// Anything that does not match is kept verbatim rather than dropped: a log
  /// viewer that silently hides lines it cannot parse is worse than useless
  /// when you are chasing a problem.
  static LogEntry parse(String line) {
    final match = RegExp(
      r'^(\w{3}\s+\w{3}\s+\d+\s+[\d:]+\s+\d{4})\s+(\w+)\.(\w+)\s+(.*)$',
    ).firstMatch(line);
    if (match == null) return LogEntry(raw: line, message: line);
    return LogEntry(
      raw: line,
      timestamp: match.group(1),
      facility: match.group(2),
      level: match.group(3),
      message: match.group(4),
    );
  }

  static List<LogEntry> parseAll(String output) => [
    for (final line in output.split('\n'))
      if (line.trim().isNotEmpty) parse(line),
  ];
}
