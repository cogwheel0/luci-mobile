import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';

/// Asks the platform to confirm it is the device owner: fingerprint, face,
/// or the screen-lock PIN/pattern when no biometric is enrolled.
class AppLockAuth {
  AppLockAuth._();

  static final _auth = LocalAuthentication();

  /// Whether this device has any screen lock the app can defer to.
  static Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

/// Covers the app until the owner unlocks it, on launch and whenever it
/// returns after [relockAfter] in the background (GitHub issue #15).
///
/// The router passwords the app keeps are admin credentials; anyone holding
/// an unlocked phone could otherwise open the app and reconfigure the
/// network (see also issue #88).
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.enabled,
    required this.ready,
    required this.child,
    this.relockAfter = const Duration(seconds: 30),
  });

  final bool enabled;

  /// False until the saved settings are read; [enabled] means nothing
  /// before that.
  final bool ready;
  final Widget child;
  final Duration relockAfter;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _settled = false;
  bool _authenticating = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settle();
  }

  /// Locks once, at launch, as soon as the saved setting is known.
  void _settle() {
    if (_settled || !widget.ready) return;
    _settled = true;
    if (widget.enabled) {
      _locked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  @override
  void didUpdateWidget(AppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _settle();
    // Turning the lock on from settings must not lock the user out of the
    // screen they are on; turning it off unlocks at once.
    if (!widget.enabled && _locked) _locked = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.enabled) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // The biometric prompt itself backgrounds the app on some devices;
        // that must not count as leaving.
        if (!_authenticating) _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null &&
            DateTime.now().difference(since) >= widget.relockAfter) {
          setState(() => _locked = true);
          _unlock();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _unlock() async {
    if (_authenticating || !mounted) return;
    _authenticating = true;
    final reason = context.l10n.appLockReason;
    final ok = await AppLockAuth.authenticate(reason);
    _authenticating = false;
    if (!mounted) return;
    if (ok) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Offstage rather than absent: the app keeps its state underneath.
        Offstage(offstage: _locked, child: widget.child),
        if (_locked) _LockScreen(onUnlock: _unlock),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 72, color: scheme.primary),
              const SizedBox(height: 24),
              Text(
                context.l10n.appTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.appLocked,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.fingerprint),
                label: Text(context.l10n.unlock),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
