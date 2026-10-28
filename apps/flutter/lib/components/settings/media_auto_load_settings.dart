import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../constants/media_auto_load_mode.dart';
import '../../utils/storage_util.dart';

class MediaAutoLoadSettings extends StatefulWidget {
  const MediaAutoLoadSettings({super.key});

  @override
  State<MediaAutoLoadSettings> createState() => _MediaAutoLoadSettingsState();
}

class _MediaAutoLoadSettingsState extends State<MediaAutoLoadSettings> {
  MediaAutoLoadMode? _savingFrom;

  Future<void> _save(MediaAutoLoadMode? mode) async {
    if (mode == null || _savingFrom != null || !mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      // Hive notifies listeners before disk I/O finishes. Keep the last saved
      // choice visible until that write has succeeded or rolled back.
      _savingFrom = MediaAutoLoadMode.fromStored(
          GStorage.settings.get(MediaAutoLoadMode.storageKey));
    });
    try {
      await GStorage.settings
          .put(MediaAutoLoadMode.storageKey, mode.storedValue);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('设置未保存，请重试'),
          action: SnackBarAction(label: '重试', onPressed: () => _save(mode)),
        ));
      }
    } finally {
      if (mounted) setState(() => _savingFrom = null);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable:
            GStorage.settings.listenable(keys: [MediaAutoLoadMode.storageKey]),
        builder: (context, settings, _) => LayoutBuilder(
          builder: (context, constraints) {
            final selected = _savingFrom ??
                MediaAutoLoadMode.fromStored(
                    settings.get(MediaAutoLoadMode.storageKey));
            // ListTile's trailing slot is height-limited. A stacked picker
            // also leaves enough room for the longer title on narrow screens.
            final stackPicker = constraints.maxWidth < 400 ||
                MediaQuery.textScalerOf(context).scale(16) > 24;
            final picker = DropdownButtonHideUnderline(
              child: DropdownButton<MediaAutoLoadMode>(
                value: selected,
                itemHeight: null,
                isExpanded: stackPicker,
                items: [
                  for (final mode in MediaAutoLoadMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.label)),
                ],
                onChanged: _savingFrom == null ? _save : null,
              ),
            );
            return Semantics(
              container: true,
              child: ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('自动加载实况图片'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('打开大图时自动播放实况图片'),
                    if (stackPicker) picker,
                  ],
                ),
                trailing: stackPicker ? null : picker,
              ),
            );
          },
        ),
      );
}
