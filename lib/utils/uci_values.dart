import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/state/router_session.dart';

/// Reading UCI values, whatever shape they arrive in.
///
/// One home for the parsing every planner and screen needs: envelopes,
/// lists, booleans, and the one hostname rule dnsmasq enforces.

/// Reads and unwraps one config: `uci.get` for [config] on [session].
Future<Map<String, dynamic>> uciConfigValues(
  IApiService api,
  RouterSession session,
  String config,
) async => uciValuesOf(
  await api.uciGetAll(
    session.ipAddress,
    session.sysauth,
    session.useHttps,
    config: config,
  ),
  config: config,
);

/// The `values` map out of a `uci.get` envelope (`[status, {values: {...}}]`).
///
/// One place, because every screen that reads a config had grown its own
/// copy of this. Anything that is not an envelope at all reads as empty; the
/// body itself goes through [uciSectionsOf].
Map<String, dynamic> uciValuesOf(dynamic envelope, {String? config}) {
  if (envelope is! List || envelope.length < 2) return const {};
  return uciSectionsOf(envelope[1], config: config);
}

/// The sections out of a `uci.get` body.
///
/// rpcd puts them under `values`; the reviewer-mode fixtures put them under
/// the config's own name, which is [config]; some builds return them bare.
Map<String, dynamic> uciSectionsOf(dynamic body, {String? config}) {
  if (body is! Map) return const {};
  final values = body['values'];
  if (values is Map) return Map<String, dynamic>.from(values);
  if (config != null && body[config] is Map) {
    return Map<String, dynamic>.from(body[config] as Map);
  }
  return Map<String, dynamic>.from(body);
}

/// A UCI option as text: trimmed, null when absent or empty, a list joined
/// with spaces (which is how UCI itself writes a list into a single line).
String? uciText(dynamic v) {
  if (v == null) return null;
  if (v is List) {
    return v.isEmpty ? null : v.map((e) => e.toString()).join(' ');
  }
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Sections of one `.type` out of a `uci.get` `values` map.
Iterable<MapEntry<String, Map<String, dynamic>>> uciSections(
  Map<String, dynamic> values,
  String type,
) sync* {
  for (final entry in values.entries) {
    final section = entry.value;
    if (section is! Map) continue;
    if (section['.type'] != type) continue;
    yield MapEntry(entry.key, Map<String, dynamic>.from(section));
  }
}

/// A UCI list option: a real list, or one string of space-separated
/// entries, depending on how it was written and which RPC read it.
List<String> uciList(dynamic v) {
  if (v == null) return const [];
  if (v is List) return [for (final e in v) e.toString()];
  return v.toString().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
}

/// A UCI boolean option. UCI accepts several spellings on each side
/// (`1`/`yes`/`on`/`true`/`enabled` and `0`/`no`/`off`/`false`/
/// `disabled`); anything unrecognised, or absent, reads as [orElse].
bool uciBool(dynamic v, {bool orElse = false}) {
  // Through [uciText], so an option rpcd hands back as a one-element list
  // reads the same as the bare value - which is what the three private
  // helpers this replaced all did.
  final s = uciText(v)?.toLowerCase();
  if (s == null) return orElse;
  return switch (s) {
    '1' || 'yes' || 'on' || 'true' || 'enabled' => true,
    '0' || 'no' || 'off' || 'false' || 'disabled' => false,
    _ => orElse,
  };
}

/// dnsmasq requires a valid DNS label. A name with a space or underscore
/// makes it fail to start, which takes LAN DNS down — and because the router
/// stays *reachable*, `uci.apply`'s rollback timer will not catch it. The
/// same rule holds for the router's own hostname.
final RegExp hostnamePattern = RegExp(
  r'^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
);

bool isValidHostname(String name) => hostnamePattern.hasMatch(name);
