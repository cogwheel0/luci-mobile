import 'package:flutter/widgets.dart';

/// Motion preferences shared by interactive and continuously updating UI.
///
/// MediaQuery is authoritative when a subtree overrides the platform setting
/// (including widget tests). The platform value keeps the fallback correct for
/// contexts mounted without a MediaQuery ancestor.
extension MotionContext on BuildContext {
  bool get reduceMotion {
    final accessibilityFeatures =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return (MediaQuery.maybeDisableAnimationsOf(this) ??
            accessibilityFeatures.disableAnimations) ||
        accessibilityFeatures.reduceMotion;
  }

  Duration motionDuration(Duration duration) =>
      reduceMotion ? Duration.zero : duration;
}
