import 'package:flutter/material.dart';
import 'package:luci_mobile/services/interfaces/auth_service_interface.dart';

class MockAuthService implements IAuthService {
  String? _sysauth = 'mock_sysauth_token_12345';
  String? _ipAddress = '192.168.1.1';
  bool _useHttps = false;
  bool _isAuthenticated = true;

  @override
  String? get sysauth => _sysauth;

  @override
  String? get ipAddress => _ipAddress;

  @override
  bool get useHttps => _useHttps;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  Future<void> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    // Simulate a short delay for realism
    await Future.delayed(const Duration(milliseconds: 500));

    // Always succeed for mock authentication
    _ipAddress = ipAddress;
    _useHttps = useHttps;
    _isAuthenticated = true;
    _sysauth = 'mock_sysauth_token_12345';
  }

  @override
  Future<bool> tryAutoLogin(
    String? ipAddress,
    String? username,
    String? password,
    bool? useHttps, {
    BuildContext? context,
  }) async {
    // Simulate a short delay for realism
    await Future.delayed(const Duration(milliseconds: 300));

    // Always succeed for mock auto-login
    _ipAddress = ipAddress ?? '192.168.1.1';
    _useHttps = useHttps ?? false;
    _isAuthenticated = true;
    _sysauth = 'mock_sysauth_token_12345';
    return true;
  }

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
    await Future.delayed(const Duration(milliseconds: 500));
    _ipAddress = activeAddress;
    _useHttps = activeHttps;
    _isAuthenticated = true;
    _sysauth = 'mock_sysauth_token_12345';
    return FallbackLoginResult(success: true, usedAddressIndex: activeIndex);
  }

  @override
  Future<void> logout() async {
    _sysauth = null;
    _isAuthenticated = false;
  }

  @override
  Future<bool> checkRouterAvailability(
    String ipAddress,
    bool useHttps, {
    BuildContext? context,
  }) async {
    // Simulate a short delay for realism
    await Future.delayed(const Duration(milliseconds: 200));

    // Always return true for mock router availability
    return true;
  }
}
