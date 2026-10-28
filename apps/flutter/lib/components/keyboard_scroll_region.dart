import 'package:flutter/material.dart';

/// Marks the pane the user is interacting with without intercepting keys from
/// its text fields, menus, or other controls.
class KeyboardScrollRegion extends StatefulWidget {
  const KeyboardScrollRegion(
      {super.key, required this.child, this.autofocus = false});
  final Widget child;
  final bool autofocus;

  @override
  State<KeyboardScrollRegion> createState() => KeyboardScrollRegionState();
}

class KeyboardScrollRegionState extends State<KeyboardScrollRegion> {
  final _focus = FocusNode(skipTraversal: true);

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) _requestFocus();
  }

  @override
  void didUpdateWidget(KeyboardScrollRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus && !oldWidget.autofocus) _requestFocus();
  }

  void _requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.autofocus) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _focus,
        autofocus: widget.autofocus,
        child: Listener(
          onPointerDown: (_) {
            if (!_focus.hasFocus) _focus.requestFocus();
          },
          onPointerSignal: (_) {
            if (!_focus.hasFocus) _focus.requestFocus();
          },
          child: widget.child,
        ),
      );
}
