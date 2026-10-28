import 'package:flutter/material.dart';
import 'package:get/get_navigation/src/dialog/dialog_route.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../pages/feed/reply/reply_page.dart';
import '../utils/storage_util.dart';
import 'liquid_top_bar.dart';

/// The floating and rail entry points open the same existing composer route.
class HomePublishAction extends StatelessWidget {
  const HomePublishAction({super.key, this.extended = false});

  final bool extended;

  void _open(BuildContext context) => Navigator.of(context).push(GetDialogRoute(
        pageBuilder: (_, __, ___) => const ReplyPage(),
        transitionDuration: const Duration(milliseconds: 500),
        transitionBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero)
              .animate(animation),
          child: child,
        ),
      ));

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: GStorage.settings.listenable(keys: [
          SettingsBoxKey.hideHomePublishButton,
          SettingsBoxKey.floatingNavigation,
          SettingsBoxKey.liquidGlass,
          SettingsBoxKey.liquidGlassLevel,
        ]),
        builder: (context, _, __) {
          if (GStorage.hideHomePublishButton) {
            return const SizedBox.shrink();
          }
          final foreground = Theme.of(context).colorScheme.primary;
          final textStyle = DefaultTextStyle.of(context)
              .style
              .copyWith(fontSize: 12, color: foreground);
          final stacked =
              extended && MediaQuery.textScalerOf(context).scale(12) > 18;
          var height = 52.0;
          if (stacked) {
            final painter = TextPainter(
                text: TextSpan(text: '发布', style: textStyle),
                textScaler: MediaQuery.textScalerOf(context),
                textDirection: Directionality.of(context))
              ..layout(maxWidth: 48);
            height = painter.height + 36;
            painter.dispose();
          }
          final content = extended
              ? stacked
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add,
                          size: 18, color: foreground, applyTextScaling: false),
                      const SizedBox(height: 2),
                      SizedBox(
                          width: 48,
                          child: Text('发布',
                              textAlign: TextAlign.center, style: textStyle)),
                    ])
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add,
                          size: 18, color: foreground, applyTextScaling: false),
                      const SizedBox(width: 2),
                      Flexible(child: Text('发布', style: textStyle)),
                    ])
              : Icon(Icons.add, color: foreground);
          if (GStorage.floatingNavigation) {
            return LiquidGlassButton(
              height: height,
              width: extended ? 64 : 52,
              enabled: GStorage.liquidGlass,
              level: GStorage.liquidGlassLevel,
              tooltip: '发布动态',
              onPressed: () => _open(context),
              child: Center(child: content),
            );
          }
          if (extended) {
            return Tooltip(
              message: '发布动态',
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size(64, height)),
                onPressed: () => _open(context),
                child: content,
              ),
            );
          }
          return FloatingActionButton(
            heroTag: null,
            tooltip: '发布动态',
            onPressed: () => _open(context),
            child: const Icon(Icons.add),
          );
        },
      );
}
