import 'package:c001apk_flutter/components/network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../logic/model/feed/datum.dart';
import '../../utils/global_data.dart';
import '../../utils/storage_util.dart';
import '../liquid_glass_surface.dart';
import 'message_first_card.dart';

class MessageHeaderCard extends StatelessWidget {
  const MessageHeaderCard({
    super.key,
    this.userInfo,
    required this.onLogin,
    this.floating = false,
    this.counts,
  });

  final Datum? userInfo;
  final Function() onLogin;
  final bool floating;
  final List<int?>? counts;

  String get _username {
    final name = userInfo?.username ?? GlobalData().username;
    try {
      return Uri.decodeComponent(name);
    } catch (_) {
      return name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final experience = userInfo?.experience ?? GStorage.exp;
    final nextExperience = userInfo?.nextLevelExperience ?? GStorage.nextExp;
    final content = Padding(
      padding: EdgeInsets.symmetric(
          horizontal: floating ? 18 : 20, vertical: floating ? 16 : 0),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!GlobalData().isLogin)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Center(
              child: FilledButton.tonal(
                onPressed: onLogin,
                child: const Text('点击登录'),
              ),
            ),
          )
        else ...[
          Row(
            children: [
              Semantics(
                button: true,
                label: '查看个人主页',
                child: InkWell(
                  borderRadius: BorderRadius.circular(26),
                  onTap: () =>
                      Get.toNamed('/u/${userInfo?.uid ?? GlobalData().uid}'),
                  child: clipNetworkImage(
                    userInfo?.userAvatar ?? GStorage.userAvatar,
                    isAvatar: true,
                    width: floating ? 52 : 45,
                    height: floating ? 52 : 45,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Lv.${userInfo?.level ?? GStorage.level}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Expanded(
                            child: Text(
                          '$experience/$nextExperience',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 13),
                        )),
                      ],
                    ),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(
                      value: nextExperience > 0
                          ? (experience / nextExperience).clamp(0.0, 1.0)
                          : 0,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(10),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (floating) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 6),
            messageFirstCard(true, context, counts, transparent: true),
          ],
        ],
      ]),
    );
    return Material(
      type: MaterialType.transparency,
      child: floating
          ? LiquidGlassPanel(
              enabled: GStorage.liquidGlass,
              level: GStorage.liquidGlassLevel,
              child: content,
            )
          : ColoredBox(
              color: Theme.of(context).colorScheme.surface, child: content),
    );
  }
}
