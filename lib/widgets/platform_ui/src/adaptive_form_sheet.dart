import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/gestures.dart';
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
      // _FormSheetChrome draws it instead, inside the area it keeps a busy
      // form from being dragged by.
      showDragHandle: false,
      useSafeArea: material.useSafeArea,
      shape: material.shape,
      builder: (context) => _FormSheetChrome(
        bottomSheet: true,
        showDragHandle: material.showDragHandle,
        child: builder(context),
      ),
    );
  }
  return showCupertinoSheet<T>(
    context: context,
    // The page underneath, and the sheet's own buttons on iOS 26, are
    // native views that the transition has to account for.
    hasPlatformViews: PlatformUiCapabilities.usesNativeIOS26,
    scrollableBuilder: (context, controller) =>
        _FormSheetChrome(controller: controller, child: builder(context)),
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
    _AdaptiveFormSheetScope.reportBusy(context, busy);
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
              // The sheet's controller turns a drag down at the top into
              // dragging the sheet away. While busy the form holds still,
              // and the drag goes to _FormSheetChrome, which refuses it.
              physics: busy ? const NeverScrollableScrollPhysics() : null,
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

/// Whether the form in a sheet is busy: written by its [AdaptiveFormSheet]
/// as it builds, and read by [_FormSheetChrome] when a drag begins, so it
/// needs no rebuild of its own.
class _BusyFlag {
  bool value = false;
}

/// What a form sheet's route wraps the form in.
///
/// Dragging a sheet down closes it with `Navigator.pop`, on Android and on
/// iOS, which a busy form's [PopScope] cannot refuse. While the form says
/// it is busy, a drag recognizer here joins the gesture and, being deeper
/// than the sheet's own, takes it. It also draws a Material bottom sheet's
/// drag handle, which the route would otherwise draw outside its reach.
class _FormSheetChrome extends StatefulWidget {
  const _FormSheetChrome({
    this.controller,
    this.bottomSheet = false,
    this.showDragHandle = false,
    required this.child,
  });

  final ScrollController? controller;
  final bool bottomSheet;
  final bool showDragHandle;
  final Widget child;

  @override
  State<_FormSheetChrome> createState() => _FormSheetChromeState();
}

class _FormSheetChromeState extends State<_FormSheetChrome> {
  final _busy = _BusyFlag();

  static void _ignore(Object? _) {}

  @override
  Widget build(BuildContext context) {
    var sheet = widget.child;
    if (widget.showDragHandle) {
      // Laid out as BottomSheet lays out its own handle.
      sheet = Stack(
        alignment: Alignment.topCenter,
        children: [
          const _FormSheetDragHandle(),
          Padding(
            padding: const EdgeInsets.only(top: kMinInteractiveDimension),
            child: sheet,
          ),
        ],
      );
    }
    return _AdaptiveFormSheetScope(
      controller: widget.controller,
      bottomSheet: widget.bottomSheet,
      busy: _busy,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _BusyDragRecognizer:
              GestureRecognizerFactoryWithHandlers<_BusyDragRecognizer>(
                () => _BusyDragRecognizer(() => _busy.value),
                (recognizer) => recognizer
                  ..onStart = _ignore
                  ..onUpdate = _ignore
                  ..onEnd = _ignore,
              ),
        },
        child: sheet,
      ),
    );
  }
}

/// A vertical drag that takes part only while [blocking] says so, and then
/// does nothing.
class _BusyDragRecognizer extends VerticalDragGestureRecognizer {
  _BusyDragRecognizer(this.blocking);

  final bool Function() blocking;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      blocking() && super.isPointerAllowed(event);
}

/// Material 3's bottom sheet drag handle, as BottomSheet draws it, except
/// that dismissing it from accessibility services asks the route, so a busy
/// form's [PopScope] can refuse.
class _FormSheetDragHandle extends StatelessWidget {
  const _FormSheetDragHandle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheetTheme = theme.bottomSheetTheme;
    final size = sheetTheme.dragHandleSize ?? const Size(32, 4);
    return Semantics(
      label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      container: true,
      button: true,
      onTap: () => Navigator.maybePop(context),
      child: SizedBox(
        width: math.max(size.width, kMinInteractiveDimension),
        height: math.max(size.height, kMinInteractiveDimension),
        child: Center(
          child: Container(
            key: const ValueKey('adaptive-form-sheet-drag-handle'),
            width: size.width,
            height: size.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size.height / 2),
              color:
                  WidgetStateProperty.resolveAs<Color?>(
                    sheetTheme.dragHandleColor,
                    const <WidgetState>{},
                  ) ??
                  theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// What the form's frame needs from how it was shown: on iOS the sheet's
/// scroll controller, so dragging the content down at its top drags the
/// sheet, on Android whether it is in a bottom sheet, and on either where to
/// say it is busy.
class _AdaptiveFormSheetScope extends InheritedWidget {
  const _AdaptiveFormSheetScope({
    this.controller,
    this.bottomSheet = false,
    required this.busy,
    required super.child,
  });

  final ScrollController? controller;
  final bool bottomSheet;
  final _BusyFlag busy;

  static _AdaptiveFormSheetScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AdaptiveFormSheetScope>();

  static ScrollController? maybeControllerOf(BuildContext context) =>
      _of(context)?.controller;

  static bool isBottomSheet(BuildContext context) =>
      _of(context)?.bottomSheet ?? false;

  /// Tells the sheet whether the form is busy. A plain write, read when a
  /// drag begins: nothing needs to rebuild for it.
  static void reportBusy(BuildContext context, bool busy) {
    context
            .getInheritedWidgetOfExactType<_AdaptiveFormSheetScope>()
            ?.busy
            .value =
        busy;
  }

  @override
  bool updateShouldNotify(_AdaptiveFormSheetScope oldWidget) =>
      controller != oldWidget.controller ||
      bottomSheet != oldWidget.bottomSheet ||
      busy != oldWidget.busy;
}
