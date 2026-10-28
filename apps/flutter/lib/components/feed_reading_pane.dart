import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../pages/feed/feed_page.dart';
import '../utils/storage_util.dart';
import 'adaptive_reading_pane.dart';

class FeedReadingPane extends StatelessWidget {
  const FeedReadingPane(
      {super.key, required this.child, this.paneKey, this.leadingInset = 0});
  final Widget child;
  final GlobalKey<AdaptiveReadingPaneState>? paneKey;
  final double leadingInset;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable:
            GStorage.settings.listenable(keys: [SettingsBoxKey.readingMode]),
        builder: (context, settings, _) {
          final value =
              settings.get(SettingsBoxKey.readingMode, defaultValue: 0);
          final mode =
              value is int && value >= 0 && value < ReadingMode.values.length
                  ? ReadingMode.values[value]
                  : ReadingMode.automatic;
          return AdaptiveReadingPane(
            key: paneKey,
            leadingInset: leadingInset,
            mode: mode,
            detailBuilder: (_, id, close) =>
                FeedPage(key: ValueKey(id), id: id, onClose: close),
            child: child,
          );
        },
      );
}
