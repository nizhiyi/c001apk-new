import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/storage_util.dart';
import 'expressive_navigation_bar.dart';
import 'liquid_navigation_bar.dart';

/// The page subtree stays in the same slot when navigation style or width changes.
class AdaptiveMainScaffold extends StatelessWidget {
  const AdaptiveMainScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.bodyBuilder,
    this.railTrailing,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget Function(BuildContext context, bool useRail) bodyBuilder;
  final Widget? railTrailing;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: GStorage.settings.listenable(keys: [
          SettingsBoxKey.floatingNavigation,
          SettingsBoxKey.liquidGlass,
          SettingsBoxKey.liquidGlassLevel,
        ]),
        builder: (context, _, __) =>
            LayoutBuilder(builder: (context, constraints) {
          final useRail =
              constraints.maxWidth - MediaQuery.paddingOf(context).horizontal >=
                  600;
          final floating = GStorage.floatingNavigation;
          final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
          return Scaffold(
            // Scaffold inserts a different element tree when extendBody changes.
            // Keep it enabled and reserve the standard bar with stable wrappers so
            // preference/width changes cannot unmount account pages or their scrolls.
            extendBody: true,
            body: Builder(builder: (context) {
              final media = MediaQuery.of(context);
              final reserve = !useRail && !keyboard && !floating;
              return Padding(
                padding:
                    EdgeInsets.only(bottom: reserve ? media.padding.bottom : 0),
                child: MediaQuery(
                  data: media.copyWith(
                    padding: reserve
                        ? media.padding.copyWith(bottom: 0)
                        : media.padding,
                    // Nested page FABs use viewPadding; lists use padding.
                    viewPadding: !useRail && floating && !keyboard
                        ? media.viewPadding
                            .copyWith(bottom: media.padding.bottom)
                        : media.viewPadding,
                  ),
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: Row(children: [
                      SizedBox(
                        width: useRail ? 80 : 0,
                        child: Offstage(
                          offstage: !useRail,
                          child: NavigationRail(
                            trailingAtBottom: true,
                            trailing: railTrailing == null
                                ? null
                                : Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: railTrailing,
                                  ),
                            selectedIndex: selectedIndex,
                            onDestinationSelected: onDestinationSelected,
                            labelType: NavigationRailLabelType.all,
                            destinations: const [
                              NavigationRailDestination(
                                  icon: Icon(Icons.home_outlined),
                                  selectedIcon: Icon(Icons.home),
                                  label: Text('主页')),
                              NavigationRailDestination(
                                  icon: Icon(Icons.feed_outlined),
                                  selectedIcon: Icon(Icons.feed),
                                  label: Text('关注')),
                              NavigationRailDestination(
                                  icon: Icon(Icons.person_outline),
                                  selectedIcon: Icon(Icons.person),
                                  label: Text('我的')),
                            ],
                          ),
                        ),
                      ),
                      Expanded(child: bodyBuilder(context, useRail)),
                    ]),
                  ),
                ),
              );
            }),
            bottomNavigationBar: useRail || keyboard
                ? null
                : floating
                    ? LiquidNavigationBar(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: onDestinationSelected,
                        refract: GStorage.liquidGlass,
                        level: GStorage.liquidGlassLevel,
                      )
                    : ExpressiveNavigationBar(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: onDestinationSelected,
                      ),
          );
        }),
      );
}
