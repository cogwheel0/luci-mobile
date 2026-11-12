import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:cupertino_ui/cupertino_ui.dart' hide RefreshCallback;
import 'package:material_ui/material_ui.dart';

import 'platform_ui_capabilities.dart';

/// Progress remains a value in [0, 1]; null means work with no known total.
class AdaptiveProgressIndicator extends StatelessWidget {
  const AdaptiveProgressIndicator({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.strokeWidth = 4,
    this.semanticLabel,
    this.semanticValue,
  }) : linear = false,
       minHeight = null,
       radius = null;

  /// A horizontal bar. On iOS 26 and later a bar with a known [value] is the
  /// native `UIProgressView`, which has its own height and track colour, so
  /// [minHeight] applies to the Flutter bar only; a [backgroundColor] or a
  /// [semanticValue] keeps the Flutter bar.
  const AdaptiveProgressIndicator.linear({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.minHeight,
    this.semanticLabel,
    this.semanticValue,
  }) : linear = true,
       strokeWidth = 4,
       radius = null;

  /// The iOS activity spinner on every platform, [radius] points in radius.
  const AdaptiveProgressIndicator.activity({
    super.key,
    double this.radius = 10,
    this.color,
  }) : linear = false,
       value = null,
       backgroundColor = null,
       strokeWidth = 4,
       minHeight = null,
       semanticLabel = null,
       semanticValue = null;

  final bool linear;
  final double? value;
  final Color? color;
  final Color? backgroundColor;
  final double strokeWidth;
  final double? minHeight;
  final double? radius;
  final String? semanticLabel;
  final String? semanticValue;

  @override
  Widget build(BuildContext context) {
    if (radius case final radius?) {
      return CupertinoActivityIndicator(radius: radius, color: color);
    }
    if (linear) {
      if (value case final progress?
          when backgroundColor == null &&
              semanticValue == null &&
              PlatformUiCapabilities.usesNativeIOS26) {
        return Semantics(
          label: semanticLabel,
          value: '${(progress.clamp(0, 1) * 100).round()}%',
          child: ExcludeSemantics(
            child: CNProgressIndicator(
              value: progress,
              // The package's default reads Flutter's CupertinoTheme, which
              // this app (on cupertino_ui) lacks.
              tint: color ?? CupertinoTheme.of(context).primaryColor,
            ),
          ),
        );
      }
      return LinearProgressIndicator(
        value: value,
        color: color,
        backgroundColor: backgroundColor,
        minHeight: minHeight,
        semanticsLabel: semanticLabel,
        semanticsValue: semanticValue,
      );
    }
    if (PlatformUiCapabilities.isIOS) {
      return Semantics(
        label: semanticLabel,
        value:
            semanticValue ??
            (value == null ? null : '${(value! * 100).round()}%'),
        child: FittedBox(
          child: value == null
              ? CupertinoActivityIndicator(radius: 18, color: color)
              : CupertinoActivityIndicator.partiallyRevealed(
                  radius: 18,
                  color: color,
                  progress: value!.clamp(0, 1),
                ),
        ),
      );
    }
    return CircularProgressIndicator(
      value: value,
      color: color,
      backgroundColor: backgroundColor,
      strokeWidth: strokeWidth,
      semanticsLabel: semanticLabel,
      semanticsValue: semanticValue,
    );
  }
}

/// Pull to refresh: the iOS activity indicator on iOS, grey as the system
/// draws it whatever [color] says, and the Material refresh indicator
/// elsewhere, as luci-mobile's pages had it.
///
/// Both keep Flutter's pull gesture, so any scroll view can take it without
/// becoming a sliver list.
class AdaptiveRefreshIndicator extends StatelessWidget {
  const AdaptiveRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.displacement = 40.0,
    this.edgeOffset = 0.0,
    this.color,
    this.backgroundColor,
    this.strokeWidth = RefreshProgressIndicator.defaultStrokeWidth,
    this.semanticsLabel,
    this.semanticsValue,
    this.triggerMode = RefreshIndicatorTriggerMode.onEdge,
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final double displacement;
  final double edgeOffset;

  /// The Material indicator's colour. iOS keeps its system grey.
  final Color? color;

  /// The Material indicator's disc. iOS draws no disc.
  final Color? backgroundColor;

  final double strokeWidth;
  final String? semanticsLabel;
  final String? semanticsValue;
  final RefreshIndicatorTriggerMode triggerMode;
  final ScrollNotificationPredicate notificationPredicate;

  @override
  Widget build(BuildContext context) {
    if (PlatformUiCapabilities.isIOS) {
      return RefreshIndicator.adaptive(
        onRefresh: onRefresh,
        displacement: displacement,
        edgeOffset: edgeOffset,
        semanticsLabel: semanticsLabel,
        semanticsValue: semanticsValue,
        triggerMode: triggerMode,
        notificationPredicate: notificationPredicate,
        child: child,
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      displacement: displacement,
      edgeOffset: edgeOffset,
      color: color,
      backgroundColor: backgroundColor,
      strokeWidth: strokeWidth,
      semanticsLabel: semanticsLabel,
      semanticsValue: semanticsValue,
      triggerMode: triggerMode,
      notificationPredicate: notificationPredicate,
      child: child,
    );
  }
}
