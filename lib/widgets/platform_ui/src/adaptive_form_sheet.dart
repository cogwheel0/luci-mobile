import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import 'adaptive_controls.dart';
import 'platform_ui_capabilities.dart';

/// Shows a small form: a Material dialog on Android, and on iOS a sheet
/// that slides up over the page. [builder] returns an [AdaptiveFormSheet].
///
/// Completes with the value the form pops with, or null when it is
/// cancelled, dismissed, or dragged away.
Future<T?> showAdaptiveFormSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  if (!PlatformUiCapabilities.isIOS) {
    return showDialog<T>(context: context, builder: builder);
  }
  return showCupertinoSheet<T>(
    context: context,
    // The page underneath, and the sheet's own buttons on iOS 26, are
    // native views that the transition has to account for.
    hasPlatformViews: PlatformUiCapabilities.usesNativeIOS26,
    scrollableBuilder: (context, controller) => _AdaptiveFormSheetScope(
      controller: controller,
      child: builder(context),
    ),
  );
}

/// A form's frame, for [showAdaptiveFormSheet].
///
/// On Android it is the Material dialog luci-mobile's forms were: [title],
/// [child] as the content, and a Cancel and a filled confirm button. On iOS
/// it is a sheet page with Cancel and the confirm action in its navigation
/// bar: an ✕ and a prominent ✓ in Liquid Glass on iOS 26, and text buttons
/// before. Either way the confirm action is disabled while [onConfirm] is
/// null, and shows progress while [busy].
class AdaptiveFormSheet extends StatelessWidget {
  const AdaptiveFormSheet({
    super.key,
    required this.title,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onConfirm,
    required this.child,
    this.busy = false,
  });

  final String title;
  final String cancelLabel;
  final String confirmLabel;

  /// Confirms the form, typically popping it with its result.
  final VoidCallback? onConfirm;

  /// The form's fields.
  final Widget child;

  /// The confirmation is under way: confirming is disabled and shows
  /// progress, and cancelling is disabled.
  final bool busy;

  void _cancel(BuildContext context) => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final confirm = busy ? null : onConfirm;
    if (!PlatformUiCapabilities.isIOS) {
      // While busy, neither the barrier nor Back may close it.
      return PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: child),
          actions: [
            TextButton(
              onPressed: busy ? null : () => _cancel(context),
              child: Text(cancelLabel),
            ),
            FilledButton(
              onPressed: confirm,
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(confirmLabel),
            ),
          ],
        ),
      );
    }
    final theme = Theme.of(context);
    return PopScope(
      canPop: !busy,
      child: CupertinoPageScaffold(
        backgroundColor: theme.colorScheme.surface,
        navigationBar: CupertinoNavigationBar(
          automaticallyImplyLeading: false,
          automaticallyImplyMiddle: false,
          backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.94),
          leading: _cancelButton(context),
          middle: Text(title),
          trailing: _confirmButton(context, confirm),
        ),
        child: SafeArea(
          // The forms' Material fields need a Material ancestor, which the
          // Material dialog gave them and a Cupertino sheet does not.
          child: Material(
            type: MaterialType.transparency,
            child: ListView(
              controller: _AdaptiveFormSheetScope.maybeOf(context),
              padding: const EdgeInsets.all(16),
              children: [child],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cancelButton(BuildContext context) {
    final onPressed = busy ? null : () => _cancel(context);
    if (PlatformUiCapabilities.usesNativeIOS26) {
      return AdaptiveButton.sfSymbol(
        onPressed: onPressed,
        sfSymbol: const SFSymbol('xmark'),
        semanticLabel: cancelLabel,
        minSize: const Size.square(44),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(22),
        useSmoothRectangleBorder: false,
      );
    }
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Text(cancelLabel),
    );
  }

  Widget _confirmButton(BuildContext context, VoidCallback? confirm) {
    if (busy) {
      return Semantics(
        label: confirmLabel,
        child: const SizedBox.square(
          dimension: 44,
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    }
    if (PlatformUiCapabilities.usesNativeIOS26) {
      return AdaptiveButton.sfSymbol(
        onPressed: confirm,
        sfSymbol: const SFSymbol('checkmark'),
        semanticLabel: confirmLabel,
        style: AdaptiveButtonStyle.prominentGlass,
        minSize: const Size.square(44),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(22),
        useSmoothRectangleBorder: false,
      );
    }
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: confirm,
      child: Text(
        confirmLabel,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The sheet's scroll controller, so dragging the content down at its top
/// drags the sheet.
class _AdaptiveFormSheetScope extends InheritedWidget {
  const _AdaptiveFormSheetScope({
    required this.controller,
    required super.child,
  });

  final ScrollController controller;

  static ScrollController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_AdaptiveFormSheetScope>()
      ?.controller;

  @override
  bool updateShouldNotify(_AdaptiveFormSheetScope oldWidget) =>
      controller != oldWidget.controller;
}
