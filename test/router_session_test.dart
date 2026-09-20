import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/router_session.dart';

const _base = RouterSession(
  routerId: 'r1',
  ipAddress: '192.168.1.1',
  sysauth: 'sid-abc',
  useHttps: false,
  token: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RouterSession equality', () {
    test('identical field values compare equal', () {
      expect(
        _base,
        const RouterSession(
          routerId: 'r1',
          ipAddress: '192.168.1.1',
          sysauth: 'sid-abc',
          useHttps: false,
          token: 1,
        ),
      );
      expect(
        _base.hashCode,
        const RouterSession(
          routerId: 'r1',
          ipAddress: '192.168.1.1',
          sysauth: 'sid-abc',
          useHttps: false,
          token: 1,
        ).hashCode,
      );
    });

    // The token is what makes a re-login a *different* session even when the
    // address and credentials are unchanged. Without it in equality, feature
    // providers would keep serving data fetched under the old session.
    test('a bumped token makes it a different session', () {
      const relogged = RouterSession(
        routerId: 'r1',
        ipAddress: '192.168.1.1',
        sysauth: 'sid-abc',
        useHttps: false,
        token: 2,
      );
      expect(relogged, isNot(_base));
    });

    test('a different router makes it a different session', () {
      const other = RouterSession(
        routerId: 'r2',
        ipAddress: '192.168.1.1',
        sysauth: 'sid-abc',
        useHttps: false,
        token: 1,
      );
      expect(other, isNot(_base));
    });

    test('a rotated sysauth makes it a different session', () {
      const rotated = RouterSession(
        routerId: 'r1',
        ipAddress: '192.168.1.1',
        sysauth: 'sid-xyz',
        useHttps: false,
        token: 1,
      );
      expect(rotated, isNot(_base));
    });

    test('hasFallback reflects a configured fallback address', () {
      expect(_base.hasFallback, isFalse);
      expect(
        const RouterSession(
          routerId: 'r1',
          ipAddress: '192.168.1.1',
          sysauth: 'sid-abc',
          useHttps: false,
          token: 1,
          fallbackAddress: '10.0.0.1',
          fallbackUseHttps: true,
        ).hasFallback,
        isTrue,
      );
    });
  });

  group('AppState.currentSession', () {
    test('exposes the address the auth service actually logged in with', () {
      final state = AppState.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );
      addTearDown(state.dispose);

      final session = state.currentSession;

      expect(session, isNotNull);
      expect(session!.ipAddress, '192.168.1.1');
      expect(session.sysauth, 'mock_sysauth_token_12345');
      expect(session.token, state.sessionToken);
    });

    test('is null without a session token', () async {
      final auth = MockAuthService();
      final state = AppState.forTesting(
        apiService: MockApiService(),
        authService: auth,
      );
      addTearDown(state.dispose);

      await auth.logout();

      expect(state.currentSession, isNull);
    });
  });

  group('AppState critical section', () {
    test(
      'suppresses the dashboard fetch while an apply is confirming',
      () async {
        final state = AppState.forTesting(
          apiService: MockApiService(),
          authService: MockAuthService(),
        );
        addTearDown(state.dispose);

        expect(state.isInCriticalSection, isFalse);

        state.beginCriticalSection();
        expect(state.isInCriticalSection, isTrue);

        // rpcd binds the pending rollback to the session that called uci.apply,
        // so a dashboard fetch here - whose fallback path can re-login - would
        // make uci.confirm fail and the router revert.
        await state.fetchDashboardData();
        expect(state.dashboardData, isNull);

        await state.endCriticalSection(refresh: false);
        expect(state.isInCriticalSection, isFalse);
      },
    );

    test('begin is idempotent and end without begin is a no-op', () async {
      final state = AppState.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );
      addTearDown(state.dispose);

      await state.endCriticalSection();
      expect(state.isInCriticalSection, isFalse);

      state.beginCriticalSection();
      state.beginCriticalSection();
      expect(state.isInCriticalSection, isTrue);

      await state.endCriticalSection(refresh: false);
      expect(state.isInCriticalSection, isFalse);
    });
  });
}
