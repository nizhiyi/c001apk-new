import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../logic/content_filter/app_content_filter.dart';
import '../logic/content_filter/content_filter_projection.dart';
import '../logic/content_filter/content_filter_rule.dart';
import '../logic/model/feed/datum.dart';
import '../pages/common/common_controller.dart';
import '../utils/storage_util.dart';

class ContentFilterRevealScope extends InheritedWidget {
  const ContentFilterRevealScope(
      {super.key,
      required super.child,
      this.contentKeys = const {},
      this.authorUids = const {}});
  final Set<String> contentKeys;
  final Set<String> authorUids;
  static ContentFilterRevealScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentFilterRevealScope>();
  @override
  bool updateShouldNotify(ContentFilterRevealScope oldWidget) => true;
}

/// Does not construct hidden content, including images and interactive targets.
class ContentFilterGate extends StatefulWidget {
  const ContentFilterGate(
      {super.key,
      required this.data,
      required this.builder,
      this.scope,
      this.hiddenChildren,
      this.page = false,
      this.onReveal,
      this.onClose});
  final Datum data;
  final WidgetBuilder builder;
  final FilterScope? scope;
  final WidgetBuilder? hiddenChildren;
  final bool page;
  final VoidCallback? onReveal;
  final VoidCallback? onClose;
  @override
  State<ContentFilterGate> createState() => _ContentFilterGateState();
}

class _ContentFilterGateState extends State<ContentFilterGate> {
  bool _revealed = false;
  @override
  void didUpdateWidget(ContentFilterGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (ContentFilterProjection.keyOf(oldWidget.data, scope: oldWidget.scope) !=
        ContentFilterProjection.keyOf(widget.data, scope: widget.scope)) {
      _revealed = false;
    }
  }

  Widget _build(BuildContext context) {
    final key = ContentFilterProjection.keyOf(widget.data, scope: widget.scope);
    final local = ContentFilterRevealScope.of(context);
    final hit = ContentFilterProjection.match(widget.data, scope: widget.scope);
    final allowed = local?.contentKeys.contains(key) == true ||
        (hit?.kind == FilterRuleKind.author &&
            local?.authorUids.contains('${widget.data.uid}') == true);
    if (_revealed || allowed || hit == null) return widget.builder(context);
    final placeholder = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已过滤：${hit.reason}',
                style: Theme.of(context).textTheme.bodyMedium),
            Wrap(spacing: 8, children: [
              TextButton(
                  onPressed: () {
                    setState(() => _revealed = true);
                    widget.onReveal?.call();
                  },
                  child: const Text('仅本次查看')),
              TextButton(
                  onPressed: () async {
                    await disableContentFilterRule(hit);
                    if (mounted) setState(() {});
                  },
                  child: Text(
                      hit.ruleId.startsWith('legacy.') ? '移出个人黑名单' : '停用此规则')),
            ]),
            if (widget.hiddenChildren != null) widget.hiddenChildren!(context),
          ]),
    );
    if (!widget.page) return placeholder;
    return Scaffold(
        appBar: AppBar(
            title: const Text('内容已过滤'),
            leading: BackButton(onPressed: widget.onClose)),
        body: SingleChildScrollView(child: placeholder));
  }

  @override
  Widget build(BuildContext context) {
    final service = AppContentFilter.service;
    return service == null
        ? _build(context)
        : ListenableBuilder(
            listenable: service, builder: (context, _) => _build(context));
  }
}

Future<void> disableContentFilterRule(FilterMatch match) async {
  if (match.ruleId.startsWith('legacy.user:')) {
    GStorage.onBlock(match.ruleId.substring('legacy.user:'.length),
        isDelete: true);
  } else if (match.ruleId.startsWith('legacy.topic:')) {
    GStorage.onBlock(match.ruleId.substring('legacy.topic:'.length),
        isUser: false, isDelete: true);
  } else {
    await AppContentFilter.service?.setRuleDisabled(match.ruleId, true);
  }
}

class ContentFilterSummary extends StatelessWidget {
  const ContentFilterSummary({super.key, required this.controller});
  final CommonController controller;
  @override
  Widget build(BuildContext context) => Obx(() {
        final count = controller.filteredItems.length;
        if (count == 0) return const SizedBox.shrink();
        return TextButton.icon(
          icon: const Icon(Icons.filter_alt_outlined, size: 18),
          label: Text('已过滤 $count 条 · 查看原因'),
          onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                    title: const Text('已过滤的内容'),
                    content: SizedBox(
                        width: 460,
                        child: Obx(() => ListView(
                              shrinkWrap: true,
                              children: controller.filteredItems.map((item) {
                                final hit = controller.filterMatch(item);
                                return ListTile(
                                    title: Text(hit?.reason ?? '规则已变化'),
                                    subtitle: Text(
                                        '${item.entityType == 'feed_reply' ? '评论' : '内容'} ${item.id ?? ''} · UID ${item.uid ?? ''}'),
                                    trailing: IconButton(
                                        tooltip: '仅本次查看',
                                        icon: const Icon(
                                            Icons.visibility_outlined),
                                        onPressed: () =>
                                            controller.revealItem(item)),
                                    onTap: hit == null
                                        ? null
                                        : () async {
                                            await disableContentFilterRule(hit);
                                            controller.reapplyFilters();
                                          });
                              }).toList(),
                            ))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'))
                    ],
                  )),
        );
      });
}
