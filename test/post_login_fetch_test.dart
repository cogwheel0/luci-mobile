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

/// A saved address that loses one request to the parallel hang and is then
/// gone - the phone left its network - while the alternate keeps answering.
/// Each dashboard fetch starts with the reboot-access check, which is how a
/// new round is told apart.
class _PrimaryGoesAway extends MockApiService {
  static const primary = '192.168.1.1';

  var _round = 0;

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
    if (object == 'session' && method == 'access') _round++;
    if (ipAddress == primary && _round == 1 && object == 'system') {
      throw _Router._timeout(const UnansweredParallelRequest());
    }
    if (ipAddress == primary && _round > 1) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/cgi-bin/luci/admin/ubus'),
        reason: 'Network is unreachable',
      );
    }
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
}

/// Logs in on the alternate address, as `loginWithFallback` does when the
/// saved one does not answer.
class _FallbackAuth extends MockAuthService {
  String? _address;

  @override
  String? get ipAddress => _address ?? super.ipAddress;

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
    _address = fallbackAddress;
    return FallbackLoginResult(success: true, usedAddressIndex: 1);
  }
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

    // Asking again after the hang is not the alternate-address retry: a
    // saved address that went away mid-fetch looks like the hang first.
    test('still tries the alternate address after asking again', () async {
      final saved = Router(
        id: 'router',
        ipAddress: _PrimaryGoesAway.primary,
        username: 'root',
        password: 'password',
        useHttps: false,
        alternateAddress: '100.64.0.1',
        alternateUseHttps: false,
      );
      await routers.updateRouter(saved);
      final state = AppState.forTesting(
        apiService: _PrimaryGoesAway(),
        authService: _FallbackAuth(),
        routerService: routers,
      );
      addTearDown(state.dispose);

      await state.fetchDashboardData();

      expect(state.appFailure, isNull);
      expect(state.dashboardData, isNotNull);
      expect(routers.selectedRouter!.activeAddressIndex, 1);
    });

    // #89: either of these failing blanked the dashboard and the
    // Interfaces page with it; they only add throughput and a client count.
    test('loads without device counters or leases', () async {
      final api = _Router(
        timesOut: {'luci-rpc.getNetworkDevices', 'luci-rpc.getDHCPLeases'},
      );
      final state = stateFor(api);

      await state.fetchDashboardData();

      expect(state.appFailure, isNull);
      expect(state.dashboardData, isNotNull);
      expect(state.dashboardData!['boardInfo'], isNotNull);
      expect(state.dashboardData!['interfaceDump'], isNotNull);
      expect(state.dashboardData!['networkDevices'], isNull);
      expect(state.dashboardData!['dhcpLeases'], isNull);
    });

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

  // The fetch a logout overtakes leaves its state alone; the dashboard would
  // then skip fetching for good, waiting on it.
  test('logging out during a fetch leaves nothing loading', () async {
    final state = stateFor(_Router());

    final fetch = state.fetchDashboardData();
    expect(state.isDashboardLoading, isTrue);
    await state.logout();
    await fetch;

    expect(state.isDashboardLoading, isFalse);
    expect(state.dashboardFetchIsFresh, isFalse);
  });

  // Which devices face the internet changes with failover and reconnects,
  // and the dashboard is not re-fetched on its own; the poll re-reads the
  // interface dump itself, but only once its copy is old enough.
  group('the throughput poll re-reads the interface dump', () {
    Future<_Router> pollFor({required Duration maxAge}) async {
      final api = _Router();
      final state = stateFor(api)..throughputDumpMaxAge = maxAge;
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
      api.calls.clear();
      // The poll ticks every two seconds.
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(api.calls, contains('luci-rpc.getNetworkDevices'));
      return api;
    }

    test('once its copy is stale', () async {
      final api = await pollFor(maxAge: Duration.zero);
      expect(api.callsTo('network.interface.dump'), greaterThan(0));
      // Before the counters, so a slow dump read cannot date them late.
      expect(
        api.calls.indexOf('network.interface.dump'),
        lessThan(api.calls.indexOf('luci-rpc.getNetworkDevices')),
      );
    });

    test('not while the dashboard fetch\'s copy is fresh', () async {
      final api = await pollFor(maxAge: const Duration(minutes: 5));
      expect(api.callsTo('network.interface.dump'), 0);
    });
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

  // Log out used to keep the selected router, so the login screen it opened
  // signed straight back in - as did the next launch (#88).
  group('after Log out', () {
    test('neither the login screen nor a restart signs back in', () async {
      final state = stateFor(_Router());
      expect(await state.tryAutoLogin(), isTrue);

      await state.logout(userInitiated: true);
      expect(await state.tryAutoLogin(), isFalse);

      // A restart: everything reloaded from storage.
      final restarted = RouterService();
      await restarted.loadRouters();
      final relaunched = AppState.forTesting(
        apiService: _Router(),
        authService: MockAuthService(),
        routerService: restarted,
      );
      addTearDown(relaunched.dispose);
      expect(await relaunched.tryAutoLogin(), isFalse);
      // The router itself is kept, for the login form and Manage routers.
      expect(restarted.selectedRouter?.id, 'router');
    });

    test('signing in again ends it', () async {
      final state = stateFor(_Router());
      await state.logout(userInitiated: true);

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
      expect(await state.tryAutoLogin(), isTrue);
    });

    // Removing the last router or leaving reviewer mode also log out; they
    // are not the user asking to be signed out.
    test('a logout the app does itself is not remembered', () async {
      final state = stateFor(_Router());
      await state.logout();
      expect(await state.tryAutoLogin(), isTrue);
    });

    // The login it overtook must not clear the logout's flag on its way
    // out, in this run or the next.
    test('Log out during a sign-in wins', () async {
      final auth = _SlowAuth();
      final state = AppState.forTesting(
        apiService: _Router(),
        authService: auth,
        routerService: routers,
      );
      addTearDown(state.dispose);

      final login = state.login(
        '192.168.1.1',
        'root',
        'password',
        false,
        fromRouter: true,
      );
      final logout = state.logout(userInitiated: true);
      auth.answer.complete();

      expect(await login, isFalse);
      await logout;
      expect(await state.tryAutoLogin(), isFalse);
      expect(await routers.isSignedOut(), isTrue);
    });

    // Logout's cleanup must take its place in the auth queue before it waits
    // on storage; otherwise a sign-in started in that gap is queued first
    // and the older logout's cleanup ends it.
    test('a sign-in right after Log out is not ended by it', () async {
      final auth = MockAuthService();
      final state = AppState.forTesting(
        apiService: _Router(),
        authService: auth,
        routerService: routers,
      );
      addTearDown(state.dispose);

      final logout = state.logout(userInitiated: true);
      final login = state.login('192.168.1.1', 'root', 'password', false);
      await logout;

      expect(await login, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(await state.tryAutoLogin(), isTrue);
    });

    test('flag writes land in the order they were made', () async {
      // Neither awaited before the next: a login's clear, then a logout.
      final cleared = routers.setSignedOut(false);
      final set = routers.setSignedOut(true);
      await Future.wait([cleared, set]);
      expect(await routers.isSignedOut(), isTrue);
    });
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
