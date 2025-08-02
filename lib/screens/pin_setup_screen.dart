import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/services/app_lock_service.dart';
import 'package:luci_mobile/services/service_factory.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/pin_ui_components.dart';

class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  final List<String> _firstPin = [];
  final List<String> _confirmPin = [];
  bool _isConfirming = false;
  bool _showError = false;
  String _errorMessage = '';
  bool _isSaving = false;
  
  @override
  void initState() {
    super.initState();
  }
  
  void _onPinDigitPressed(String digit) {
    if (_isConfirming) {
      if (_confirmPin.length < 4) {
        setState(() {
          _confirmPin.add(digit);
          _showError = false;
        });
        
        if (_confirmPin.length == 4) {
          _verifyPins();
        }
      }
    } else {
      if (_firstPin.length < 4) {
        setState(() {
          _firstPin.add(digit);
          _showError = false;
        });
        
        if (_firstPin.length == 4) {
          setState(() {
            _isConfirming = true;
          });
        }
      }
    }
  }
  
  void _onPinDigitRemoved() {
    if (_isConfirming) {
      if (_confirmPin.isNotEmpty) {
        setState(() {
          _confirmPin.removeLast();
          _showError = false;
        });
      }
    } else {
      if (_firstPin.isNotEmpty) {
        setState(() {
          _firstPin.removeLast();
          _showError = false;
        });
      }
    }
  }
  
  Future<void> _verifyPins() async {
    final firstPin = _firstPin.join();
    final confirmPin = _confirmPin.join();
    
    if (firstPin != confirmPin) {
      setState(() {
        _confirmPin.clear();
        _showError = true;
        _errorMessage = 'PIN codes do not match';
      });
      
      // Clear error after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showError = false;
          });
        }
      });
      return;
    }
    
    setState(() {
      _isSaving = true;
    });
    
    final appLockService = ServiceContainer.instance.factory.createAppLockService();
    await appLockService.initialize();
    
    final success = await appLockService.setPinCode(firstPin);
    
    if (success && mounted) {
      // Enable app lock
      await appLockService.setEnabled(true);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN code set successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
      Navigator.of(context).pop();
    } else {
      setState(() {
        _showError = true;
        _errorMessage = 'Failed to save PIN code';
        _isSaving = false;
      });
    }
  }
  

  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Set PIN Code', showBack: true),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            
            // Title and instructions
            Text(
              _isConfirming ? 'Confirm PIN Code' : 'Create PIN Code',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isConfirming 
                ? 'Enter the same PIN code again to confirm'
                : 'Enter a 4-digit PIN code to secure your app',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 60),
            
            // PIN dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final currentPin = _isConfirming ? _confirmPin : _firstPin;
                final isFilled = index < currentPin.length;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: PinDigitWidget(isFilled: isFilled),
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
                textAlign: TextAlign.center,
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
                      PinNumberButton(
                        number: '1',
                        onPressed: () => _onPinDigitPressed('1'),
                        isDisabled: _isSaving,
                      ),
                      PinNumberButton(
                        number: '2',
                        onPressed: () => _onPinDigitPressed('2'),
                        isDisabled: _isSaving,
                      ),
                      PinNumberButton(
                        number: '3',
                        onPressed: () => _onPinDigitPressed('3'),
                        isDisabled: _isSaving,
                      ),
                    ],
                  ),
                  
                  // Row 2: 4, 5, 6
                  Row(
                    children: [
                      PinNumberButton(
                        number: '4',
                        onPressed: () => _onPinDigitPressed('4'),
                        isDisabled: _isSaving,
                      ),
                      PinNumberButton(
                        number: '5',
                        onPressed: () => _onPinDigitPressed('5'),
                        isDisabled: _isSaving,
                      ),
                      PinNumberButton(
                        number: '6',
                        onPressed: () => _onPinDigitPressed('6'),
                        isDisabled: _isSaving,
                      ),
                    ],
                  ),
                  
                  // Row 3: 7, 8, 9
                  Row(
                    children: [
                      PinNumberButton(
                        number: '7',
                        onPressed: () => _onPinDigitPressed('7'),
                        isDisabled: _isSaving,
                      ),
                      PinNumberButton(
                        number: '8',
                        onPressed: () => _onPinDigitPressed('8'),
                        isDisabled: _isSaving,
                      ),
                      PinNumberButton(
                        number: '9',
                        onPressed: () => _onPinDigitPressed('9'),
                        isDisabled: _isSaving,
                      ),
                    ],
                  ),
                  
                  // Row 4: empty, 0, backspace
                  Row(
                    children: [
                      const Expanded(child: SizedBox()),
                      PinNumberButton(
                        number: '0',
                        onPressed: () => _onPinDigitPressed('0'),
                        isDisabled: _isSaving,
                      ),
                      PinActionButton(
                        icon: Icons.backspace_outlined,
                        onPressed: _onPinDigitRemoved,
                        isDisabled: _isSaving,
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