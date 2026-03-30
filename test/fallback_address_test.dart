import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/router.dart';

void main() {
  group('Router fallback address', () {
    test('activeAddress returns primary when index is 0', () {
      final router = Router(
        id: 'test-root',
        ipAddress: '192.168.8.1',
        username: 'root',
        password: 'pass',
        useHttps: false,
        alternateAddress: 'router.tail.ts.net',
        alternateUseHttps: true,
        activeAddressIndex: 0,
      );
      expect(router.activeAddress, '192.168.8.1');
      expect(router.activeUseHttps, false);
      expect(router.inactiveAddress, 'router.tail.ts.net');
      expect(router.inactiveUseHttps, true);
    });

    test('activeAddress returns alternate when index is 1', () {
      final router = Router(
        id: 'test-root',
        ipAddress: '192.168.8.1',
        username: 'root',
        password: 'pass',
        useHttps: false,
        alternateAddress: 'router.tail.ts.net',
        alternateUseHttps: true,
        activeAddressIndex: 1,
      );
      expect(router.activeAddress, 'router.tail.ts.net');
      expect(router.activeUseHttps, true);
      expect(router.inactiveAddress, '192.168.8.1');
      expect(router.inactiveUseHttps, false);
    });

    test('activeAddress falls back to primary when no alternate', () {
      final router = Router(
        id: 'test-root',
        ipAddress: '192.168.8.1',
        username: 'root',
        password: 'pass',
        useHttps: false,
        activeAddressIndex: 1, // index 1 but no alternate
      );
      expect(router.activeAddress, '192.168.8.1');
      expect(router.inactiveAddress, isNull);
    });

    test('hasFallback is true only with non-empty alternate', () {
      expect(
        Router(
          id: 'a',
          ipAddress: 'ip',
          username: 'u',
          password: 'p',
          useHttps: false,
          alternateAddress: 'alt',
        ).hasFallback,
        isTrue,
      );
      expect(
        Router(
          id: 'a',
          ipAddress: 'ip',
          username: 'u',
          password: 'p',
          useHttps: false,
        ).hasFallback,
        isFalse,
      );
      expect(
        Router(
          id: 'a',
          ipAddress: 'ip',
          username: 'u',
          password: 'p',
          useHttps: false,
          alternateAddress: '',
        ).hasFallback,
        isFalse,
      );
    });

    test('serialization roundtrip preserves all fields', () {
      final router = Router(
        id: 'test-root',
        ipAddress: '192.168.8.1',
        username: 'root',
        password: 'pass',
        useHttps: false,
        alternateAddress: 'router.tail.ts.net',
        alternateUseHttps: true,
        activeAddressIndex: 1,
      );
      final json = router.toJson();
      final restored = Router.fromJson(json);
      expect(restored.ipAddress, '192.168.8.1');
      expect(restored.alternateAddress, 'router.tail.ts.net');
      expect(restored.alternateUseHttps, true);
      expect(restored.activeAddressIndex, 1);
      expect(restored.activeAddress, 'router.tail.ts.net');
    });

    test('serialization without alternate omits fields', () {
      final router = Router(
        id: 'test-root',
        ipAddress: '192.168.8.1',
        username: 'root',
        password: 'pass',
        useHttps: false,
      );
      final json = router.toJson();
      expect(json.containsKey('alternateAddress'), isFalse);
      expect(json.containsKey('alternateUseHttps'), isFalse);
      expect(json.containsKey('activeAddressIndex'), isFalse);
    });

    test('copyWith updates activeAddressIndex without changing addresses', () {
      final router = Router(
        id: 'test-root',
        ipAddress: '192.168.8.1',
        username: 'root',
        password: 'pass',
        useHttps: false,
        alternateAddress: 'router.tail.ts.net',
        alternateUseHttps: true,
        activeAddressIndex: 0,
      );
      final updated = router.copyWith(activeAddressIndex: 1);
      expect(updated.ipAddress, '192.168.8.1'); // unchanged
      expect(updated.alternateAddress, 'router.tail.ts.net'); // unchanged
      expect(updated.id, 'test-root'); // stable ID
      expect(updated.activeAddressIndex, 1);
      expect(updated.activeAddress, 'router.tail.ts.net');
    });

    test('ID stays stable when activeAddressIndex changes', () {
      final router = Router(
        id: '192.168.8.1-root',
        ipAddress: '192.168.8.1',
        username: 'root',
        password: 'pass',
        useHttps: false,
        alternateAddress: 'tailscale.host',
      );
      final switched = router.copyWith(activeAddressIndex: 1);
      expect(switched.id, router.id);
    });
  });
}
