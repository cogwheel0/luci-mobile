import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/services/app_lock_service.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  final TextEditingController _pinController = TextEditingController();
  final List<String> _enteredPin = [];
  bool _isAuthenticating = false;
  bool _showError = false;
  String _errorMessage = '';
  
  @override
  void initState() {
    super.initState();
    _tryBiometricAuth();
  }
  
  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }
  
  Future<void> _tryBiometricAuth() async {
    final appLockService = AppLockService();
    await appLockService.initialize();
    
    if (appLockService.useBiometrics && await appLockService.isBiometricsAvailable()) {
      setState(() {
        _isAuthenticating = true;
      });
      
      final success = await appLockService.authenticateWithBiometrics();
      
      if (success && mounted) {
        Navigator.of(context).pushReplacementNamed('/main');
      } else {
        setState(() {
          _isAuthenticating = false;
        });
      }
    }
  }
  
  void _onPinDigitPressed(String digit) {
    if (_enteredPin.length < 4) {
      setState(() {
        _enteredPin.add(digit);
        _showError = false;
      });
      
      if (_enteredPin.length == 4) {
        _verifyPin();
      }
    }
  }
  
  void _onPinDigitRemoved() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin.removeLast();
        _showError = false;
      });
    }
  }
  
  Future<void> _verifyPin() async {
    setState(() {
      _isAuthenticating = true;
    });
    
    final pinCode = _enteredPin.join();
    final appLockService = AppLockService();
    await appLockService.initialize();
    
    final isValid = await appLockService.verifyPinCode(pinCode);
    
    if (isValid && mounted) {
      appLockService.unlock();
      Navigator.of(context).pushReplacementNamed('/main');
    } else {
      setState(() {
        _enteredPin.clear();
        _showError = true;
        _errorMessage = 'Incorrect PIN code';
        _isAuthenticating = false;
      });
      
      // Clear error after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showError = false;
          });
        }
      });
    }
  }
  
  Widget _buildPinDigit({bool isFilled = false}) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isFilled 
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.outline.withOpacity(0.3),
      ),
    );
  }
  
  Widget _buildNumberButton(String number) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: _isAuthenticating ? null : () => _onPinDigitPressed(number),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    number,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildActionButton({required IconData icon, required VoidCallback onTap}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: _isAuthenticating ? null : onTap,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: 28,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            
            // App icon and title
            Icon(
              Icons.lock_outline,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Enter PIN Code',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your PIN to unlock the app',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            
            const SizedBox(height: 60),
            
            // PIN dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final isFilled = index < _enteredPin.length;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: _buildPinDigit(isFilled: isFilled),
                );
              }),
            ),
            
            if (_showError) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            
            const Spacer(),
            
            // Number pad
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                children: [
                  // Row 1: 1, 2, 3
                  Row(
                    children: [
                      _buildNumberButton('1'),
                      _buildNumberButton('2'),
                      _buildNumberButton('3'),
                    ],
                  ),
                  
                  // Row 2: 4, 5, 6
                  Row(
                    children: [
                      _buildNumberButton('4'),
                      _buildNumberButton('5'),
                      _buildNumberButton('6'),
                    ],
                  ),
                  
                  // Row 3: 7, 8, 9
                  Row(
                    children: [
                      _buildNumberButton('7'),
                      _buildNumberButton('8'),
                      _buildNumberButton('9'),
                    ],
                  ),
                  
                  // Row 4: biometric, 0, backspace
                  Row(
                    children: [
                      _buildActionButton(
                        icon: Icons.fingerprint,
                        onTap: _tryBiometricAuth,
                      ),
                      _buildNumberButton('0'),
                      _buildActionButton(
                        icon: Icons.backspace_outlined,
                        onTap: _onPinDigitRemoved,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
} 