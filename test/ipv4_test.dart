import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/utils/ipv4.dart';

void main() {
  test('accepts a dotted quad', () {
    expect(parseIpv4('192.168.1.1'), [192, 168, 1, 1]);
    expect(parseIpv4(' 10.0.0.255 '), [10, 0, 0, 255]);
    expect(parseIpv4('0.0.0.0'), [0, 0, 0, 0]);
  });

  // `int.tryParse` accepts all of these, and the address goes straight into
  // UCI: one dnsmasq rejects stops it from starting, taking LAN DNS with it
  // while the router stays reachable, so no rollback timer catches it.
  test('refuses what only int.tryParse would accept', () {
    for (final bad in [
      '192.168.1.0x10',
      '0xC0.168.1.1',
      '192. 168.1.5',
      '192.168.1.+5',
      '192.168.1.-5',
      '192.168.1.010',
      '192.168.1.1 2',
    ]) {
      expect(parseIpv4(bad), isNull, reason: bad);
      expect(isValidIpv4(bad), isFalse, reason: bad);
    }
  });

  test('refuses malformed quads', () {
    for (final bad in ['', 'nope', '192.168.1', '192.168.1.1.1', '1.2.3.256']) {
      expect(isValidIpv4(bad), isFalse, reason: bad);
    }
  });
}
