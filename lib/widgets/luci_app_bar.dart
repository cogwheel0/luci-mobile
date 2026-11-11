import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

class LuciAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final bool centerTitle;
  final bool showBack;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final double elevation;

  const LuciAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.centerTitle = true,
    this.showBack = false,
    this.actions,
    this.backgroundColor,
    this.elevation = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformUiCapabilities.isIOS) return _buildCupertino(context);
    final theme = Theme.of(context);
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: backgroundColor ?? theme.colorScheme.surface,
      elevation: elevation,
      scrolledUnderElevation: elevation,
      centerTitle: centerTitle,
      titleSpacing: 16.0,
      leading: showBack
          ? IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: theme.colorScheme.onSurface,
              ),
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: context.l10n.back,
            )
          : null,
      title:
          titleWidget ??
          (title != null
              ? Text(
                  title!,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                )
              : null),
      actions: actions,
      shadowColor: theme.shadowColor,
      surfaceTintColor: backgroundColor ?? theme.colorScheme.surface,
      systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).appBarTheme.systemOverlayStyle
                ?.copyWith(statusBarBrightness: Brightness.dark)
          : Theme.of(context).appBarTheme.systemOverlayStyle
                ?.copyWith(statusBarBrightness: Brightness.light),
    );
  }

  /// The iOS navigation bar: translucent, its title centred, the system
  /// back chevron, and the actions trailing.
  Widget _buildCupertino(BuildContext context) {
    final trailing = actions;
    return CupertinoNavigationBar(
      automaticallyImplyLeading: false,
      automaticallyImplyMiddle: false,
      // The page's own colour, slightly translucent so iOS still blurs what
      // passes under it: the Cupertino default (white, or black in dark
      // mode) read as a band across the Material page below.
      backgroundColor:
          backgroundColor ??
          Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      leading: showBack
          ? CupertinoNavigationBarBackButton(
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      middle: titleWidget ?? (title != null ? Text(title!) : null),
      trailing: trailing == null || trailing.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: trailing),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(
    PlatformUiCapabilities.isIOS
        ? kMinInteractiveDimensionCupertino
        : kToolbarHeight,
  );
}

/// An action in [LuciAppBar.actions]: a Liquid Glass circle in the iOS 26
/// navigation bar, a plain tinted symbol in earlier iOS, and an IconButton
/// on Android. [tooltip] names it for assistive technology everywhere.
class LuciAppBarAction extends StatelessWidget {
  const LuciAppBarAction({
    super.key,
    required this.sfSymbol,
    required this.materialIcon,
    required this.tooltip,
    required this.onPressed,
  });

  final String sfSymbol;
  final IconData materialIcon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!PlatformUiCapabilities.isIOS) {
      return AdaptiveButton.sfSymbol(
        onPressed: onPressed,
        sfSymbol: SFSymbol(sfSymbol),
        materialIcon: materialIcon,
        semanticLabel: tooltip,
        style: AdaptiveButtonStyle.plain,
      );
    }
    // Sized as Conduit's navigation bar actions are.
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: AdaptiveButton.sfSymbol(
        onPressed: onPressed,
        sfSymbol: SFSymbol(sfSymbol),
        semanticLabel: tooltip,
        style: PlatformUiCapabilities.usesNativeIOS26
            ? AdaptiveButtonStyle.glass
            : AdaptiveButtonStyle.plain,
        minSize: const Size.square(36),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(18),
        useSmoothRectangleBorder: false,
      ),
    );
  }
}

class LuciSectionHeader extends StatelessWidget {
  final String title;
  const LuciSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: LuciSpacing.md,
        right: LuciSpacing.md,
        top: LuciSpacing.xl,
        bottom: LuciSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: LuciTextStyles.sectionHeader(context),
            ),
          ),
        ],
      ),
    );
  }
}

class LuciErrorDisplay extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;
  final bool showRetry;

  const LuciErrorDisplay({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.showRetry = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LuciSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon ?? Icons.error_outline_rounded,
              color: colorScheme.error,
              size: 64,
            ),
            const SizedBox(height: LuciSpacing.lg),
            Text(
              title,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (showRetry || onAction != null) ...[
              const SizedBox(height: LuciSpacing.xl),
              if (showRetry)
                AdaptiveButton(
                  onPressed: onAction,
                  label: actionLabel ?? context.l10n.retry,
                  sfSymbol: const SFSymbol('arrow.clockwise'),
                  materialIcon: Icons.refresh_rounded,
                  padding: const EdgeInsets.symmetric(
                    horizontal: LuciSpacing.lg,
                    vertical: 12,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class LuciEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const LuciEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LuciSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              size: 64,
            ),
            const SizedBox(height: LuciSpacing.lg),
            Text(
              title,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LuciSpacing.sm),
            Text(
              message,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (onAction != null) ...[
              const SizedBox(height: LuciSpacing.lg),
              AdaptiveButton(
                onPressed: onAction,
                label: actionLabel ?? context.l10n.add,
                sfSymbol: const SFSymbol('plus'),
                materialIcon: Icons.add_rounded,
                padding: const EdgeInsets.symmetric(
                  horizontal: LuciSpacing.lg,
                  vertical: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LuciLoadingWidget extends StatelessWidget {
  const LuciLoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: CircularProgressIndicator(
        color: colorScheme.primary,
        strokeWidth: 3,
      ),
    );
  }
}

/// Copies [value] and says so.
///
/// One copy of the gesture, because the four that grew separately disagreed
/// on the wording and one of them put the copied value in the toast.
Future<void> copyToClipboard(
  BuildContext context,
  String value, {
  required String label,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = context.l10n.copiedToClipboard(label);
  await Clipboard.setData(ClipboardData(text: value));
  messenger.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}
