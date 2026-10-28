import 'package:flutter/material.dart';

/// Fade within the space above navigation, then remove paint, focus and hits.
/// A full 2x-height slide can leave a raised FAB visible underneath a floating bar.
class ScrollHidingAction extends StatelessWidget {
  const ScrollHidingAction(
      {super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = animation.drive(CurveTween(curve: Curves.easeInOut));
    return AnimatedBuilder(
      animation: animation,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      ),
      builder: (_, child) => Visibility(
        visible: animation.value > 0,
        maintainState: true,
        child: child!,
      ),
    );
  }
}
