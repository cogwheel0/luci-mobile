import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/system_details.dart';
import 'package:luci_mobile/services/api_service.dart';

void main() {
  // #14: what LuCI's Status > Overview shows, from the `system board` reply
  // the dashboard already fetches.
  group('system details', () {
    test('every field the router reports, in LuCI order', () {
      final rows = SystemDetail.of({
        'hostname': 'gateway',
        'model': 'TP-Link Archer C7 v5',
        'system': 'Qualcomm Atheros QCA956X ver 1 rev 0',
        'kernel': '6.6.73',
        'release': {
          'target': 'ath79/generic',
          'description': 'OpenWrt 24.10.0 r28427-6df0e3d02a',
        },
      });
      expect(rows, [
        (SystemDetail.hostname, 'gateway'),
        (SystemDetail.model, 'TP-Link Archer C7 v5'),
        (SystemDetail.architecture, 'Qualcomm Atheros QCA956X ver 1 rev 0'),
        (SystemDetail.target, 'ath79/generic'),
        (SystemDetail.firmware, 'OpenWrt 24.10.0 r28427-6df0e3d02a'),
        (SystemDetail.kernel, '6.6.73'),
      ]);
    });

    test('missing or blank fields are left out, not shown empty', () {
      expect(
        SystemDetail.of({'model': 'x86/64', 'kernel': '  ', 'release': 'odd'}),
        [(SystemDetail.model, 'x86/64')],
      );
      expect(SystemDetail.of(null), isEmpty);
    });
  });

  // #10: the peer's name, allowed IPs and traffic were dropped on parsing.
  group('WireGuard peer', () {
    test('name, allowed IPs and transfer are kept', () {
      final peer = RealApiService.wireGuardPeer('key=', {
        'name': ' laptop ',
        'endpoint': '203.0.113.7:51820',
        'allowed_ips': ['10.0.0.2/32', 'fd00::2/128'],
        'latest_handshake': '1762850000',
        'transfer_rx': 1048576,
        'transfer_tx': '2048',
      });
      expect(peer['public_key'], 'key=');
      expect(peer['name'], 'laptop');
      expect(peer['allowed_ips'], ['10.0.0.2/32', 'fd00::2/128']);
      expect(peer['last_handshake'], 1762850000);
      expect(peer['transfer_rx'], 1048576);
      expect(peer['transfer_tx'], 2048);
    });

    // An older LuCI, or a peer with no description, sends less.
    test('what the router leaves out is left out', () {
      final peer = RealApiService.wireGuardPeer('key=', {
        'name': '',
        'allowed_ips': ['(none)'],
      });
      expect(peer.containsKey('name'), isFalse);
      expect(peer['allowed_ips'], isEmpty);
      expect(peer.containsKey('transfer_rx'), isFalse);
      expect(peer['endpoint'], 'N/A');
      expect(peer['last_handshake'], 0);
    });
  });
}
