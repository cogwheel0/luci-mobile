import 'package:flutter/foundation.dart';

import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/state/router_session.dart';

/// A network tool the router can run on the user's behalf.
enum DiagnosticTool {
  ping(['/bin/ping', '/usr/bin/ping']),
  traceroute(['/usr/bin/traceroute', '/bin/traceroute', '/usr/sbin/traceroute']),
  nslookup(['/usr/bin/nslookup', '/bin/nslookup']);

  const DiagnosticTool(this.paths);

  /// Absolute paths, tried in order, because rpcd's `file.exec` resolves
  /// nothing and LuCI's ACL lists each tool under the exact path it expects.
  /// Builds differ in where busybox links (or a full package installs) the
  /// binary, so a refusal or "not found" on one path moves on to the next.
  final List<String> paths;

  /// The preferred path.
  String get path => paths.first;
}

/// One way of running a command that rpcd may or may not allow.
typedef _ExecCandidate = ({String command, List<String> params});

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
    final args = argsFor(tool, target);
    return _execFirst(session, [
      for (final path in tool.paths) (command: path, params: args),
    ]);
  }

  /// Reads the kernel ring buffer.
  ///
  /// rpcd matches `file.exec` against LuCI's ACL *including arguments*:
  /// the stock grant is for exactly `/bin/dmesg -r`, so a bare `dmesg` is
  /// refused even for root (GitHub issue #91). `-r` prints raw `<prio>`
  /// prefixes, which [LogEntry.parseKernel] turns into levels.
  Future<DiagnosticResult> kernelLog(RouterSession session) async {
    return _execFirst(session, const [
      (command: '/bin/dmesg', params: ['-r']),
      (command: '/bin/dmesg', params: []),
    ]);
  }

  /// Reads the system log.
  ///
  /// `logread` talks to ubus itself, and on some builds doing that from inside
  /// an `file.exec` — which is already a ubus call — deadlocks until rpcd
  /// times out. Callers must be ready for this to fail and say so rather than
  /// showing an empty log as if the router had nothing to report.
  ///
  /// The commands are tried in the order LuCI itself uses them, because that
  /// is what the router's ACL grants (GitHub issue #91): 23.05+ ships
  /// `/usr/libexec/syslog-wrapper`, older releases grant exactly
  /// `logread -e ^`. Only [lines] of the newest output are kept.
  Future<DiagnosticResult> systemLog(
    RouterSession session, {
    int lines = 500,
  }) async {
    final result = await _execFirst(session, [
      (command: '/usr/libexec/syslog-wrapper', params: const []),
      (command: '/sbin/logread', params: const ['-e', '^']),
      (command: '/usr/sbin/logread', params: const ['-e', '^']),
      (command: '/sbin/logread', params: ['-l', '$lines']),
    ]);
    return DiagnosticResult(
      output: tailLines(result.output, lines),
      exitCode: result.exitCode,
      stderr: result.stderr,
    );
  }

  /// The last [count] non-empty lines of [output].
  @visibleForTesting
  static String tailLines(String output, int count) {
    final all = output.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (all.length <= count) return all.join('\n');
    return all.sublist(all.length - count).join('\n');
  }

  /// Runs the first of [candidates] the router lets this session run.
  ///
  /// Moves on only when a candidate is refused or missing; any other
  /// failure (timeout, dead session) is the answer and is rethrown at once.
  Future<DiagnosticResult> _execFirst(
    RouterSession session,
    List<_ExecCandidate> candidates,
  ) async {
    RpcException? last;
    for (final c in candidates) {
      try {
        return await _exec(session, c.command, c.params);
      } on RpcException catch (e) {
        if (!(e.isAccessDenied || e.isUnavailable)) rethrow;
        last = e;
      }
    }
    throw last ??
        const RpcException(object: 'file', method: 'exec', status: 4);
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

  static const _kernelLevels = [
    'emerg',
    'alert',
    'crit',
    'err',
    'warn',
    'notice',
    'info',
    'debug',
  ];

  /// Parses a `dmesg -r` line: `<6>[   12.345678] eth0: link up`.
  ///
  /// Lines without the raw prefix (a plain `dmesg`) still get their uptime
  /// stamp split off; anything else is kept verbatim.
  static LogEntry parseKernel(String line) {
    final match = RegExp(
      r'^(?:<(\d+)>)?\[\s*([\d.]+)\]\s?(.*)$',
    ).firstMatch(line);
    if (match == null) return LogEntry(raw: line, message: line);
    final prio = int.tryParse(match.group(1) ?? '');
    return LogEntry(
      raw: line,
      timestamp: '${match.group(2)}s',
      facility: 'kern',
      level: prio == null ? 'info' : _kernelLevels[prio & 7],
      message: match.group(3),
    );
  }

  static List<LogEntry> parseAllKernel(String output) => [
    for (final line in output.split('\n'))
      if (line.trim().isNotEmpty) parseKernel(line),
  ];
}
