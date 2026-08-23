import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/mock_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reviewer DHCP RPC returns parsed leases', () async {
    final result = await MockApiService().callSimple(
      'luci-rpc',
      'getDHCPLeases',
      {},
    );
    final leases = result[1]['dhcp_leases'] as List<dynamic>;

    expect(leases, hasLength(24));
    expect(leases.first['hostname'], 'iPhone-John');
    expect(leases.first['ipaddr'], '192.168.1.100');
  });
}
