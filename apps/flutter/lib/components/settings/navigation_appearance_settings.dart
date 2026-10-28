import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../utils/storage_util.dart';
import '../../constants/liquid_glass_level.dart';
import '../expressive_list_section.dart';

/// Separate floating/glass preferences, like KernelSU's theme settings.
class NavigationAppearanceSettings extends StatelessWidget {
  const NavigationAppearanceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: GStorage.settings.listenable(keys: [
        SettingsBoxKey.floatingNavigation,
        SettingsBoxKey.liquidGlass,
        SettingsBoxKey.liquidGlassLevel,
      ]),
      builder: (context, _, __) {
        final enabled = GStorage.floatingNavigation && GStorage.liquidGlass;
        // ListTile limits trailing widgets to 56dp. Stack the selector when
        // larger text needs more vertical room.
        final stackPicker = MediaQuery.textScalerOf(context).scale(16) > 24;
        final picker = DropdownButtonHideUnderline(
          child: DropdownButton<LiquidGlassLevel>(
            value: GStorage.liquidGlassLevel,
            itemHeight: null,
            items: [
              for (final level in LiquidGlassLevel.values)
                DropdownMenuItem(value: level, child: Text(level.label)),
            ],
            onChanged: enabled
                ? (level) {
                    if (level != null) {
                      GStorage.settings.put(
                          SettingsBoxKey.liquidGlassLevel, level.storedValue);
                    }
                  }
                : null,
          ),
        );
        return ExpressiveListSection(children: [
          SwitchListTile(
            secondary: const Icon(Icons.call_to_action_outlined),
            title: const Text('悬浮控件'),
            subtitle: const Text('开启后，应用内的一些控件变为悬浮状态'),
            value: GStorage.floatingNavigation,
            onChanged: (value) =>
                GStorage.settings.put(SettingsBoxKey.floatingNavigation, value),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.water_drop_outlined),
            title: const Text('液态玻璃'),
            subtitle: const Text('为悬浮导航、搜索、发布和关注菜单启用玻璃效果'),
            value: GStorage.liquidGlass,
            onChanged: GStorage.floatingNavigation
                ? (value) =>
                    GStorage.settings.put(SettingsBoxKey.liquidGlass, value)
                : null,
          ),
          Semantics(
            container: true,
            child: ListTile(
              enabled: enabled,
              leading: const Icon(Icons.tune),
              title: const Text('液态玻璃档位'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(GStorage.liquidGlassLevel.description),
                  if (stackPicker) picker,
                ],
              ),
              trailing: stackPicker ? null : picker,
            ),
          ),
        ]);
      },
    );
  }
}
