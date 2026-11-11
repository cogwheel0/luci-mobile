import 'package:flutter/widgets.dart';

/// Room the bottom tab bar takes over the page, where it floats over it.
///
/// On iOS 26 the native tab bar is Liquid Glass over the page rather than
/// a strip below it: pages scroll under it, and their last item has to be
/// able to clear it. The shell puts that height here (and into
/// [MediaQuery.padding], for lists that pad themselves from it); a page that
/// sets its own bottom padding adds [of]. It is zero wherever the bar sits
/// below the page (Android, iOS before 26), so nothing changes there.
class TabBarInset extends InheritedWidget {
  const TabBarInset({super.key, required this.bottom, required super.child});

  /// From the bottom of the screen: the bar and the home indicator under it.
  final double bottom;

  /// What the nearest shell reserves, or zero outside one.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabBarInset>()?.bottom ?? 0;

  @override
  bool updateShouldNotify(TabBarInset oldWidget) => bottom != oldWidget.bottom;
}
