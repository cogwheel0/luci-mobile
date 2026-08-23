import 'package:flutter/material.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';

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
          ? Theme.of(context).appBarTheme.systemOverlayStyle?.copyWith(
              statusBarBrightness: Brightness.dark,
            )
          : Theme.of(context).appBarTheme.systemOverlayStyle?.copyWith(
              statusBarBrightness: Brightness.light,
            ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
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
                ElevatedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(actionLabel ?? context.l10n.retry),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: LuciSpacing.lg,
                      vertical: 12,
                    ),
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
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel ?? context.l10n.add),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: LuciSpacing.lg,
                    vertical: 12,
                  ),
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
