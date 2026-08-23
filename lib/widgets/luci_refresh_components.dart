import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/luci_design_system.dart';
import '../l10n/luci_localizations.dart';

/// A standardized pull-to-refresh widget that provides consistent
/// visual feedback and behavior across all screens in the app.
class LuciPullToRefresh extends StatefulWidget {
  const LuciPullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.displacement = 40.0,
    this.edgeOffset = 0.0,
    this.backgroundColor,
    this.color,
    this.strokeWidth = RefreshProgressIndicator.defaultStrokeWidth,
    this.semanticsLabel,
    this.semanticsValue,
    this.triggerMode = RefreshIndicatorTriggerMode.onEdge,
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  /// The function to call when the user pulls to refresh.
  final RefreshCallback onRefresh;

  /// The widget below this widget in the tree.
  final Widget child;

  /// The distance from the child's top or bottom edge to where the refresh
  /// indicator will settle.
  final double displacement;

  /// The offset where [RefreshProgressIndicator] starts to appear on drag start.
  final double edgeOffset;

  /// The progress indicator's background color.
  final Color? backgroundColor;

  /// The progress indicator's foreground color.
  final Color? color;

  /// The progress indicator's stroke width.
  final double strokeWidth;

  /// The semantic label for the refresh indicator.
  final String? semanticsLabel;

  /// The semantic value for the refresh indicator.
  final String? semanticsValue;

  /// Defines how the refresh is triggered.
  final RefreshIndicatorTriggerMode triggerMode;

  /// A check that specifies whether a [ScrollNotification] should be
  /// handled by this widget.
  final ScrollNotificationPredicate notificationPredicate;

  @override
  State<LuciPullToRefresh> createState() => _LuciPullToRefreshState();
}

class _LuciPullToRefreshState extends State<LuciPullToRefresh>
    with SingleTickerProviderStateMixin {
  late AnimationController _hapticController;
  bool _hasTriggeredHaptic = false;

  @override
  void initState() {
    super.initState();
    _hapticController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _hapticController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    // Provide haptic feedback when refresh is triggered
    if (!_hasTriggeredHaptic) {
      await HapticFeedback.mediumImpact();
      _hasTriggeredHaptic = true;
      unawaited(
        _hapticController.forward().then((_) {
          _hapticController.reset();
          _hasTriggeredHaptic = false;
        }),
      );
    }

    try {
      await widget.onRefresh();
    } catch (e) {
      // Handle any errors that might occur during refresh
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.refreshFailed(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(LuciSpacing.md),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LuciSpacing.sm),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: _onRefresh,
      displacement: widget.displacement,
      edgeOffset: widget.edgeOffset,
      backgroundColor: widget.backgroundColor ?? colorScheme.surface,
      color: widget.color ?? colorScheme.primary,
      strokeWidth: widget.strokeWidth,
      semanticsLabel: widget.semanticsLabel,
      semanticsValue: widget.semanticsValue,
      triggerMode: widget.triggerMode,
      notificationPredicate: widget.notificationPredicate,
      child: widget.child,
    );
  }
}

/// A specialized pull-to-refresh widget for list views that ensures
/// proper scrolling behavior and provides visual feedback for empty lists.
class LuciListPullToRefresh extends StatelessWidget {
  const LuciListPullToRefresh({
    super.key,
    required this.onRefresh,
    required this.itemCount,
    required this.itemBuilder,
    this.separatorBuilder,
    this.scrollController,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
    this.showEmptyState = true,
  });

  /// The function to call when the user pulls to refresh.
  final RefreshCallback onRefresh;

  /// The number of items in the list.
  final int itemCount;

  /// Builder for list items.
  final IndexedWidgetBuilder itemBuilder;

  /// Builder for separators between list items.
  final IndexedWidgetBuilder? separatorBuilder;

  /// Controls the scroll offset of the list.
  final ScrollController? scrollController;

  /// How the scroll view should respond to user input.
  final ScrollPhysics? physics;

  /// Whether the extent of the scroll view should be determined by its contents.
  final bool shrinkWrap;

  /// The amount of space by which to inset the list.
  final EdgeInsetsGeometry? padding;

  /// Message to show when the list is empty.
  final String? emptyMessage;

  /// Icon to show when the list is empty.
  final IconData emptyIcon;

  /// Whether to show the empty state when itemCount is 0.
  final bool showEmptyState;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0 && showEmptyState) {
      return LuciPullToRefresh(
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    emptyIcon,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  SizedBox(height: LuciSpacing.md),
                  Text(
                    emptyMessage ?? context.l10n.noItemsToDisplay,
                    style: LuciTextStyles.cardTitle(
                      context,
                    ).copyWith(color: Theme.of(context).colorScheme.outline),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: LuciSpacing.sm),
                  Text(
                    context.l10n.pullDownToRefresh,
                    style: LuciTextStyles.cardSubtitle(
                      context,
                    ).copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget listView;
    if (separatorBuilder != null) {
      listView = ListView.separated(
        controller: scrollController,
        physics: physics,
        shrinkWrap: shrinkWrap,
        padding: padding,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        separatorBuilder: separatorBuilder!,
      );
    } else {
      listView = ListView.builder(
        controller: scrollController,
        physics: physics,
        shrinkWrap: shrinkWrap,
        padding: padding,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    }

    return LuciPullToRefresh(onRefresh: onRefresh, child: listView);
  }
}
