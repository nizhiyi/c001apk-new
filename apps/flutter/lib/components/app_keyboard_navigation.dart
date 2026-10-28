import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'keyboard_scroll_region.dart';
import 'app_navigation_history.dart';

/// Fallback keyboard navigation for routes whose scroll controllers are not
/// primary. Controls inside the route get the first chance to handle each key.
class AppKeyboardNavigation extends StatefulWidget {
  const AppKeyboardNavigation({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.history,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final AppNavigationHistory? history;

  @override
  State<AppKeyboardNavigation> createState() => _AppKeyboardNavigationState();
}

class _AppKeyboardNavigationState extends State<AppKeyboardNavigation> {
  bool _exitPromptOpen = false;

  Future<void> _back({bool promptAtRoot = true}) async {
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    if (navigator.canPop()) {
      await navigator.maybePop();
      return;
    }
    if (!promptAtRoot || _exitPromptOpen) return;
    _exitPromptOpen = true;
    try {
      final exit = await showDialog<bool>(
        context: navigator.context,
        builder: (context) => AlertDialog(
          title: const Text('退出 c001apk？'),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('退出'),
            ),
          ],
        ),
      );
      if (exit == true && mounted) {
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          await windowManager.close();
        } else {
          await SystemNavigator.pop();
        }
      }
    } finally {
      _exitPromptOpen = false;
    }
  }

  ScrollableState? _scrollTarget() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null) {
      final focused = Scrollable.maybeOf(focusContext, axis: Axis.vertical);
      if (focused != null) return focused;
    }
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return null;
    final viewport = Offset.zero & MediaQuery.sizeOf(context);
    ScrollableState? target;
    double largestArea = 0;
    void visit(Element element) {
      if (element.widget is Offstage && (element.widget as Offstage).offstage) {
        return;
      }
      if (element is StatefulElement && element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        final box = element.findRenderObject();
        if (axisDirectionToAxis(state.axisDirection) == Axis.vertical &&
            ModalRoute.of(element)?.isCurrent == true &&
            box is RenderBox &&
            box.attached &&
            box.hasSize) {
          final bounds = MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          ).intersect(viewport);
          final area = bounds.isEmpty ? 0.0 : bounds.width * bounds.height;
          if (area > largestArea) {
            target = state;
            largestArea = area;
          }
        }
      }
      element.visitChildren(visit);
    }

    final region =
        focusContext?.findAncestorStateOfType<KeyboardScrollRegionState>();
    (region?.context ?? navigator.context).visitChildElements(visit);
    return target;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) unawaited(_back());
      return KeyEventResult.handled;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowUp &&
        event.logicalKey != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    // Text editing shortcuts are resolved above this Focus in WidgetsApp.
    // Leave cursor movement and multiline editing to EditableText.
    if (FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>() !=
        null) {
      return KeyEventResult.ignored;
    }
    final target = _scrollTarget();
    if (target == null ||
        !target.position.hasContentDimensions ||
        !target.position.physics.shouldAcceptUserOffset(target.position)) {
      return KeyEventResult.ignored;
    }
    final position = target.position;
    widget.history?.cancelRestore();
    final movingDown = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final reversed = target.axisDirection == AxisDirection.up;
    final offset = movingDown != reversed ? 64.0 : -64.0;
    final next = (position.pixels + offset)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    unawaited(position.animateTo(next,
        duration: const Duration(milliseconds: 100), curve: Curves.easeOut));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => AppNavigationHistoryScope(
        history: widget.history,
        child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              widget.history?.restorePending();
              return false;
            },
            child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) {
                  if (event.kind == PointerDeviceKind.mouse &&
                      event.buttons == kBackMouseButton) {
                    unawaited(_back(promptAtRoot: false));
                  } else if (event.kind == PointerDeviceKind.mouse &&
                      event.buttons == kForwardMouseButton) {
                    widget.history?.forward();
                  } else {
                    widget.history?.cancelRestore();
                  }
                },
                onPointerSignal: (_) => widget.history?.cancelRestore(),
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _onKeyEvent,
                  child: widget.child,
                ))),
      );
}
