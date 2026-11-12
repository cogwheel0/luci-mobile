import 'package:material_ui/material_ui.dart';

import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

/// A grouped card of hub entries, divided like a settings list.
class LuciHubSection extends StatelessWidget {
  const LuciHubSection({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    if (PlatformUiCapabilities.isIOS) {
      // An inset group, as iOS Settings lists its entries, the hairlines
      // starting at the titles, past the icons.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: LuciSpacing.md),
        child: AdaptiveFormSection(separatorIndent: 72, children: tiles),
      );
    }
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(
        horizontal: LuciSpacing.md,
        vertical: LuciSpacing.sm,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
      ),
      child: Column(
        children: ListTile.divideTiles(context: context, tiles: tiles).toList(),
      ),
    );
  }
}

/// One entry in a hub.
///
/// [subtitle] is not decoration: a hub row that only names a destination makes
/// the user open it to find out what is there. Saying what it contains is how
/// the screen answers "where can I go, and what's in it?".
///
/// An entry the router cannot support stays visible and [enabled] false with
/// the reason in its subtitle, rather than disappearing — a menu that differs
/// between routers with no explanation reads as a bug.
class LuciHubTile extends StatelessWidget {
  const LuciHubTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.onTap,
    this.enabled = true,
    this.titleColor,
    this.subtitleColor,
    this.showSpinner = false,
    this.trailing,
    this.subtitleMaxLines,
    this.destructive = false,
  });

  /// Whether the entry destroys or ends something, such as signing out: on
  /// iOS its title is red and it has no chevron, as it opens no page.
  final bool destructive;

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final VoidCallback? onTap;
  final bool enabled;
  final Color? titleColor;
  final Color? subtitleColor;
  final bool showSpinner;
  final Widget? trailing;

  /// Lines the subtitle may take before it is cut with an ellipsis; null
  /// for as many as it needs.
  final int? subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = iconColor ?? theme.colorScheme.primary;

    Widget leadingIcon = Icon(
      icon,
      color: tint,
      size: 24,
      semanticLabel: title,
    );
    if (showSpinner) {
      leadingIcon = _SpinningIcon(icon: icon, color: tint, label: title);
    }
    final leading = Container(
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(10),
      child: leadingIcon,
    );

    if (PlatformUiCapabilities.isIOS) {
      // A row of an iOS Settings list: a chevron where it opens a page.
      return Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: AdaptiveListRow(
          leading: ExcludeSemantics(child: leading),
          title: title,
          subtitle: subtitle,
          trailing: trailing,
          destructive: destructive,
          showChevron: enabled && onTap != null && !destructive,
          onTap: enabled ? onTap : null,
        ),
      );
    }
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: ListTile(
        leading: leading,
        title: Text(
          title,
          style: titleColor != null
              ? LuciTextStyles.cardTitle(context).copyWith(color: titleColor)
              : LuciTextStyles.cardTitle(context),
          semanticsLabel: title,
        ),
        subtitle: Text(
          subtitle,
          style: subtitleColor != null
              ? LuciTextStyles.cardSubtitle(context)
                    .copyWith(color: subtitleColor)
              : LuciTextStyles.cardSubtitle(context),
          semanticsLabel: subtitle,
          maxLines: subtitleMaxLines,
          overflow: subtitleMaxLines == null ? null : TextOverflow.ellipsis,
        ),
        trailing: trailing,
        enabled: enabled,
        onTap: enabled ? onTap : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LuciSpacing.lg,
          vertical: 10,
        ),
        hoverColor: theme.colorScheme.primary.withValues(alpha: 0.04),
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.08),
        minVerticalPadding: LuciSpacing.md,
        minLeadingWidth: 0,
        visualDensity: VisualDensity.standard,
      ),
    );
  }
}

/// A continuously rotating icon, for a hub entry whose action is in progress.
class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A steady rotation reads as "still working"; reduced-motion users get the
    // static icon, since the spinner is reassurance rather than information.
    if (MediaQuery.disableAnimationsOf(context)) {
      return Icon(
        widget.icon,
        color: widget.color,
        size: 24,
        semanticLabel: widget.label,
      );
    }
    return RotationTransition(
      turns: _controller,
      child: Icon(
        widget.icon,
        color: widget.color,
        size: 24,
        semanticLabel: widget.label,
      ),
    );
  }
}
