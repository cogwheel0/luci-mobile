/// Parsing and validating IPv4 addresses the way a router will read them.
///
/// Deliberately stricter than `int.tryParse`, which accepts `0x` hex, a
/// leading sign and surrounding whitespace: an address that passes
/// validation here is written straight into UCI, and one dnsmasq rejects
/// stops it from starting - taking LAN DNS with it, while the router itself
/// stays reachable so the apply rollback timer never fires.
library;

final RegExp _octet = RegExp(r'^(0|[1-9][0-9]{0,2})$');

/// The four octets of [raw], or null when it is not a dotted quad.
///
/// Leading zeros are refused rather than guessed at: `010` is 8 to some
/// parsers and 10 to others.
List<int>? parseIpv4(String raw) {
  final parts = raw.trim().split('.');
  if (parts.length != 4) return null;
  final out = <int>[];
  for (final part in parts) {
    if (!_octet.hasMatch(part)) return null;
    final value = int.parse(part);
    if (value > 255) return null;
    out.add(value);
  }
  return out;
}

bool isValidIpv4(String raw) => parseIpv4(raw) != null;
