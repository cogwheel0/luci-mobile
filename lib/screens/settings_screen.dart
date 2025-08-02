import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/services/app_lock_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late AppLockService _appLockService;
  bool _isAppLockEnabled = false;
  bool _useBiometrics = false;
  bool _isBiometricsAvailable = false;
  bool _isPinCodeSet = false;
  int _lockTimeout = 0;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _initializeAppLock();
  }
  
  Future<void> _initializeAppLock() async {
    _appLockService = AppLockService();
    await _appLockService.initialize();
    
    setState(() {
      _isAppLockEnabled = _appLockService.isEnabled;
      _useBiometrics = _appLockService.useBiometrics;
      _lockTimeout = _appLockService.lockTimeout;
    });
    
    // Check biometrics availability
    final biometricsAvailable = await _appLockService.isBiometricsAvailable();
    final pinCodeSet = await _appLockService.isPinCodeSet();
    
    setState(() {
      _isBiometricsAvailable = biometricsAvailable;
      _isPinCodeSet = pinCodeSet;
      _isLoading = false;
    });
  }
  
  void _showReviewerModeResetDialog(BuildContext context, WidgetRef ref) {
    final appState = ref.read(appStateProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Reviewer Mode?'),
        content: const Text(
          'This will disable reviewer mode and return to normal authentication. '
          'You will need to log in with real router credentials.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await appState.setReviewerMode(false);
              appState.logout();
              if (context.mounted) {
                unawaited(Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false));
              }
            },
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    
    return Scaffold(
      appBar: const LuciAppBar(title: 'Settings', showBack: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        children: [
          Builder(
            builder: (context) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
                    child: Text('Theme', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('System Default'),
                    value: ThemeMode.system,
                    groupValue: appState.themeMode,
                    onChanged: (mode) => appState.setThemeMode(mode!),
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Light'),
                    value: ThemeMode.light,
                    groupValue: appState.themeMode,
                    onChanged: (mode) => appState.setThemeMode(mode!),
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Dark'),
                    value: ThemeMode.dark,
                    groupValue: appState.themeMode,
                    onChanged: (mode) => appState.setThemeMode(mode!),
                  ),
                  if (appState.reviewerModeEnabled) ...[
                    const Divider(height: 32),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text('Reviewer Mode', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline, color: Colors.orange),
                      title: const Text('Reviewer Mode Active'),
                      subtitle: Text(
                        'Mock data is being used for demonstration',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: FilledButton.icon(
                        onPressed: () => _showReviewerModeResetDialog(context, ref),
                        icon: const Icon(Icons.exit_to_app),
                        label: const Text('Exit Reviewer Mode'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(context).colorScheme.onError,
                        ),
                      ),
                    ),
                  ],
                  
                  // App Lock Settings
                  const Divider(height: 32),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text('App Lock', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  
                  if (_isLoading) ...[
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ] else ...[
                    // Enable/Disable App Lock
                    SwitchListTile(
                      title: const Text('Enable App Lock'),
                      subtitle: const Text('Require authentication to access the app'),
                      value: _isAppLockEnabled,
                      onChanged: (value) async {
                        if (value && !_isPinCodeSet) {
                          // Show PIN setup screen
                          final result = await Navigator.of(context).pushNamed('/pin-setup');
                          if (result == true) {
                            await _initializeAppLock();
                          }
                        } else {
                          await _appLockService.setEnabled(value);
                          setState(() {
                            _isAppLockEnabled = value;
                          });
                        }
                      },
                    ),
                    
                    if (_isAppLockEnabled) ...[
                      // PIN Code Management
                      ListTile(
                        leading: const Icon(Icons.pin),
                        title: const Text('PIN Code'),
                        subtitle: Text(_isPinCodeSet ? 'PIN code is set' : 'No PIN code set'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          if (_isPinCodeSet) {
                            // Show PIN change dialog
                            _showPinChangeDialog(context);
                          } else {
                            // Navigate to PIN setup
                            final result = await Navigator.of(context).pushNamed('/pin-setup');
                            if (result == true) {
                              await _initializeAppLock();
                            }
                          }
                        },
                      ),
                      
                      // Biometric Authentication
                      if (_isBiometricsAvailable) ...[
                        SwitchListTile(
                          title: const Text('Use Biometric Authentication'),
                          subtitle: const Text('Allow fingerprint or face recognition'),
                          value: _useBiometrics,
                          onChanged: (value) async {
                            await _appLockService.setUseBiometrics(value);
                            setState(() {
                              _useBiometrics = value;
                            });
                          },
                        ),
                      ],
                      
                      // Lock Timeout
                      ListTile(
                        leading: const Icon(Icons.timer),
                        title: const Text('Lock Timeout'),
                        subtitle: Text(_getLockTimeoutText()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showLockTimeoutDialog(context),
                      ),
                      
                      // Test App Lock
                      ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: const Text('Test App Lock'),
                        subtitle: const Text('Lock the app now to test'),
                        onTap: () {
                          _appLockService.lock();
                          Navigator.of(context).pushNamed('/app-lock');
                        },
                      ),
                    ],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
  
  String _getLockTimeoutText() {
    switch (_lockTimeout) {
      case 0:
        return 'Immediate';
      case 30:
        return '30 seconds';
      case 60:
        return '1 minute';
      case 300:
        return '5 minutes';
      case 600:
        return '10 minutes';
      default:
        return '${_lockTimeout} seconds';
    }
  }
  
  void _showPinChangeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change PIN Code'),
        content: const Text('Do you want to change your PIN code?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final result = await Navigator.of(context).pushNamed('/pin-setup');
              if (result == true) {
                await _initializeAppLock();
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
  
  void _showLockTimeoutDialog(BuildContext context) {
    final timeoutOptions = [
      {'value': 0, 'label': 'Immediate'},
      {'value': 30, 'label': '30 seconds'},
      {'value': 60, 'label': '1 minute'},
      {'value': 300, 'label': '5 minutes'},
      {'value': 600, 'label': '10 minutes'},
    ];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lock Timeout'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: timeoutOptions.map((option) {
            return RadioListTile<int>(
              title: Text(option['label'] as String),
              value: option['value'] as int,
              groupValue: _lockTimeout,
              onChanged: (value) async {
                if (value != null) {
                  await _appLockService.setLockTimeout(value);
                  setState(() {
                    _lockTimeout = value;
                  });
                  Navigator.of(context).pop();
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
