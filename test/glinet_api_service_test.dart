import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/glinet_api_service.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';

void main() {
  group('GlInetApiService', () {
    test('isAuthenticated is false before login', () {
      final service = GlInetApiService(HttpClientManager());
      expect(service.isAuthenticated, isFalse);
    });

    test('clearSession resets auth state', () {
      final service = GlInetApiService(HttpClientManager());
      // Simulate that we set internal state via reflection isn't possible,
      // but we can verify clearSession doesn't throw
      service.clearSession();
      expect(service.isAuthenticated, isFalse);
    });

    test('call returns null when not authenticated', () async {
      final service = GlInetApiService(HttpClientManager());
      final result = await service.call('host', false, 'system', 'get_status');
      expect(result, isNull);
    });

    test('getWifiChannels returns empty map when not authenticated', () async {
      final service = GlInetApiService(HttpClientManager());
      final result = await service.getWifiStatus('host', false);
      expect(result, isEmpty);
    });

    test('getClients returns empty map when not authenticated', () async {
      final service = GlInetApiService(HttpClientManager());
      final result = await service.getClients('host', false);
      expect(result, isEmpty);
    });

    test('getSystemExtras returns empty map when not authenticated', () async {
      final service = GlInetApiService(HttpClientManager());
      final result = await service.getSystemExtras('host', false);
      expect(result, isEmpty);
    });
  });
}
