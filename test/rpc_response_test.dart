import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('associated stations survive one failing wireless interface', () async {
    final api = _StationApi(
      stations: {
        'wlan0': ['AA:BB:CC:DD:EE:FF'],
        'wlan1': Exception('interface down'),
      },
    );

    final result = await api.fetchAllAssociatedWirelessMacsWithContext(
      ipAddress: 'router',
      sysauth: 'token',
      useHttps: false,
    );

    expect(result['wlan0'], {'AA:BB:CC:DD:EE:FF'});
  });

  test('associated stations fail when every interface fails', () async {
    final api = _StationApi(stations: {'wlan0': Exception('interface down')});

    expect(
      api.fetchAllAssociatedWirelessMacsWithContext(
        ipAddress: 'router',
        sysauth: 'token',
        useHttps: false,
      ),
      throwsException,
    );
  });

  test('associated stations reject an invalid device response', () async {
    final api = _StationApi(stations: {}, wirelessResponse: [0]);

    expect(
      api.fetchAllAssociatedWirelessMacsWithContext(
        ipAddress: 'router',
        sysauth: 'token',
        useHttps: false,
      ),
      throwsA(isA<RpcException>()),
    );
  });
}

class _StationApi extends RealApiService {
  final Map<String, Object> stations;
  final dynamic wirelessResponse;

  _StationApi({required this.stations, this.wirelessResponse});

  @override
  Future<dynamic> callWithContext(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    if (wirelessResponse != null) return wirelessResponse;
    return [
      0,
      {
        'radio0': {
          'interfaces': stations.keys
              .map(
                (ifname) => {
                  'ifname': ifname,
                  'config': {'mode': 'ap'},
                },
              )
              .toList(),
        },
      },
    ];
  }

  @override
  Future<List<String>> fetchAssociatedStationsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    final result = stations[interface]!;
    if (result is Exception) throw result;
    return result as List<String>;
  }
}
