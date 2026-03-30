import 'package:flutter/material.dart';

/// Result of a login attempt with fallback.
class FallbackLoginResult {
  final bool success;
  final int usedAddressIndex; // 0 = primary, 1 = alternate

  FallbackLoginResult({required this.success, required this.usedAddressIndex});
}

abstract class IAuthService {
  Future<void> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  });

  /// Try active address first, then fallback to the other.
  Future<FallbackLoginResult> loginWithFallback({
    required String activeAddress,
    required bool activeHttps,
    required int activeIndex,
    String? fallbackAddress,
    bool? fallbackHttps,
    required String username,
    required String password,
    BuildContext? context,
  });

  Future<bool> tryAutoLogin(
    String? ipAddress,
    String? username,
    String? password,
    bool? useHttps, {
    BuildContext? context,
  });
  Future<void> logout();
  Future<bool> checkRouterAvailability(
    String ipAddress,
    bool useHttps, {
    BuildContext? context,
  });

  String? get sysauth;
  String? get ipAddress;
  bool get useHttps;
  bool get isAuthenticated;
}
