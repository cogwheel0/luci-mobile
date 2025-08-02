import 'dart:async';

import 'package:flutter/material.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/config/app_config.dart';
import 'package:luci_mobile/services/app_lock_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _logoScale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
    _checkReviewerMode();
  }

  Future<void> _checkReviewerMode() async {
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;
    
    // Check if reviewer mode is enabled
    final secureStorage = SecureStorageService();
    final reviewerModeEnabled = await secureStorage.readValue(AppConfig.reviewerModeKey);
    
    // Check app lock status
    final appLockService = AppLockService();
    await appLockService.initialize();
    
    if (reviewerModeEnabled == 'true' && mounted) {
      // In reviewer mode, check if app lock is enabled
      if (appLockService.isEnabled && appLockService.isLocked) {
        unawaited(Navigator.of(context).pushReplacementNamed('/app-lock'));
      } else {
        unawaited(Navigator.of(context).pushReplacementNamed('/main'));
      }
    } else if (mounted) {
      // Normal flow - check app lock first
      if (appLockService.isEnabled && appLockService.isLocked) {
        unawaited(Navigator.of(context).pushReplacementNamed('/app-lock'));
      } else {
        unawaited(Navigator.of(context).pushReplacementNamed('/login'));
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withValues(alpha: 0.8),
              colorScheme.primaryContainer.withValues(alpha: 0.7),
              colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _logoScale,
                child: Icon(
                  Icons.router,
                  size: 100,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'LuCI Mobile',
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'OpenWrt Router Control',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
} 