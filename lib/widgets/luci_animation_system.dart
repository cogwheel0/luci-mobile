import 'package:material_ui/material_ui.dart';

import '../design/luci_design_system.dart';

/// Advanced animation system for sophisticated transitions and micro-interactions
/// Part of Phase 3: Enhanced Animations & Micro-interactions
class LuciAdvancedAnimations {
  // Enhanced animation durations for specific use cases
  static const Duration microInteraction = Duration(
    milliseconds: 150,
  ); // Button press, toggle
  static const Duration quickTransition = Duration(
    milliseconds: 250,
  ); // Small movements, color changes
  static const Duration smoothTransition = Duration(
    milliseconds: 350,
  ); // Card flips, content reveals
  static const Duration pageTransition = Duration(
    milliseconds: 500,
  ); // Screen transitions
  static const Duration complexAnimation = Duration(
    milliseconds: 750,
  ); // Multi-step animations

  // Advanced curves for specific interactions
  static const Curve bounceIn = Curves.elasticOut;
  static const Curve smoothEase = Curves.easeInOutCubic;
  static const Curve quickSnap = Curves.easeOutBack;
  static const Curve gentleFloat = Curves.easeInOutSine;
  static const Curve sharpPop = Curves.easeOutExpo;

  // Spring physics for natural feeling animations
  static const SpringDescription gentleSpring = SpringDescription(
    mass: 1.0,
    stiffness: 180.0,
    damping: 12.0,
  );

  static const SpringDescription snappySpring = SpringDescription(
    mass: 0.7,
    stiffness: 400.0,
    damping: 15.0,
  );
}

/// Enhanced fade transition with configurable timing and direction
class LuciFadeTransition extends StatefulWidget {
  const LuciFadeTransition({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeInOut,
    this.fadeDirection = LuciFadeDirection.fadeIn,
    this.delay = Duration.zero,
    this.onComplete,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;
  final LuciFadeDirection fadeDirection;
  final Duration delay;
  final VoidCallback? onComplete;

  @override
  State<LuciFadeTransition> createState() => _LuciFadeTransitionState();
}

enum LuciFadeDirection { fadeIn, fadeOut, crossFade }

class _LuciFadeTransitionState extends State<LuciFadeTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    _animation = CurvedAnimation(parent: _controller, curve: widget.curve);

    if (widget.delay > Duration.zero) {
      Future.delayed(widget.delay, () {
        if (mounted) _startAnimation();
      });
    } else {
      _startAnimation();
    }
  }

  void _startAnimation() {
    switch (widget.fadeDirection) {
      case LuciFadeDirection.fadeIn:
        _controller.forward().then((_) => widget.onComplete?.call());
        break;
      case LuciFadeDirection.fadeOut:
        _controller.reverse().then((_) => widget.onComplete?.call());
        break;
      case LuciFadeDirection.crossFade:
        _controller.forward().then((_) {
          _controller.reverse().then((_) => widget.onComplete?.call());
        });
        break;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _animation, child: widget.child);
  }
}

/// Slide transition with bounce effect for engaging micro-interactions
class LuciSlideTransition extends StatefulWidget {
  const LuciSlideTransition({
    super.key,
    required this.child,
    this.direction = LuciSlideDirection.up,
    this.distance = 50.0,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeOutBack,
    this.delay = Duration.zero,
    this.bounce = true,
  });

  final Widget child;
  final LuciSlideDirection direction;
  final double distance;
  final Duration duration;
  final Curve curve;
  final Duration delay;
  final bool bounce;

  @override
  State<LuciSlideTransition> createState() => _LuciSlideTransitionState();
}

enum LuciSlideDirection { up, down, left, right }

class _LuciSlideTransitionState extends State<LuciSlideTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);

    // Determine slide offset based on direction
    Offset beginOffset;
    switch (widget.direction) {
      case LuciSlideDirection.up:
        beginOffset = Offset(0, widget.distance / 100);
        break;
      case LuciSlideDirection.down:
        beginOffset = Offset(0, -widget.distance / 100);
        break;
      case LuciSlideDirection.left:
        beginOffset = Offset(widget.distance / 100, 0);
        break;
      case LuciSlideDirection.right:
        beginOffset = Offset(-widget.distance / 100, 0);
        break;
    }

    _slideAnimation = Tween<Offset>(begin: beginOffset, end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: widget.bounce ? Curves.elasticOut : widget.curve,
          ),
        );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    if (widget.delay > Duration.zero) {
      Future.delayed(widget.delay, () {
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

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(opacity: _fadeAnimation, child: widget.child),
    );
  }
}

/// Scale transition with physics-based spring animation
class LuciScaleTransition extends StatefulWidget {
  const LuciScaleTransition({
    super.key,
    required this.child,
    this.initialScale = 0.0,
    this.finalScale = 1.0,
    this.useSpringPhysics = true,
    this.duration = const Duration(milliseconds: 600),
    this.delay = Duration.zero,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final double initialScale;
  final double finalScale;
  final bool useSpringPhysics;
  final Duration duration;
  final Duration delay;
  final Alignment alignment;

  @override
  State<LuciScaleTransition> createState() => _LuciScaleTransitionState();
}

class _LuciScaleTransitionState extends State<LuciScaleTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);

    if (widget.useSpringPhysics) {
      _scaleAnimation = Tween<double>(
        begin: widget.initialScale,
        end: widget.finalScale,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    } else {
      _scaleAnimation =
          Tween<double>(
            begin: widget.initialScale,
            end: widget.finalScale,
          ).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
          );
    }

    if (widget.delay > Duration.zero) {
      Future.delayed(widget.delay, () {
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

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      alignment: widget.alignment,
      child: widget.child,
    );
  }
}

/// Staggered animation container for sequential reveals
class LuciStaggeredAnimation extends StatefulWidget {
  const LuciStaggeredAnimation({
    super.key,
    required this.children,
    this.staggerDelay = const Duration(milliseconds: 100),
    this.animationType = LuciStaggerType.slideUp,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  final List<Widget> children;
  final Duration staggerDelay;
  final LuciStaggerType animationType;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;

  @override
  State<LuciStaggeredAnimation> createState() => _LuciStaggeredAnimationState();
}

enum LuciStaggerType { slideUp, slideDown, fadeIn, scaleIn }

class _LuciStaggeredAnimationState extends State<LuciStaggeredAnimation> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: widget.crossAxisAlignment,
      mainAxisAlignment: widget.mainAxisAlignment,
      children: List.generate(widget.children.length, (index) {
        final delay = Duration(
          milliseconds: widget.staggerDelay.inMilliseconds * index,
        );

        Widget animatedChild;
        switch (widget.animationType) {
          case LuciStaggerType.slideUp:
            animatedChild = LuciSlideTransition(
              direction: LuciSlideDirection.up,
              delay: delay,
              child: widget.children[index],
            );
            break;
          case LuciStaggerType.slideDown:
            animatedChild = LuciSlideTransition(
              direction: LuciSlideDirection.down,
              delay: delay,
              child: widget.children[index],
            );
            break;
          case LuciStaggerType.fadeIn:
            animatedChild = LuciFadeTransition(
              delay: delay,
              child: widget.children[index],
            );
            break;
          case LuciStaggerType.scaleIn:
            animatedChild = LuciScaleTransition(
              delay: delay,
              child: widget.children[index],
            );
            break;
        }

        return animatedChild;
      }),
    );
  }
}

/// Enhanced button with micro-interactions and haptic feedback
class LuciInteractiveButton extends StatefulWidget {
  const LuciInteractiveButton({
    super.key,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.scaleOnPress = true,
    this.hapticFeedback = true,
    this.rippleEffect = true,
    this.pressScale = 0.95,
    this.borderRadius,
    this.backgroundColor,
    this.pressedColor,
  });

  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final bool scaleOnPress;
  final bool hapticFeedback;
  final bool rippleEffect;
  final double pressScale;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Color? pressedColor;

  @override
  State<LuciInteractiveButton> createState() => _LuciInteractiveButtonState();
}

class _LuciInteractiveButtonState extends State<LuciInteractiveButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _colorAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: LuciAdvancedAnimations.microInteraction,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressScale,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _colorAnimation = ColorTween(
      begin: widget.backgroundColor,
      end: widget.pressedColor,
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (!_isPressed) {
      setState(() => _isPressed = true);
      if (widget.scaleOnPress) {
        _controller.forward();
      }
      if (widget.hapticFeedback) {
        // HapticFeedback.lightImpact(); // Commented to avoid import issues for now
      }
    }
  }

  void _handleTapUp(TapUpDetails details) {
    _handleTapEnd();
  }

  void _handleTapCancel() {
    _handleTapEnd();
  }

  void _handleTapEnd() {
    if (_isPressed) {
      setState(() => _isPressed = false);
      if (widget.scaleOnPress) {
        _controller.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              decoration: BoxDecoration(
                color: _colorAnimation.value ?? widget.backgroundColor,
                borderRadius:
                    widget.borderRadius ??
                    BorderRadius.circular(LuciSpacing.sm),
              ),
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}

/// Page transition builder for consistent screen navigation
class LuciPageTransition extends PageRouteBuilder {
  final Widget child;
  final LuciTransitionType transitionType;
  final Duration duration;
  final Curve curve;

  LuciPageTransition({
    required this.child,
    this.transitionType = LuciTransitionType.slideRight,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeInOutCubic,
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) => child,
         transitionDuration: duration,
         reverseTransitionDuration: duration,
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           return _buildTransition(
             child: child,
             animation: animation,
             secondaryAnimation: secondaryAnimation,
             transitionType: transitionType,
             curve: curve,
           );
         },
       );

  static Widget _buildTransition({
    required Widget child,
    required Animation<double> animation,
    required Animation<double> secondaryAnimation,
    required LuciTransitionType transitionType,
    required Curve curve,
  }) {
    final curvedAnimation = CurvedAnimation(parent: animation, curve: curve);

    switch (transitionType) {
      case LuciTransitionType.slideRight:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        );
      case LuciTransitionType.slideLeft:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1.0, 0.0),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        );
      case LuciTransitionType.slideUp:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 1.0),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        );
      case LuciTransitionType.fadeScale:
        return FadeTransition(
          opacity: curvedAnimation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
            child: child,
          ),
        );
      case LuciTransitionType.fade:
        return FadeTransition(opacity: curvedAnimation, child: child);
    }
  }
}

enum LuciTransitionType { slideRight, slideLeft, slideUp, fadeScale, fade }
