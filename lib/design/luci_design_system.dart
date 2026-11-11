import 'package:material_ui/material_ui.dart';

/// Standardized spacing constants for consistent layout
class LuciSpacing {
  static const double xs = 4.0; // Micro spacing
  static const double sm = 8.0; // Small spacing
  static const double md = 16.0; // Standard spacing
  static const double lg = 24.0; // Large spacing
  static const double xl = 32.0; // Extra large spacing
  static const double xxl = 48.0; // Section spacing
}

/// Standardized text styles for consistent typography
class LuciTextStyles {
  static TextStyle sectionHeader(BuildContext context) {
    return Theme.of(context).textTheme.titleSmall!.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.2,
    );
  }

  static TextStyle cardTitle(BuildContext context) {
    return Theme.of(context).textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  static TextStyle cardSubtitle(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall!.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
    );
  }

  static TextStyle detailLabel(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall!
        .copyWith(color: Theme.of(context).colorScheme.onSurface);
  }

  static TextStyle detailValue(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontWeight: FontWeight.w500,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  static TextStyle errorText(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: Theme.of(context).colorScheme.onErrorContainer);
  }
}

/// Standardized animation constants for consistent motion
class LuciAnimations {
  // Standard durations
  static const Duration fast = Duration(
    milliseconds: 200,
  ); // Micro interactions
  static const Duration standard = Duration(
    milliseconds: 400,
  ); // Card expansions
  static const Duration slow = Duration(milliseconds: 600); // Page transitions
  static const Duration chart = Duration(
    milliseconds: 800,
  ); // Data visualizations

  // Standard curves
  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;
  static const Curve elastic = Curves.elasticOut;
}

/// Standardized card design system
class LuciCardStyles {
  static BorderRadius standardRadius = BorderRadius.circular(16.0);
  static BorderRadius largeRadius = BorderRadius.circular(20.0);

  static BoxDecoration standardCard(
    BuildContext context, {
    bool isElevated = false,
    bool isSelected = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: colorScheme.surface,
      borderRadius: standardRadius,
      border: Border.all(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.3)
            : colorScheme.outlineVariant.withValues(alpha: 0.2),
        width: isSelected ? 2 : 1,
      ),
      boxShadow: isElevated
          ? [
              BoxShadow(
                color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ]
          : null,
    );
  }

  static Widget standardCardWrapper({
    required BuildContext context,
    required Widget child,
    bool isElevated = false,
    bool isSelected = false,
    VoidCallback? onTap,
    EdgeInsets? margin,
    EdgeInsets? padding,
  }) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: LuciSpacing.sm),
      decoration: standardCard(
        context,
        isElevated: isElevated,
        isSelected: isSelected,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: standardRadius,
        child: InkWell(
          borderRadius: standardRadius,
          onTap: onTap,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(LuciSpacing.md),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Standardized status indicators
class LuciStatusIndicators {
  static Widget statusDot(
    BuildContext context,
    bool isActive, {
    double size = 10.0,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isActive ? Colors.green : colorScheme.error,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.surface, width: 1.5),
      ),
    );
  }

  static Widget statusChip(BuildContext context, String label, bool isActive) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label),
      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: isActive ? colorScheme.onPrimary : colorScheme.onError,
      ),
      backgroundColor: isActive
          ? colorScheme.primary.withValues(alpha: 0.8)
          : colorScheme.error.withValues(alpha: 0.7),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}
