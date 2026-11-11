import 'package:flutter/foundation.dart';

import 'package:luci_mobile/services/api_service.dart';
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
    return _exec(session, tool.path, argsFor(tool, target));
  }

  /// The command lines LuCI itself uses to read the logs.
  ///
  /// rpcd checks `file.exec` against the ACL by the *exact* command line, and
  /// LuCI's ACL (`luci-mod-status-logs`) grants only these. Anything else -
  /// `logread -l 200`, a bare `dmesg` - is refused even for root, so the app
  /// must ask in exactly the same words LuCI does.
  ///
  /// The system log is newest-LuCI first: 24.10 and later ship a wrapper
  /// (which also honours `log_file`) and no longer grant `logread` directly;
  /// 21.02 to 23.05 have no wrapper and grant `logread -e ^` at either path.
  static const systemLogCommands = <(String, List<String>)>[
    ('/usr/libexec/syslog-wrapper', []),
    ('/sbin/logread', ['-e', '^']),
    ('/usr/sbin/logread', ['-e', '^']),
  ];

  /// `-r` keeps the `<priority>` prefixes, which is also the only form the
  /// ACL grants.
  static const kernelLogCommand = ('/bin/dmesg', ['-r']);

  /// Reads the kernel ring buffer.
  Future<DiagnosticResult> kernelLog(RouterSession session) async {
    final (command, params) = kernelLogCommand;
    return _exec(session, command, params);
  }

  /// Reads the last [lines] lines of the system log.
  ///
  /// The ACL grants no form of `logread` that takes a line count, so the
  /// whole buffer is read and trimmed here.
  ///
  /// `logread` talks to ubus itself, and on some builds doing that from inside
  /// an `file.exec` — which is already a ubus call — deadlocks until rpcd
  /// times out. Callers must be ready for this to fail and say so rather than
  /// showing an empty log as if the router had nothing to report.
  Future<DiagnosticResult> systemLog(
    RouterSession session, {
    int lines = 200,
  }) async {
    RpcException? denied;
    RpcException? last;
    for (final (command, params) in systemLogCommands) {
      try {
        final result = await _exec(session, command, params);
        return DiagnosticResult(
          output: lastLines(result.output, lines),
          exitCode: result.exitCode,
          stderr: result.stderr,
        );
      } on RpcException catch (e) {
        // Not installed on this release (4), or not the form this release's
        // ACL grants (6): try the next one. Anything else is a real failure.
        if (!e.isNotFound && !e.isAccessDenied) rethrow;
        last = e;
        if (e.isAccessDenied) denied ??= e;
      }
    }
    // A refusal says more than "not found": it means a log reader exists
    // and this account may not run it.
    throw denied ?? last!;
  }

  /// The last [count] non-empty lines of [output].
  @visibleForTesting
  static String lastLines(String output, int count) {
    final all = output.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (all.length <= count) return all.join('\n');
    return all.sublist(all.length - count).join('\n');
  }

  /// Runs [command] and returns whatever it printed, whatever it exited with.
  ///
  /// Deliberately not `systemExec`, which throws on a non-zero exit: here a
  /// non-zero exit *is* the result. `ping` exits 1 for "100% packet loss"
  /// and `nslookup` for NXDOMAIN, and that output is exactly what the user
  /// ran the tool to see.
  Future<DiagnosticResult> _exec(
    RouterSession session,
    String command,
    List<String> params,
  ) async {
    final raw = await _api.call(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      object: 'file',
      method: 'exec',
      params: {'command': command, 'params': params},
    );
    // `call` has already turned a non-zero ubus status into an RpcException
    // with whatever detail the router sent; only the shape is checked here.
    if (raw is! List || raw.isEmpty) {
      throw const RpcException(
        object: 'file',
        method: 'exec',
        detail: 'invalid response',
      );
    }
    return _parseExec(raw);
  }

  static DiagnosticResult _parseExec(List<dynamic> raw) {
    // The envelope shape varies between rpcd builds; parse defensively.
    if (raw.length < 2 || raw[1] is! Map) {
      return const DiagnosticResult(output: '', exitCode: -1);
    }
    final data = raw[1] as Map;
    final code = data['code'];
    return DiagnosticResult(
      output: data['stdout']?.toString() ?? '',
      // Unknown, not zero: a body carrying no exit status is a run we
      // cannot vouch for, and calling it a success turns "the log could
      // not be read" into "the log is empty".
      exitCode: code is num ? code.toInt() : -1,
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
  ///
  /// Kernel lines from `dmesg -r` (`<4>[  12.3] ...`) carry their syslog
  /// priority as a number; it is decoded so warnings and errors are marked
  /// the same way as in the system log.
  static LogEntry parse(String line) {
    final kernel = RegExp(r'^<(\d+)>(.*)$').firstMatch(line);
    if (kernel != null) {
      final priority = int.parse(kernel.group(1)!);
      final message = kernel.group(2)!;
      return LogEntry(
        raw: message,
        level: _severities[priority & 7],
        message: message,
      );
    }
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

  /// Syslog severity names in the spelling `logread` uses, indexed by level.
  static const _severities = [
    'emerg',
    'alert',
    'crit',
    'err',
    'warn',
    'notice',
    'info',
    'debug',
  ];

  static List<LogEntry> parseAll(String output) => [
    for (final line in output.split('\n'))
      if (line.trim().isNotEmpty) parse(line),
  ];
}
