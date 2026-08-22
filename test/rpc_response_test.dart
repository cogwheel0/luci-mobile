import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/api_service.dart';

void main() {
  test('missing luci-rpc package produces an actionable error', () {
    expect(
      () => validateRpcResult([4], object: 'luci-rpc', method: 'getDHCPLeases'),
      throwsA(
        isA<RpcException>().having(
          (error) => error.toString(),
          'message',
          contains('Install rpcd-mod-luci'),
        ),
      ),
    );
  });

  test('missing iwinfo package produces an actionable error', () {
    expect(
      () => validateRpcResult([3], object: 'iwinfo', method: 'assoclist'),
      throwsA(
        isA<RpcException>().having(
          (error) => error.toString(),
          'message',
          contains('Install rpcd-mod-iwinfo'),
        ),
      ),
    );
  });

  test('permission denial identifies the blocked action', () {
    expect(
      () => validateRpcResult([6], object: 'system', method: 'reboot'),
      throwsA(
        isA<RpcException>().having(
          (error) => error.toString(),
          'message',
          contains('permission for system.reboot'),
        ),
      ),
    );
  });

  test('access response distinguishes admin and view-only sessions', () {
    expect(
      rpcAccessAllowed([
        0,
        {'access': true},
      ]),
      isTrue,
    );
    expect(
      rpcAccessAllowed([
        0,
        {'access': false},
      ]),
      isFalse,
    );
    expect(rpcAccessAllowed([0, {}]), isNull);
  });
}
