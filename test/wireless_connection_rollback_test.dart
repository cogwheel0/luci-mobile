import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';

class _FailingRestartApiService extends MockApiService {
  _FailingRestartApiService({this.failWirelessDelete = false});

  final bool failWirelessDelete;
  final calls = <String>[];

  @override
  Future<dynamic> uciGetAll(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    final values = switch (config) {
      'wireless' => {
        'radio0': {'.type': 'wifi-device'},
      },
      'network' => {
        'lan': {'.type': 'interface'},
      },
      'firewall' => {
        'lan_zone': {'.type': 'zone', 'name': 'lan'},
        'wan_zone': {
          '.type': 'zone',
          'name': 'wan',
          'network': ['wan'],
        },
      },
      _ => <String, dynamic>{},
    };
    return [
      0,
      {'values': values},
    ];
  }

  @override
  Future<dynamic> uciAdd(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String type,
    required Map<String, dynamic> values,
    String? name,
    BuildContext? context,
  }) async {
    calls.add('add $config.$name');
    return [0, name];
  }

  @override
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, String> values,
    BuildContext? context,
  }) async {
    calls.add('set $config.$section $values');
    return [0, {}];
  }

  @override
  Future<dynamic> uciCommit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    calls.add('commit $config');
    return [0, {}];
  }

  @override
  Future<dynamic> uciDelete(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    String? option,
    BuildContext? context,
  }) async {
    calls.add('delete $config.$section');
    if (failWirelessDelete && config == 'wireless') {
      throw Exception('forced wireless rollback failure');
    }
    return [0, {}];
  }

  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async {
    final call = '$command ${params.join(' ')}';
    calls.add(call);
    if (call == '/sbin/wifi down radio0') {
      throw Exception('forced restart failure');
    }
    return [0, {}];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed restart rolls back committed wireless dependencies', () async {
    final api = _FailingRestartApiService();
    final state = AppState.forTesting(
      apiService: api,
      authService: MockAuthService(),
    );
    addTearDown(state.dispose);

    final connected = await state.connectToWirelessNetwork(
      radioDevice: 'radio0',
      ssid: 'Test network',
      encryption: 'psk2',
      password: 'password123',
    );

    expect(connected, isFalse);
    expect(api.calls, contains('delete wireless.wifinet0'));
    expect(
      api.calls,
      contains('/sbin/uci del_list firewall.@zone[1].network=wwan'),
    );
    expect(api.calls, contains('delete network.wwan'));
    expect(api.calls, contains("set wireless.radio0 {disabled: 0}"));
    expect(
      api.calls.where((call) => call == '/sbin/wifi up radio0'),
      hasLength(2),
    );
    expect(api.calls.last, '/sbin/wifi up radio0');
  });

  test('failed station rollback retains its committed dependencies', () async {
    final api = _FailingRestartApiService(failWirelessDelete: true);
    final state = AppState.forTesting(
      apiService: api,
      authService: MockAuthService(),
    );
    addTearDown(state.dispose);

    final connected = await state.connectToWirelessNetwork(
      radioDevice: 'radio0',
      ssid: 'Test network',
      encryption: 'psk2',
      password: 'password123',
    );

    expect(connected, isFalse);
    expect(api.calls, contains('delete wireless.wifinet0'));
    expect(
      api.calls,
      isNot(contains('/sbin/uci del_list firewall.@zone[1].network=wwan')),
    );
    expect(api.calls, isNot(contains('delete network.wwan')));
  });
}
