import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Conduit's bridge to a native `UIMenu` / `UIAlertController` presenter,
/// without its native half: luci-mobile does not ship that Swift code yet.
///
/// [isAvailable] is false, so the platform UI layer takes its own fallbacks
/// (the package's native popup button, or a Flutter menu) instead of asking
/// this. The methods keep Conduit's contract for any caller that does ask:
/// context menus report that they cannot initialize, and presentation fails
/// the way a native error would, so callers fall back rather than reading
/// the result as a dismissal.
class IosNativeDropdownBridge {
  IosNativeDropdownBridge._();

  static final IosNativeDropdownBridge instance = IosNativeDropdownBridge._();

  /// Whether the native presenter exists in this app.
  bool get isAvailable => false;

  Future<bool> initializeContextMenu() async => false;

  Future<String?> showContextMenu({
    required int requestId,
    required Rect sourceRect,
    required List<IosNativeDropdownOption> options,
    required Uint8List previewPng,
  }) async => throw UnsupportedError('No native context menu in this app');

  Future<void> cancelContextMenu(int requestId) async {}

  Future<String?> show({
    required List<IosNativeDropdownOption> options,
    String? title,
    String? message,
    String? cancelLabel,
    Rect? sourceRect,
    bool rethrowErrors = false,
  }) async {
    if (rethrowErrors) {
      throw UnsupportedError('No native dropdown presenter in this app');
    }
    return null;
  }

  Future<String?> showFromContext({
    required BuildContext context,
    required List<IosNativeDropdownOption> options,
    String? title,
    String? message,
    String? cancelLabel,
    bool rethrowErrors = false,
  }) => show(
    options: options,
    title: title,
    message: message,
    cancelLabel: cancelLabel,
    rethrowErrors: rethrowErrors,
  );
}

class IosNativeDropdownOption {
  const IosNativeDropdownOption({
    required this.id,
    required this.label,
    this.subtitle,
    this.sfSymbol,
    this.enabled = true,
    this.destructive = false,
  });

  final String id;
  final String label;
  final String? subtitle;
  final String? sfSymbol;
  final bool enabled;
  final bool destructive;
}
