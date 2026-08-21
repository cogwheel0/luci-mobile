import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:luci_mobile/models/router.dart';
import '../utils/logger.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  static const String _routersKey = 'routers';
  static const String _selectedRouterKey = 'selectedRouterId';

  static const List<String> _credentialKeys = [
    'ipAddress',
    'username',
    'password',
    'useHttps',
  ];

  Future<void> saveCredentials({
    required String ipAddress,
    required String username,
    required String password,
    required bool useHttps,
  }) async {
    try {
      await _storage.write(key: 'ipAddress', value: ipAddress);
      await _storage.write(key: 'username', value: username);
      await _storage.write(key: 'password', value: password);
      await _storage.write(key: 'useHttps', value: useHttps.toString());
    } catch (e, stack) {
      Logger.exception('Failed to save credentials', e, stack);
      rethrow;
    }
  }

  Future<Map<String, String?>> getCredentials() async {
    try {
      final ipAddress = await _storage.read(key: 'ipAddress');
      final username = await _storage.read(key: 'username');
      final password = await _storage.read(key: 'password');
      final useHttps = await _storage.read(key: 'useHttps');
      return {
        'ipAddress': ipAddress,
        'username': username,
        'password': password,
        'useHttps': useHttps,
      };
    } catch (e, stack) {
      Logger.exception('Failed to get credentials', e, stack);
      return {
        'ipAddress': null,
        'username': null,
        'password': null,
        'useHttps': null,
      };
    }
  }

  Future<void> clearCredentials() async {
    try {
      // Clear only session credentials. Deleting everything here would also
      // wipe the saved routers list (including per-router passwords), the
      // selected router, dashboard preferences, theme and accepted certs.
      for (final key in _credentialKeys) {
        await _storage.delete(key: key);
      }
    } catch (e, stack) {
      Logger.exception('Failed to clear credentials', e, stack);
      // Don't rethrow as this is often called during cleanup
    }
  }

  Future<String?> readValue(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e, stack) {
      Logger.exception('Failed to read value for key: $key', e, stack);
      return null;
    }
  }

  Future<void> writeValue(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e, stack) {
      Logger.exception('Failed to write value for key: $key', e, stack);
      rethrow;
    }
  }

  Future<void> deleteValue(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e, stack) {
      Logger.exception('Failed to delete value for key: $key', e, stack);
      rethrow;
    }
  }

  Future<void> saveRouters(List<Router> routers) async {
    try {
      final jsonList = routers.map((r) => r.toJson()).toList();
      await _storage.write(key: _routersKey, value: jsonEncode(jsonList));
    } catch (e, stack) {
      Logger.exception('Failed to save routers', e, stack);
      rethrow;
    }
  }

  Future<List<Router>> getRouters() async {
    try {
      final jsonString = await _storage.read(key: _routersKey);
      if (jsonString == null || jsonString.isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((e) => Router.fromJson(e)).toList();
    } catch (e, stack) {
      Logger.exception('Failed to get routers', e, stack);
      return [];
    }
  }

  Future<void> deleteRouter(String id) async {
    try {
      final routers = await getRouters();
      final updated = routers.where((r) => r.id != id).toList();
      await saveRouters(updated);
    } catch (e, stack) {
      Logger.exception('Failed to delete router: $id', e, stack);
      rethrow;
    }
  }

  Future<void> updateRouter(Router router) async {
    try {
      final routers = await getRouters();
      final updated = [
        for (final r in routers)
          if (r.id == router.id) router else r,
      ];
      await saveRouters(updated);
    } catch (e, stack) {
      Logger.exception('Failed to update router: ${router.id}', e, stack);
      rethrow;
    }
  }

  Future<void> saveSelectedRouterId(String? id) async {
    try {
      if (id == null) {
        await _storage.delete(key: _selectedRouterKey);
      } else {
        await _storage.write(key: _selectedRouterKey, value: id);
      }
    } catch (e, stack) {
      Logger.exception('Failed to save selected router ID', e, stack);
      rethrow;
    }
  }

  Future<String?> getSelectedRouterId() async {
    try {
      return await _storage.read(key: _selectedRouterKey);
    } catch (e, stack) {
      Logger.exception('Failed to get selected router ID', e, stack);
      return null;
    }
  }
}
