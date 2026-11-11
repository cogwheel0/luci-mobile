import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import 'adaptive_glass_controls.dart';
import 'platform_ui_capabilities.dart';
import 'placeholder_caret_gap.dart';
import 'ios_text_magnifier.dart';

enum AdaptiveSnackBarType { info, success, warning, error }

class AdaptiveSnackBar {
  AdaptiveSnackBar._();

  static OverlayEntry? _activeIOSEntry;

  /// Counts messages asked for, so one shown a frame late can tell that a
  /// newer one has replaced it.
  static int _latest = 0;

  static void show(
    BuildContext context, {
    required String message,
    AdaptiveSnackBarType type = AdaptiveSnackBarType.info,
    Duration duration = const Duration(seconds: 4),
    String? action,
    VoidCallback? onActionPressed,
  }) {
    final id = ++_latest;
    // A navigator's own context (kept by callers whose page may be gone by
    // the time they report) sits above that navigator's overlay.
    final contextOverlay = Overlay.maybeOf(context);
    final navigatorOverlay =
        contextOverlay ?? Navigator.maybeOf(context)?.overlay;
    final nativeDuration = _nativeDuration(duration);
    if (PlatformUiCapabilities.usesNativeIOS26 &&
        navigatorOverlay != null &&
        action == null &&
        nativeDuration != null) {
      // The toast replaces a banner left up by a longer message.
      _dismissIOSBanner();
      final style = switch (type) {
        AdaptiveSnackBarType.info => CNToastStyle.info,
        AdaptiveSnackBarType.success => CNToastStyle.success,
        AdaptiveSnackBarType.warning => CNToastStyle.warning,
        AdaptiveSnackBarType.error => CNToastStyle.error,
      };
      void showToast(BuildContext toastContext) => CNToast.show(
        context: toastContext,
        message: message,
        position: CNToastPosition.top,
        duration: nativeDuration,
        style: style,
      );
      if (contextOverlay != null) {
        showToast(context);
      } else {
        _withContextIn(navigatorOverlay, () => id == _latest, showToast);
      }
      return;
    }

    if (!PlatformUiCapabilities.isIOS) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      // As on iOS, the newest message replaces the one showing and any
      // waiting, so a long-lived one (a reboot in progress) cannot hold back
      // its result, even when they arrive while a bar is still closing.
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          _materialSnackBar(
            Theme.of(context),
            message: message,
            type: type,
            duration: duration,
            action: action,
            onActionPressed: onActionPressed,
          ),
        );
      return;
    }

    final overlay = contextOverlay ?? Navigator.maybeOf(context)?.overlay;
    if (overlay == null) return;
    _dismissIOSBanner();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _IOSBanner(
        message: message,
        type: type,
        duration: duration,
        action: action,
        onActionPressed: onActionPressed,
        onDismiss: () {
          if (entry.mounted) entry.remove();
          if (identical(_activeIOSEntry, entry)) _activeIOSEntry = null;
        },
      ),
    );
    _activeIOSEntry = entry;
    overlay.insert(entry);
  }

  static void _dismissIOSBanner() {
    final entry = _activeIOSEntry;
    _activeIOSEntry = null;
    // Inserted this frame, it has not mounted yet but is in the overlay;
    // a dismissed one has already cleared this reference.
    entry?.remove();
  }

  /// Calls [use] with a context inside [overlay], from a zero-size entry
  /// inserted for the purpose: CNToast finds its overlay from a context,
  /// and a navigator's own context sits above that navigator's overlay.
  /// That is a frame later, so [stillWanted] is asked first: a newer message
  /// asked for meanwhile replaces this one rather than following it.
  static void _withContextIn(
    OverlayState overlay,
    bool Function() stillWanted,
    void Function(BuildContext context) use,
  ) {
    var used = false;
    late final OverlayEntry probe;
    probe = OverlayEntry(
      builder: (probeContext) {
        if (!used) {
          used = true;
          // Not during build: showing inserts the toast's own entry.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (stillWanted() && probeContext.mounted) use(probeContext);
            if (probe.mounted) probe.remove();
          });
        }
        return const SizedBox.shrink();
      },
    );
    overlay.insert(probe);
  }

  /// luci-mobile's Material snackbars: information in the theme's plain
  /// bar; a success, warning or error floats, in green with a check, in
  /// orange, or in the theme's error colour.
  static SnackBar _materialSnackBar(
    ThemeData theme, {
    required String message,
    required AdaptiveSnackBarType type,
    required Duration duration,
    String? action,
    VoidCallback? onActionPressed,
  }) {
    final scheme = theme.colorScheme;
    final (
      Color? background,
      Color? foreground,
      IconData? icon,
    ) = switch (type) {
      AdaptiveSnackBarType.info => (null, null, null),
      AdaptiveSnackBarType.success => (
        Colors.green.shade700,
        Colors.white,
        Icons.check_circle,
      ),
      AdaptiveSnackBarType.warning => (
        Colors.orange.shade700,
        Colors.white,
        Icons.warning_amber_rounded,
      ),
      AdaptiveSnackBarType.error => (scheme.error, scheme.onError, null),
    };
    final text = Text(
      message,
      style: foreground == null ? null : TextStyle(color: foreground),
    );
    final floating = type != AdaptiveSnackBarType.info;
    return SnackBar(
      content: icon == null
          ? text
          : Row(
              children: [
                Icon(icon, color: foreground, size: 20),
                const SizedBox(width: 8),
                Expanded(child: text),
              ],
            ),
      duration: duration,
      backgroundColor: background,
      behavior: floating ? SnackBarBehavior.floating : null,
      shape: floating
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
          : null,
      action: action == null
          ? null
          : SnackBarAction(
              label: action,
              textColor: foreground,
              onPressed: onActionPressed ?? () {},
            ),
    );
  }

  /// The native toast's nearest length; past six seconds the Flutter banner
  /// shows instead, since it keeps any duration.
  static CNToastDuration? _nativeDuration(Duration value) {
    if (value <= const Duration(milliseconds: 2500)) {
      return CNToastDuration.short;
    }
    if (value <= const Duration(seconds: 4)) return CNToastDuration.medium;
    if (value <= const Duration(seconds: 6)) return CNToastDuration.long;
    return null;
  }

  /// Keeps where to report a result that arrives after an await: through
  /// [context] while it is mounted, else through the root navigator, which
  /// outlives any page. Take it before the await.
  static AdaptiveSnackBarReporter reporter(BuildContext context) =>
      AdaptiveSnackBarReporter._(
        context,
        Navigator.of(context, rootNavigator: true).context,
      );
}

/// Reports through a page while it is mounted, else through the root
/// navigator. From [AdaptiveSnackBar.reporter].
class AdaptiveSnackBarReporter {
  AdaptiveSnackBarReporter._(this._context, this._fallback);

  final BuildContext _context;
  final BuildContext _fallback;

  void show({
    required String message,
    AdaptiveSnackBarType type = AdaptiveSnackBarType.info,
    Duration duration = const Duration(seconds: 4),
    String? action,
    VoidCallback? onActionPressed,
  }) {
    final target = _context.mounted ? _context : _fallback;
    if (!target.mounted) return;
    AdaptiveSnackBar.show(
      target,
      message: message,
      type: type,
      duration: duration,
      action: action,
      onActionPressed: onActionPressed,
    );
  }
}

class _IOSBanner extends StatefulWidget {
  const _IOSBanner({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
    this.action,
    this.onActionPressed,
  });

  final String message;
  final AdaptiveSnackBarType type;
  final Duration duration;
  final String? action;
  final VoidCallback? onActionPressed;
  final VoidCallback onDismiss;

  @override
  State<_IOSBanner> createState() => _IOSBannerState();
}

class _IOSBannerState extends State<_IOSBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bannerColor = CupertinoColors.secondarySystemBackground.resolveFrom(
      context,
    );
    final tint = switch (widget.type) {
      AdaptiveSnackBarType.info => CupertinoColors.systemBlue,
      AdaptiveSnackBarType.success => CupertinoColors.systemGreen,
      AdaptiveSnackBarType.warning => CupertinoColors.systemOrange,
      AdaptiveSnackBarType.error => CupertinoColors.systemRed,
    };
    final icon = switch (widget.type) {
      AdaptiveSnackBarType.info => CupertinoIcons.info_circle_fill,
      AdaptiveSnackBarType.success => CupertinoIcons.check_mark_circled_solid,
      AdaptiveSnackBarType.warning =>
        CupertinoIcons.exclamationmark_triangle_fill,
      AdaptiveSnackBarType.error => CupertinoIcons.xmark_circle_fill,
    };
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        // Swiped up out of the way, as iOS banners are; it covers the
        // navigation bar while it shows.
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < 0) widget.onDismiss();
          },
          child: Semantics(
            liveRegion: true,
            onDismiss: widget.onDismiss,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: PlatformUiCapabilities.usesNativeIOS26
                    ? null
                    : bannerColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  if (PlatformUiCapabilities.usesNativeIOS26)
                    Positioned.fill(
                      child: AdaptiveGlassBackdrop(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: tint, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: TextStyle(
                              color: CupertinoColors.label.resolveFrom(context),
                            ),
                          ),
                        ),
                        if (widget.action != null)
                          CupertinoButton(
                            padding: const EdgeInsets.only(left: 10),
                            minimumSize: const Size(36, 36),
                            onPressed: () {
                              widget.onActionPressed?.call();
                              widget.onDismiss();
                            },
                            child: Text(widget.action!),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum AlertActionStyle {
  defaultAction,
  cancel,
  destructive,
  primary,
  secondary,
  success,
  warning,
  info,
  disabled,
}

class AlertAction {
  const AlertAction({
    required this.title,
    required this.onPressed,
    this.style = AlertActionStyle.defaultAction,
    this.enabled = true,
  });

  final String title;
  final VoidCallback onPressed;
  final AlertActionStyle style;
  final bool enabled;
}

class AdaptiveAlertDialogInput {
  const AdaptiveAlertDialogInput({
    required this.placeholder,
    this.initialValue,
    this.keyboardType,
    this.obscureText = false,
    this.autocorrect = true,
    this.maxLines = 1,
    this.maxLength,
  });

  final String placeholder;
  final String? initialValue;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool autocorrect;
  final int maxLines;
  final int? maxLength;
}

class AdaptiveAlertDialog {
  AdaptiveAlertDialog._();

  /// Asks a yes-or-no question: a native alert on iOS 26 and later, a
  /// Cupertino alert before, a Material dialog on Android. True only when
  /// the user picks [confirmLabel]; cancelling or dismissing is false.
  ///
  /// A [destructive] confirmation is red; otherwise it is the alert's
  /// default action, and Material's filled button.
  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    String? message,
    required String confirmLabel,
    required String cancelLabel,
    bool destructive = false,
  }) async {
    var confirmed = false;
    await show(
      context: context,
      title: title,
      message: message,
      actions: [
        AlertAction(
          title: cancelLabel,
          style: AlertActionStyle.cancel,
          onPressed: () {},
        ),
        AlertAction(
          title: confirmLabel,
          style: destructive
              ? AlertActionStyle.destructive
              : AlertActionStyle.primary,
          onPressed: () => confirmed = true,
        ),
      ],
    );
    return confirmed;
  }

  static Future<void> show({
    required BuildContext context,
    required String title,
    String? message,
    required List<AlertAction> actions,
  }) async {
    // CNAlert opens in the app theme's brightness (read through
    // LegacyDesignCompatibility), so a forced light or dark theme stays native.
    if (PlatformUiCapabilities.usesNativeIOS26 &&
        actions.any(_isEnabled) &&
        actions.where((a) => a.style == AlertActionStyle.cancel).length <= 1 &&
        actions.where((a) => a.style == AlertActionStyle.primary).length <= 1) {
      final presentedActions = List<AlertAction>.of(actions);
      final result = await CNAlert.show<int>(
        context: context,
        title: title,
        message: message,
        actions: [
          for (var index = 0; index < presentedActions.length; index++)
            CNAlertAction(
              label: presentedActions[index].title,
              value: index,
              isCancel:
                  presentedActions[index].style == AlertActionStyle.cancel,
              isDefault:
                  presentedActions[index].style == AlertActionStyle.primary,
              isDestructive:
                  presentedActions[index].style == AlertActionStyle.destructive,
              enabled: _isEnabled(presentedActions[index]),
            ),
        ],
      );
      if (!context.mounted) return;
      final index = result?.value;
      if (index != null && _isEnabled(presentedActions[index])) {
        presentedActions[index].onPressed();
      }
      return;
    }
    if (PlatformUiCapabilities.isIOS) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(title),
          content: message == null ? null : Text(message),
          actions: [
            for (final action in actions)
              CupertinoDialogAction(
                onPressed:
                    !action.enabled || action.style == AlertActionStyle.disabled
                    ? null
                    : () {
                        Navigator.of(dialogContext).pop();
                        action.onPressed();
                      },
                isDefaultAction: action.style == AlertActionStyle.primary,
                isDestructiveAction:
                    action.style == AlertActionStyle.destructive,
                child: Text(action.title),
              ),
          ],
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          for (final action in actions) _materialAction(dialogContext, action),
        ],
      ),
    );
  }

  /// A primary action is Material's filled button; the rest are text
  /// buttons, a destructive one in the error colour.
  static Widget _materialAction(
    BuildContext dialogContext,
    AlertAction action,
  ) {
    final onPressed = !_isEnabled(action)
        ? null
        : () {
            Navigator.of(dialogContext).pop();
            action.onPressed();
          };
    if (action.style == AlertActionStyle.primary) {
      return FilledButton(onPressed: onPressed, child: Text(action.title));
    }
    return TextButton(
      style: action.style == AlertActionStyle.destructive
          ? TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            )
          : null,
      onPressed: onPressed,
      child: Text(action.title),
    );
  }

  static bool _isEnabled(AlertAction action) =>
      action.enabled && action.style != AlertActionStyle.disabled;

  static Future<String?> inputShow({
    required BuildContext context,
    required String title,
    String? message,
    required List<AlertAction> actions,
    required AdaptiveAlertDialogInput input,
  }) async {
    final controller = TextEditingController(text: input.initialValue);
    ModalRoute<dynamic>? dialogRoute;
    try {
      if (PlatformUiCapabilities.isIOS) {
        return await showCupertinoDialog<String?>(
          context: context,
          builder: (dialogContext) {
            dialogRoute = ModalRoute.of(dialogContext);
            return CupertinoAlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message != null) Text(message),
                  const SizedBox(height: 10),
                  CupertinoTextField(
                    magnifierConfiguration: nativeIosTextMagnifierConfiguration,
                    controller: controller,
                    placeholder: placeholderClearOfCaret(input.placeholder),
                    keyboardType: input.keyboardType,
                    obscureText: input.obscureText,
                    autocorrect: input.autocorrect,
                    enableSuggestions: input.autocorrect,
                    smartDashesType: input.autocorrect
                        ? null
                        : SmartDashesType.disabled,
                    smartQuotesType: input.autocorrect
                        ? null
                        : SmartQuotesType.disabled,
                    maxLength: input.maxLength,
                    maxLines: input.maxLines,
                    autofocus: true,
                  ),
                ],
              ),
              actions: [
                for (final action in actions)
                  CupertinoDialogAction(
                    onPressed:
                        !action.enabled ||
                            action.style == AlertActionStyle.disabled
                        ? null
                        : () {
                            final isCancel =
                                action.style == AlertActionStyle.cancel;
                            Navigator.of(dialogContext)
                                .pop(isCancel ? null : controller.text);
                            action.onPressed();
                          },
                    isDefaultAction: action.style == AlertActionStyle.primary,
                    isDestructiveAction:
                        action.style == AlertActionStyle.destructive,
                    child: Text(action.title),
                  ),
              ],
            );
          },
        );
      }
      return await showDialog<String?>(
        context: context,
        builder: (dialogContext) {
          dialogRoute = ModalRoute.of(dialogContext);
          final field = TextField(
            magnifierConfiguration: nativeIosTextMagnifierConfiguration,
            controller: controller,
            keyboardType: input.keyboardType,
            obscureText: input.obscureText,
            autocorrect: input.autocorrect,
            enableSuggestions: input.autocorrect,
            smartDashesType: input.autocorrect
                ? null
                : SmartDashesType.disabled,
            smartQuotesType: input.autocorrect
                ? null
                : SmartQuotesType.disabled,
            maxLength: input.maxLength,
            maxLines: input.maxLines,
            autofocus: true,
            decoration: InputDecoration(hintText: input.placeholder),
          );
          return AlertDialog(
            title: Text(title),
            // Cupertino shows the message above the field; so does Material.
            content: message == null
                ? field
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message),
                      const SizedBox(height: 12),
                      field,
                    ],
                  ),
            actions: [
              for (final action in actions)
                TextButton(
                  style: action.style == AlertActionStyle.destructive
                      ? TextButton.styleFrom(
                          foregroundColor: Theme.of(dialogContext)
                              .colorScheme
                              .error,
                        )
                      : null,
                  onPressed:
                      !action.enabled ||
                          action.style == AlertActionStyle.disabled
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop(
                            action.style == AlertActionStyle.cancel
                                ? null
                                : controller.text,
                          );
                          action.onPressed();
                        },
                  child: Text(action.title),
                ),
            ],
          );
        },
      );
    } finally {
      // Pop completes before the closing animation unmounts the text field.
      await dialogRoute?.completed;
      controller.dispose();
    }
  }
}
