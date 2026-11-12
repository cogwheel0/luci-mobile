import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import 'adaptive_controls.dart';
import 'platform_ui_capabilities.dart';

/// How a form opened with [showAdaptiveFormSheet] shows on Android. iOS
/// always shows it as a sheet.
class AdaptiveFormMaterialPresentation {
  /// A Material dialog, for a small form.
  const AdaptiveFormMaterialPresentation.dialog()
    : bottomSheet = false,
      showDragHandle = false,
      useSafeArea = false,
      shape = null;

  /// A modal bottom sheet, for a longer form.
  const AdaptiveFormMaterialPresentation.bottomSheet({
    this.showDragHandle = true,
    this.useSafeArea = false,
    this.shape,
  }) : bottomSheet = true;

  final bool bottomSheet;
  final bool showDragHandle;
  final bool useSafeArea;
  final ShapeBorder? shape;
}

/// Shows a form: on Android a Material dialog or bottom sheet, as [material]
/// says, and on iOS a sheet that slides up over the page. [builder] returns
/// an [AdaptiveFormSheet]; a form that keeps a Material layout of its own on
/// Android may return that there instead.
///
/// Completes with the value the form pops with, or null when it is
/// cancelled, dismissed, or dragged away.
Future<T?> showAdaptiveFormSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  AdaptiveFormMaterialPresentation material =
      const AdaptiveFormMaterialPresentation.dialog(),
}) {
  if (!PlatformUiCapabilities.isIOS) {
    if (!material.bottomSheet) {
      return showDialog<T>(context: context, builder: builder);
    }
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: material.showDragHandle,
      useSafeArea: material.useSafeArea,
      shape: material.shape,
      builder: (context) =>
          _AdaptiveFormSheetScope(bottomSheet: true, child: builder(context)),
    );
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
/// On Android it is the Material dialog or bottom sheet luci-mobile's forms
/// were: [title] (and [subtitle]), [child] as the content, and a Cancel and
/// a filled confirm button, with the [destructiveLabel] action at the start
/// of a bottom sheet's row. On iOS it is a sheet page with Cancel and the
/// confirm action in its navigation bar: an ✕ and a prominent ✓ in Liquid
/// Glass on iOS 26, and text buttons before. The destructive action is a red
/// button under the fields there, as iOS puts "Forget This Network".
///
/// Either way the confirm action is disabled while [onConfirm] is null, and
/// shows progress while [busy].
class AdaptiveFormSheet extends StatelessWidget {
  const AdaptiveFormSheet({
    super.key,
    required this.title,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onConfirm,
    required this.child,
    this.subtitle,
    this.destructiveLabel,
    this.onDestructive,
    this.busy = false,
  }) : assert(
         (destructiveLabel == null) == (onDestructive == null),
         'A destructive action needs both a label and a callback.',
       );

  final String title;

  /// A line under the title: what the form is for, such as the radio a
  /// network is on.
  final String? subtitle;

  final String cancelLabel;
  final String confirmLabel;

  /// Confirms the form, typically popping it with its result.
  final VoidCallback? onConfirm;

  /// A destructive action beside confirming, such as removing what the form
  /// edits; null for none.
  final String? destructiveLabel;
  final VoidCallback? onDestructive;

  /// The form's fields.
  final Widget child;

  /// The confirmation is under way: confirming is disabled and shows
  /// progress, and cancelling and the destructive action are disabled.
  final bool busy;

  void _cancel(BuildContext context) => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final confirm = busy ? null : onConfirm;
    if (!PlatformUiCapabilities.isIOS) {
      // While busy, neither the barrier nor Back may close it.
      return PopScope(
        canPop: !busy,
        child: _AdaptiveFormSheetScope.isBottomSheet(context)
            ? _materialBottomSheet(context, confirm)
            : _materialDialog(context, confirm),
      );
    }
    final theme = Theme.of(context);
    final destructive = onDestructive;
    return PopScope(
      canPop: !busy,
      child: CupertinoPageScaffold(
        backgroundColor: theme.colorScheme.surface,
        navigationBar: CupertinoNavigationBar(
          automaticallyImplyLeading: false,
          automaticallyImplyMiddle: false,
          backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.94),
          leading: _cancelButton(context),
          middle: _cupertinoTitle(context),
          trailing: _confirmButton(context, confirm),
        ),
        child: SafeArea(
          // The forms' Material fields need a Material ancestor, which the
          // Material dialog gave them and a Cupertino sheet does not.
          child: Material(
            type: MaterialType.transparency,
            child: ListView(
              controller: _AdaptiveFormSheetScope.maybeControllerOf(context),
              padding: const EdgeInsets.all(16),
              children: [
                child,
                if (destructive != null) ...[
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: AdaptiveButton(
                      onPressed: busy ? null : destructive,
                      label: destructiveLabel!,
                      style: AdaptiveButtonStyle.tinted,
                      color: CupertinoColors.systemRed.resolveFrom(context),
                      size: AdaptiveButtonSize.large,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _materialDialog(BuildContext context, VoidCallback? confirm) {
    return AlertDialog(
      title: subtitle == null
          ? Text(title)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(title), _materialSubtitle(context)],
            ),
      content: SingleChildScrollView(child: child),
      actions: [
        if (onDestructive != null)
          TextButton(
            onPressed: busy ? null : onDestructive,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(destructiveLabel!),
          ),
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
    );
  }

  Widget _materialBottomSheet(BuildContext context, VoidCallback? confirm) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                // Large text reads too loose at default tracking.
                letterSpacing: -0.4,
              ),
            ),
            if (subtitle != null) _materialSubtitle(context),
            const SizedBox(height: 24),
            child,
            const SizedBox(height: 16),
            Row(
              children: [
                if (onDestructive != null)
                  AdaptiveButton(
                    onPressed: busy ? null : onDestructive,
                    label: destructiveLabel!,
                    style: AdaptiveButtonStyle.plain,
                    color: theme.colorScheme.error,
                  ),
                const Spacer(),
                AdaptiveButton(
                  onPressed: busy ? null : () => _cancel(context),
                  label: cancelLabel,
                  style: AdaptiveButtonStyle.plain,
                ),
                const SizedBox(width: 8),
                AdaptiveButton(
                  onPressed: confirm,
                  busy: busy,
                  label: confirmLabel,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _materialSubtitle(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      subtitle!,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
      ),
    );
  }

  /// The title, with [subtitle] under it as iOS 26 navigation bars show one.
  Widget _cupertinoTitle(BuildContext context) {
    if (subtitle == null) return Text(title);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(
          subtitle!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ],
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

/// What the form's frame needs from how it was shown: on iOS the sheet's
/// scroll controller, so dragging the content down at its top drags the
/// sheet, and on Android whether it is in a bottom sheet.
class _AdaptiveFormSheetScope extends InheritedWidget {
  const _AdaptiveFormSheetScope({
    this.controller,
    this.bottomSheet = false,
    required super.child,
  });

  final ScrollController? controller;
  final bool bottomSheet;

  static _AdaptiveFormSheetScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AdaptiveFormSheetScope>();

  static ScrollController? maybeControllerOf(BuildContext context) =>
      _of(context)?.controller;

  static bool isBottomSheet(BuildContext context) =>
      _of(context)?.bottomSheet ?? false;

  @override
  bool updateShouldNotify(_AdaptiveFormSheetScope oldWidget) =>
      controller != oldWidget.controller ||
      bottomSheet != oldWidget.bottomSheet;
}
