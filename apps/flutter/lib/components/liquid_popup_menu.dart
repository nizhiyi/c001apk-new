import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/storage_util.dart';
import 'liquid_glass_surface.dart';
import 'liquid_top_bar.dart';

/// Keep the existing popup entries and selection behavior inside one glass pane.
class LiquidPopupMenuButton<T> extends StatefulWidget {
  const LiquidPopupMenuButton(
      {super.key,
      required this.child,
      required this.tooltip,
      required this.items,
      required this.onSelected,
      required this.height,
      required this.width});

  final Widget child;
  final String tooltip;
  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T> onSelected;
  final double height, width;

  @override
  State<LiquidPopupMenuButton<T>> createState() =>
      _LiquidPopupMenuButtonState<T>();
}

class _LiquidPopupMenuButtonState<T> extends State<LiquidPopupMenuButton<T>> {
  final _anchor = GlobalKey();

  Future<void> _open() async {
    final box = _anchor.currentContext!.findRenderObject()! as RenderBox;
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final anchor = origin & box.size;
    final media = MediaQuery.of(context);
    final themes = InheritedTheme.capture(from: context, to: navigator.context);
    final selected = await showGeneralDialog<T>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      transitionBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (context, _, __) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: media.textScaler,
              highContrast: media.highContrast,
              disableAnimations: media.disableAnimations),
          child: themes.wrap(
            CustomSingleChildLayout(
              delegate: _MenuLayout(anchor, MediaQuery.paddingOf(context)),
              child: Material(
                type: MaterialType.transparency,
                child: Semantics(
                  namesRoute: true,
                  scopesRoute: true,
                  explicitChildNodes: true,
                  role: ui.SemanticsRole.menu,
                  label: widget.tooltip,
                  child: Shortcuts(
                    shortcuts: const <ShortcutActivator, Intent>{
                      SingleActivator(LogicalKeyboardKey.arrowDown):
                          NextFocusIntent(),
                      SingleActivator(LogicalKeyboardKey.arrowUp):
                          PreviousFocusIntent(),
                    },
                    child: FocusTraversalGroup(
                      policy: WidgetOrderTraversalPolicy(),
                      child: Focus(
                        autofocus: true,
                        child: _GlassPopupPanel(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: widget.items),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )),
    );
    if (mounted && selected != null) widget.onSelected(selected);
  }

  @override
  Widget build(BuildContext context) => LiquidGlassButton(
        key: _anchor,
        height: widget.height,
        width: widget.width,
        enabled: GStorage.liquidGlass,
        level: GStorage.liquidGlassLevel,
        tooltip: widget.tooltip,
        onPressed: _open,
        child: widget.child,
      );
}

class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout(this.anchor, this.padding);
  final Rect anchor;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width =
        math.min(232.0, constraints.maxWidth - padding.horizontal - 16);
    return BoxConstraints.tightFor(width: width).copyWith(
      maxHeight: math.max(0, constraints.maxHeight - padding.vertical - 16),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = anchor.left.clamp(
        padding.left + 8,
        math.max(padding.left + 8,
            size.width - padding.right - childSize.width - 8));
    final top = (anchor.bottom + 8).clamp(
        padding.top + 8,
        math.max(padding.top + 8,
            size.height - padding.bottom - childSize.height - 8));
    return Offset(left.toDouble(), top.toDouble());
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor || padding != oldDelegate.padding;
}

class _GlassPopupPanel extends StatelessWidget {
  const _GlassPopupPanel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
      valueListenable: GStorage.settings.listenable(
          keys: [SettingsBoxKey.liquidGlass, SettingsBoxKey.liquidGlassLevel]),
      builder: (context, _, __) => LiquidGlassPanel(
          key: const ValueKey('glass-popup-panel'),
          enabled: GStorage.liquidGlass,
          level: GStorage.liquidGlassLevel,
          borderRadius: BorderRadius.circular(24),
          child: child));
}
