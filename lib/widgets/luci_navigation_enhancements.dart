import 'package:flutter/material.dart';
import '../design/luci_design_system.dart';
import 'luci_animation_system.dart';
import '../l10n/luci_localizations.dart';

/// Enhanced tab transition system for smooth navigation
/// Provides consistent, engaging transitions between screens
class LuciTabTransition extends StatefulWidget {
  const LuciTabTransition({
    super.key,
    required this.child,
    required this.transitionKey,
    this.duration = const Duration(milliseconds: 350),
    this.curve = Curves.easeInOutCubic,
  });

  final Widget child;
  final String transitionKey;
  final Duration duration;
  final Curve curve;

  @override
  State<LuciTabTransition> createState() => _LuciTabTransitionState();
}

class _LuciTabTransitionState extends State<LuciTabTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeInOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    _controller.forward();
  }

  @override
  void didUpdateWidget(LuciTabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.transitionKey != oldWidget.transitionKey) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(opacity: _fadeAnimation, child: widget.child),
    );
  }
}

/// Enhanced floating action button with hero animation and micro-interactions
class LuciEnhancedFAB extends StatefulWidget {
  const LuciEnhancedFAB({
    super.key,
    required this.onPressed,
    required this.icon,
    this.heroTag,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
    this.useExtended = false,
    this.label,
    this.showOnScroll = true,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String? heroTag;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool useExtended;
  final String? label;
  final bool showOnScroll;

  @override
  State<LuciEnhancedFAB> createState() => _LuciEnhancedFABState();
}

class _LuciEnhancedFABState extends State<LuciEnhancedFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: LuciAdvancedAnimations.quickTransition,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePress() {
    _controller.reverse().then((_) {
      _controller.forward();
      widget.onPressed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Transform.rotate(
            angle: _rotationAnimation.value * 0.1, // Subtle rotation on appear
            child: widget.useExtended && widget.label != null
                ? FloatingActionButton.extended(
                    onPressed: _handlePress,
                    icon: Icon(widget.icon),
                    label: Text(widget.label!),
                    heroTag: widget.heroTag,
                    tooltip: widget.tooltip,
                    backgroundColor:
                        widget.backgroundColor ?? colorScheme.primary,
                    foregroundColor:
                        widget.foregroundColor ?? colorScheme.onPrimary,
                  )
                : FloatingActionButton(
                    onPressed: _handlePress,
                    heroTag: widget.heroTag,
                    tooltip: widget.tooltip,
                    backgroundColor:
                        widget.backgroundColor ?? colorScheme.primary,
                    foregroundColor:
                        widget.foregroundColor ?? colorScheme.onPrimary,
                    child: Icon(widget.icon),
                  ),
          ),
        );
      },
    );
  }
}

/// Loading overlay with sophisticated animations
class LuciLoadingOverlay extends StatefulWidget {
  const LuciLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.loadingText,
    this.backgroundColor,
    this.useBlur = true,
  });

  final bool isLoading;
  final Widget child;
  final String? loadingText;
  final Color? backgroundColor;
  final bool useBlur;

  @override
  State<LuciLoadingOverlay> createState() => _LuciLoadingOverlayState();
}

class _LuciLoadingOverlayState extends State<LuciLoadingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _overlayController;
  late AnimationController _pulseController;
  late Animation<double> _overlayAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _overlayController = AnimationController(
      duration: LuciAdvancedAnimations.quickTransition,
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _overlayAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _overlayController, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isLoading) {
      _overlayController.forward();
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(LuciLoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading != oldWidget.isLoading) {
      if (widget.isLoading) {
        _overlayController.forward();
        _pulseController.repeat(reverse: true);
      } else {
        _overlayController.reverse();
        _pulseController.stop();
      }
    }
  }

  @override
  void dispose() {
    _overlayController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      children: [
        widget.child,
        if (widget.isLoading)
          AnimatedBuilder(
            animation: _overlayAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _overlayAnimation.value,
                child: Container(
                  color: (widget.backgroundColor ?? colorScheme.surface)
                      .withValues(alpha: 0.8),
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colorScheme.primary,
                                ),
                              ),
                              SizedBox(height: LuciSpacing.md),
                              Text(
                                widget.loadingText ?? context.l10n.loading,
                                style: LuciTextStyles.cardSubtitle(context),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Enhanced card with entrance animations and hover effects
class LuciAnimatedCard extends StatefulWidget {
  const LuciAnimatedCard({
    super.key,
    required this.child,
    this.onTap,
    this.margin = EdgeInsets.zero,
    this.padding,
    this.elevation = 0,
    this.animationDelay = Duration.zero,
    this.hoverElevation = 4,
    this.isExpandable = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry? padding;
  final double elevation;
  final Duration animationDelay;
  final double hoverElevation;
  final bool isExpandable;

  @override
  State<LuciAnimatedCard> createState() => _LuciAnimatedCardState();
}

class _LuciAnimatedCardState extends State<LuciAnimatedCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: LuciAdvancedAnimations.smoothTransition,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    // Start animation after delay
    if (widget.animationDelay > Duration.zero) {
      Future.delayed(widget.animationDelay, () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleHover(bool isHovered) {
    setState(() => _isHovered = isHovered);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Container(
              margin: widget.margin,
              child: MouseRegion(
                onEnter: (_) => _handleHover(true),
                onExit: (_) => _handleHover(false),
                child: AnimatedContainer(
                  duration: LuciAdvancedAnimations.microInteraction,
                  curve: Curves.easeInOut,
                  padding: widget.padding ?? EdgeInsets.all(LuciSpacing.md),
                  decoration:
                      LuciCardStyles.standardCard(
                        context,
                        isElevated: _isHovered || widget.elevation > 0,
                      ).copyWith(
                        boxShadow: _isHovered
                            ? [
                                BoxShadow(
                                  color: Theme.of(
                                    context,
                                  ).shadowColor.withValues(alpha: 0.15),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                  child: InkWell(
                    onTap: widget.onTap,
                    borderRadius: LuciCardStyles.standardRadius,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
