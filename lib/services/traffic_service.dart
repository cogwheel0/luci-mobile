import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/state/router_session.dart';

/// One host's accounted traffic over a period.
@immutable
class TrafficRow {
  const TrafficRow({
    required this.mac,
    required this.ip,
    required this.connections,
    required this.rxBytes,
    required this.txBytes,
  });

  final String mac;
  final String ip;
  final int connections;
  final int rxBytes;
  final int txBytes;

  int get totalBytes => rxBytes + txBytes;
}

/// Reads nlbwmon's accounting database.
///
/// Goes through `/usr/libexec/nlbwmon-action`, which is the path
/// `luci-app-nlbwmon`'s ACL grants `exec` on — `/usr/sbin/nlbw` itself is
/// **not** granted, so calling the binary directly returns permission
/// denied even as root. Measured on OpenWrt 24.10.
class TrafficService {
  const TrafficService(this._api);

  final IApiService _api;

  static const _action = '/usr/libexec/nlbwmon-action';

  /// The accounting periods the router has kept, newest first.
  Future<List<String>> periods(RouterSession session) async {
    final out = await _exec(session, const ['periods']);
    final decoded = _decode(out);
    final list = decoded is Map ? decoded['periods'] : null;
    if (list is! List) return const [];
    final periods = [for (final p in list) p.toString()];
    periods.sort((a, b) => b.compareTo(a));
    return periods;
  }

  /// Per-host totals for [period].
  Future<List<TrafficRow>> records(RouterSession session, String period) async {
    final out = await _exec(session, [
      'download',
      '-f',
      'json',
      '-t',
      period,
      '-g',
      'mac,ip',
      '-o',
      'rx',
    ]);
    return parseTable(out);
  }

  Future<String> _exec(RouterSession session, List<String> params) async {
    final result = await _api.call(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      object: 'file',
      method: 'exec',
      params: {'command': _action, 'params': params},
    );
    if (result is! List || result.isEmpty) return '';
    if (result.first != 0) {
      throw StateError('nlbwmon-action refused: status ${result.first}');
    }
    final data = result.length > 1 ? result[1] : null;
    if (data is! Map) return '';
    return data['stdout']?.toString() ?? '';
  }

  static Object? _decode(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// Parses nlbwmon's column-oriented table.
  ///
  /// The shape is `{"columns": [...], "data": [[...]]}` — column order is
  /// not fixed, so every value is looked up by name rather than index.
  /// Measured on OpenWrt 24.10:
  /// `["mac","ip","conns","rx_bytes","rx_pkts","tx_bytes","tx_pkts"]`.
  @visibleForTesting
  static List<TrafficRow> parseTable(String raw) {
    final decoded = _decode(raw);
    if (decoded is! Map) return const [];
    final columns = decoded['columns'];
    final data = decoded['data'];
    if (columns is! List || data is! List) return const [];

    final index = <String, int>{
      for (var i = 0; i < columns.length; i++) columns[i].toString(): i,
    };

    String text(List<dynamic> row, String column) {
      final i = index[column];
      if (i == null || i >= row.length) return '';
      return row[i]?.toString() ?? '';
    }

    int number(List<dynamic> row, String column) =>
        int.tryParse(text(row, column)) ?? 0;

    final rows = <TrafficRow>[];
    for (final row in data) {
      if (row is! List) continue;
      rows.add(
        TrafficRow(
          mac: text(row, 'mac').toUpperCase(),
          ip: text(row, 'ip'),
          connections: number(row, 'conns'),
          rxBytes: number(row, 'rx_bytes'),
          txBytes: number(row, 'tx_bytes'),
        ),
      );
    }
    rows.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    return rows;
  }
}
