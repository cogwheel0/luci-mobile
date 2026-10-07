import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/router.dart';
import 'package:luci_mobile/services/interfaces/auth_service_interface.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/services/router_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';

/// Answers from the reviewer fixtures, except that the calls in
/// [unansweredOnce] fail once the way a router hit by openwrt/luci#9091 fails
/// them, and the calls in [timesOut] always fail with an ordinary timeout.
class _Router extends MockApiService {
  _Router({Set<String> unansweredOnce = const {}, this.timesOut = const {}})
    : _unansweredOnce = {...unansweredOnce};

  final Set<String> _unansweredOnce;
  final Set<String> timesOut;
  final calls = <String>[];

  int callsTo(String name) => calls.where((c) => c == name).length;

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    final name = '$object.$method';
    calls.add(name);
    if (_unansweredOnce.remove(name)) {
      throw _timeout(const UnansweredParallelRequest());
    }
    if (timesOut.contains(name)) throw _timeout(null);
    return super.call(
      ipAddress,
      sysauth,
      useHttps,
      object: object,
      method: method,
      params: params,
      context: context,
    );
  }

  static DioException _timeout(Object? error) => DioException.receiveTimeout(
    timeout: const Duration(seconds: 15),
    requestOptions: RequestOptions(path: '/cgi-bin/luci/admin/ubus'),
    error: error,
  );
}

/// Holds every login until [answer] completes.
class _SlowAuth extends MockAuthService {
  final answer = Completer<void>();

  @override
  Future<FallbackLoginResult> loginWithFallback({
    required String activeAddress,
    required bool activeHttps,
    required int activeIndex,
    String? fallbackAddress,
    bool? fallbackHttps,
    required String username,
    required String password,
    BuildContext? context,
  }) async {
    await answer.future;
    return FallbackLoginResult(success: true, usedAddressIndex: activeIndex);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RouterService routers;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    routers = RouterService();
    await routers.addRouter(
      Router(
        id: 'router',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
      ),
    );
  });

  AppState stateFor(_Router api) {
    final state = AppState.forTesting(
      apiService: api,
      authService: MockAuthService(),
      routerService: routers,
    );
    addTearDown(state.dispose);
    return state;
  }

  group('a dashboard fetch on a router that hangs parallel requests', () {
    // Optional calls fail quietly: without asking again the dashboard
    // would load with no wireless at all.
    test('asks again for what an optional call lost', () async {
      final api = _Router(unansweredOnce: {'luci-rpc.getWirelessDevices'});
      final state = stateFor(api);

      await state.fetchDashboardData();

      expect(api.callsTo('luci-rpc.getWirelessDevices'), 2);
      expect(state.dashboardData!['wireless'], isNotEmpty);
      expect(state.appFailure, isNull);
    });

    test(
      'asks again instead of failing when a required call was lost',
      () async {
        final api = _Router(unansweredOnce: {'system.board'});
        final state = stateFor(api);

        await state.fetchDashboardData();

        expect(api.callsTo('system.board'), 2);
        expect(state.dashboardData, isNotNull);
        expect(state.appFailure, isNull);
      },
    );

    test('reports an ordinary timeout without asking again', () async {
      final api = _Router(timesOut: {'system.board'});
      final state = stateFor(api);

      await state.fetchDashboardData();

      expect(api.callsTo('system.board'), 1);
      expect(state.appFailure, isNotNull);
    });
  });

  // The dashboard opens right after the login that fetched it, and used to
  // send the same burst again.
  test('a fetch that just finished, even a failed one, is fresh', () async {
    final state = stateFor(_Router(timesOut: {'system.board'}));
    expect(state.dashboardFetchIsFresh, isFalse);

    await state.fetchDashboardData();
    expect(state.dashboardFetchIsFresh, isTrue);

    await state.logout();
    expect(state.dashboardFetchIsFresh, isFalse);
  });

  test('a login whose fetch failed starts no throughput poll', () async {
    final api = _Router(timesOut: {'system.board'});
    final state = stateFor(api);

    expect(
      await state.login(
        '192.168.1.1',
        'root',
        'password',
        false,
        fromRouter: true,
      ),
      isTrue,
    );
    expect(state.appFailure, isNotNull);
    final sent = api.calls.length;

    // The poll ticks every two seconds.
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(api.calls.skip(sent), isNot(contains('luci-rpc.getNetworkDevices')));
  });

  test('logging out during a login leaves the login button idle', () async {
    final auth = _SlowAuth();
    final state = AppState.forTesting(
      apiService: MockApiService(),
      authService: auth,
    );
    addTearDown(state.dispose);

    final login = state.login('192.168.1.1', 'root', 'password', false);
    expect(state.isLoading, isTrue);
    final logout = state.logout();
    auth.answer.complete();

    expect(await login, isFalse);
    await logout;
    expect(state.isLoading, isFalse);
  });
}
