import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AppLockService {
  static const String _pinCodeKey = 'app_lock_pin_code';
  static const String _isEnabledKey = 'app_lock_enabled';
  static const String _useBiometricsKey = 'app_lock_use_biometrics';
  static const String _lockTimeoutKey = 'app_lock_timeout';
  
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  // App lock state
  bool _isLocked = false;
  bool _isEnabled = false;
  bool _useBiometrics = false;
  int _lockTimeout = 0; // 0 = immediate, >0 = seconds
  DateTime? _lastUnlockTime;
  
  bool get isLocked => _isLocked;
  bool get isEnabled => _isEnabled;
  bool get useBiometrics => _useBiometrics;
  int get lockTimeout => _lockTimeout;
  
  /// Initialize the app lock service
  Future<void> initialize() async {
    await _loadSettings();
    _checkLockStatus();
  }
  
  /// Load settings from secure storage
  Future<void> _loadSettings() async {
    final enabled = await _secureStorage.read(key: _isEnabledKey);
    _isEnabled = enabled == 'true';
    
    final biometrics = await _secureStorage.read(key: _useBiometricsKey);
    _useBiometrics = biometrics == 'true';
    
    final timeout = await _secureStorage.read(key: _lockTimeoutKey);
    _lockTimeout = int.tryParse(timeout ?? '0') ?? 0;
  }
  
  /// Check if app should be locked based on timeout
  void _checkLockStatus() {
    if (!_isEnabled) {
      _isLocked = false;
      return;
    }
    
    if (_lockTimeout == 0) {
      // Immediate lock
      _isLocked = true;
    } else if (_lastUnlockTime != null) {
      final timeSinceUnlock = DateTime.now().difference(_lastUnlockTime!);
      _isLocked = timeSinceUnlock.inSeconds >= _lockTimeout;
    } else {
      _isLocked = true;
    }
  }
  
  /// Enable or disable app lock
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    await _secureStorage.write(key: _isEnabledKey, value: enabled.toString());
    
    if (!enabled) {
      _isLocked = false;
      _lastUnlockTime = null;
    } else {
      _checkLockStatus();
    }
  }
  
  /// Set PIN code
  Future<bool> setPinCode(String pinCode) async {
    if (pinCode.length < 4) {
      return false;
    }
    
    try {
      await _secureStorage.write(key: _pinCodeKey, value: pinCode);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Verify PIN code
  Future<bool> verifyPinCode(String pinCode) async {
    try {
      final storedPin = await _secureStorage.read(key: _pinCodeKey);
      return storedPin == pinCode;
    } catch (e) {
      return false;
    }
  }
  
  /// Check if PIN code is set
  Future<bool> isPinCodeSet() async {
    try {
      final pin = await _secureStorage.read(key: _pinCodeKey);
      return pin != null && pin.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
  
  /// Set biometric authentication preference
  Future<void> setUseBiometrics(bool useBiometrics) async {
    _useBiometrics = useBiometrics;
    await _secureStorage.write(key: _useBiometricsKey, value: useBiometrics.toString());
  }
  
  /// Set lock timeout in seconds (0 = immediate)
  Future<void> setLockTimeout(int timeoutSeconds) async {
    _lockTimeout = timeoutSeconds;
    await _secureStorage.write(key: _lockTimeoutKey, value: timeoutSeconds.toString());
  }
  
  /// Check if biometric authentication is available
  Future<bool> isBiometricsAvailable() async {
    try {
      final isAvailable = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return isAvailable && isDeviceSupported;
    } catch (e) {
      return false;
    }
  }
  
  /// Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }
  
  /// Authenticate with biometrics
  Future<bool> authenticateWithBiometrics() async {
    try {
      final isAvailable = await isBiometricsAvailable();
      if (!isAvailable) {
        return false;
      }
      
      final result = await _localAuth.authenticate(
        localizedReason: 'Authenticate to unlock the app',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      
      if (result) {
        unlock();
      }
      
      return result;
    } catch (e) {
      return false;
    }
  }
  
  /// Unlock the app
  void unlock() {
    _isLocked = false;
    _lastUnlockTime = DateTime.now();
  }
  
  /// Lock the app
  void lock() {
    _isLocked = true;
    _lastUnlockTime = null;
  }
  
  /// Check if app should be locked (call this when app becomes active)
  void onAppResumed() {
    _checkLockStatus();
  }
  
  /// Clear all app lock data
  Future<void> clearAllData() async {
    await _secureStorage.delete(key: _pinCodeKey);
    await _secureStorage.delete(key: _isEnabledKey);
    await _secureStorage.delete(key: _useBiometricsKey);
    await _secureStorage.delete(key: _lockTimeoutKey);
    
    _isEnabled = false;
    _useBiometrics = false;
    _lockTimeout = 0;
    _isLocked = false;
    _lastUnlockTime = null;
  }
} 