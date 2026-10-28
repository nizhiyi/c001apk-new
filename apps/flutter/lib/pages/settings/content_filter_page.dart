import 'package:flutter/material.dart';

import '../../components/expressive_list_section.dart';
import '../../components/keyboard_scroll_region.dart';
import '../../components/settings/item_title.dart';
import '../../logic/content_filter/app_content_filter.dart';
import '../../logic/content_filter/content_filter_rule.dart';
import '../../logic/content_filter/content_filter_service.dart';

class ContentFilterPage extends StatelessWidget {
  const ContentFilterPage({super.key, this.service});
  final ContentFilterService? service;

  @override
  Widget build(BuildContext context) {
    final current = service ?? AppContentFilter.service;
    return Scaffold(
      appBar: AppBar(title: const Text('屏蔽傻逼内容')),
      body: SafeArea(
          top: false,
          child: current == null
              ? const Center(child: Text('内容过滤尚未初始化，请重新启动应用'))
              : _FilterSettings(service: current)),
    );
  }
}

class _FilterSettings extends StatefulWidget {
  const _FilterSettings({required this.service});
  final ContentFilterService service;
  @override
  State<_FilterSettings> createState() => _FilterSettingsState();
}

class _FilterSettingsState extends State<_FilterSettings> {
  ContentFilterService get service => widget.service;

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存失败，请检查输入后重试')));
      }
    }
  }

  String _valueOf(FilterRule rule) => rule.kind == FilterRuleKind.text
      ? rule.groups.map((e) => e.join(' / ')).join(' + ')
      : rule.values.join('、');

  String _kindName(FilterRuleKind kind) => switch (kind) {
        FilterRuleKind.author => '作者 UID',
        FilterRuleKind.topic => '话题',
        FilterRuleKind.text => '文本短语',
      };

  List<Widget> _ruleGroup(FilterRuleKind kind, String title) {
    if (kind != FilterRuleKind.text) {
      return [
        SwitchListTile(
            key: ValueKey('filter-list-${kind.name}'),
            title: Text(title),
            value: service.isListEnabled(kind),
            onChanged: (value) =>
                _perform(() => service.setListEnabled(kind, value))),
      ];
    }
    final rules = service.ruleSet.rules.where((rule) => rule.kind == kind);
    if (rules.isEmpty) return const [];
    return [
      ItemTitle(title: title),
      for (final rule in rules)
        SwitchListTile(
            key: ValueKey('rule-${rule.id}'),
            title: Text(rule.reason),
            subtitle: Text(rule.level == FilterLevel.strict ? '严格档' : '标准与严格'),
            value: !service.disabledRuleIds.contains(rule.id),
            onChanged: (value) =>
                _perform(() => service.setRuleDisabled(rule.id, !value))),
    ];
  }

  Future<void> _addRule() async {
    var value = '';
    final form = GlobalKey<FormState>();
    var kind = FilterRuleKind.text;
    FilterRule draft() => FilterRule(
          id: 'personal.${DateTime.now().microsecondsSinceEpoch}',
          reason: '个人${_kindName(kind)}',
          kind: kind,
          values: kind == FilterRuleKind.text ? const [] : [value.trim()],
          groups: kind == FilterRuleKind.text
              ? [
                  [value.trim()]
                ]
              : const [],
          maxDistance: 240,
        );
    final rule = await showDialog<FilterRule>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: const Text('添加个人规则'),
                  content: SingleChildScrollView(
                      child: Form(
                          key: form,
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                DropdownButtonFormField<FilterRuleKind>(
                                    initialValue: kind,
                                    decoration:
                                        const InputDecoration(labelText: '类型'),
                                    items: [
                                      for (final entry in FilterRuleKind.values)
                                        DropdownMenuItem(
                                            value: entry,
                                            child: Text(_kindName(entry)))
                                    ],
                                    onChanged: (selected) {
                                      if (selected != null) {
                                        update(() {
                                          kind = selected;
                                        });
                                      }
                                    }),
                                const SizedBox(height: 16),
                                TextFormField(
                                    key: const ValueKey('filter-rule-value'),
                                    onChanged: (entered) => value = entered,
                                    maxLength: 128,
                                    keyboardType: kind == FilterRuleKind.author
                                        ? TextInputType.number
                                        : TextInputType.text,
                                    decoration: InputDecoration(
                                        labelText: _kindName(kind),
                                        helperText: kind == FilterRuleKind.topic
                                            ? '填写完整话题名或话题 ID'
                                            : (kind == FilterRuleKind.author
                                                ? '只按实际作者 UID 匹配'
                                                : '按完整短语匹配，不支持正则表达式'),
                                        helperMaxLines: 3,
                                        errorMaxLines: 3),
                                    validator: (_) {
                                      if (value.trim().isEmpty) {
                                        return '请输入${_kindName(kind)}';
                                      }
                                      try {
                                        FilterRule.fromJson(draft().toJson());
                                      } on FormatException {
                                        return kind == FilterRuleKind.text
                                            ? '该短语不能作为过滤规则'
                                            : '请填写有效的${_kindName(kind)}';
                                      }
                                      return null;
                                    }),
                              ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () {
                          if (form.currentState!.validate()) {
                            Navigator.pop(dialogContext, draft());
                          }
                        },
                        child: const Text('添加'))
                  ],
                )));
    if (rule != null) {
      await _perform(() => service.addPersonalRule(rule));
    }
  }

  Future<void> _addAuthorException() async {
    var value = '';
    final form = GlobalKey<FormState>();
    final uid = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('允许显示作者'),
                content: Form(
                    key: form,
                    child: TextFormField(
                        onChanged: (entered) => value = entered,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        maxLength: 20,
                        decoration: const InputDecoration(labelText: '作者 UID'),
                        validator: (value) => RegExp(r'^[1-9][0-9]{0,19}$')
                                .hasMatch(value?.trim() ?? '')
                            ? null
                            : '请输入有效的作者 UID')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () {
                        if (form.currentState!.validate()) {
                          Navigator.pop(dialogContext, value.trim());
                        }
                      },
                      child: const Text('添加'))
                ]));
    if (uid != null) {
      await _perform(() => service.setAuthorAllowed(uid, true));
    }
  }

  String _checkedTime(DateTime? checked) {
    if (checked == null) {
      return '尚未成功检查';
    }
    final time = checked.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: service,
      builder: (context, _) => KeyboardScrollRegion(
            child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView(
                        padding: const EdgeInsets.only(top: 12, bottom: 24),
                        children: [
                          ExpressiveListSection(children: [
                            SwitchListTile(
                                key: const ValueKey('filter-enabled'),
                                title: const Text('屏蔽傻逼内容'),
                                subtitle: const Text('减少低俗内容打扰，让浏览更清爽'),
                                value: service.enabled,
                                onChanged: (value) =>
                                    _perform(() => service.setEnabled(value))),
                          ]),
                          const ItemTitle(title: '过滤强度'),
                          ExpressiveListSection(children: [
                            RadioGroup<FilterLevel>(
                                groupValue: service.level,
                                onChanged: (value) {
                                  if (value != null) {
                                    _perform(() => service.setLevel(value));
                                  }
                                },
                                child: const Column(children: [
                                  RadioListTile<FilterLevel>(
                                      value: FilterLevel.standard,
                                      title: Text('标准'),
                                      subtitle: Text('使用审核名单与明确短语，尽量减少误屏蔽')),
                                  RadioListTile<FilterLevel>(
                                      value: FilterLevel.strict,
                                      title: Text('严格'),
                                      subtitle: Text('包含标准规则，更强过滤，误杀可能更多')),
                                ])),
                          ]),
                          const ItemTitle(title: '规则更新'),
                          ExpressiveListSection(children: [
                            ListTile(
                                title: Text('规则版本 ${service.ruleSet.revision}'),
                                subtitle: Text(
                                    '上次成功检查：${_checkedTime(service.lastCheckedAt)}')),
                            ListTile(
                                leading: const Icon(Icons.refresh),
                                title: const Text('检查规则更新'),
                                subtitle: Text(service.updateMessage ??
                                    '首次开启时检查，此后每隔 6 小时可自动检查。失败继续使用已有规则。'),
                                trailing: service.updating
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : null,
                                onTap: service.updating
                                    ? null
                                    : () => _perform(() =>
                                        service.checkForUpdates(force: true))),
                          ]),
                          ExpressiveListSection(children: [
                            ExpansionTile(
                                title: const Text('规则与名单'),
                                subtitle: const Text('按类别开启或关闭'),
                                expandedCrossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  ..._ruleGroup(FilterRuleKind.text, '内容规则'),
                                  ..._ruleGroup(
                                      FilterRuleKind.author, '频繁发布低俗内容的用户'),
                                  ..._ruleGroup(
                                      FilterRuleKind.topic, '低俗内容相关话题'),
                                ]),
                          ]),
                          const ItemTitle(title: '个人规则'),
                          ExpressiveListSection(children: [
                            ListTile(
                                leading: const Icon(Icons.add),
                                title: const Text('添加个人规则'),
                                subtitle: const Text(
                                    '添加短语、作者 UID 或完整话题；更新订阅不会覆盖个人规则'),
                                onTap: _addRule),
                            for (final rule in service.personalRules)
                              ListTile(
                                  title: Text(_valueOf(rule)),
                                  subtitle: Text(_kindName(rule.kind)),
                                  trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      tooltip: '删除个人规则：${_valueOf(rule)}',
                                      onPressed: () => _perform(() => service
                                          .removePersonalRule(rule.id)))),
                          ]),
                          const ItemTitle(title: '允许显示的作者'),
                          ExpressiveListSection(children: [
                            ListTile(
                                leading: const Icon(Icons.person_add_alt),
                                title: const Text('添加作者例外'),
                                subtitle:
                                    const Text('始终允许该作者的内容通过新过滤；原有手动黑名单需单独管理'),
                                onTap: _addAuthorException),
                            for (final uid in service.allowedAuthorUids)
                              ListTile(
                                  title: Text('UID $uid'),
                                  trailing: IconButton(
                                      icon: const Icon(Icons.close),
                                      tooltip: '移除作者例外：$uid',
                                      onPressed: () => _perform(() => service
                                          .setAuthorAllowed(uid, false)))),
                          ]),
                          const ItemTitle(title: '允许显示的内容'),
                          ExpressiveListSection(children: [
                            if (service.allowedContentKeys.isEmpty)
                              const ListTile(
                                  title: Text('暂无内容例外'),
                                  subtitle: Text('这里管理长期例外。“仅本次查看”不会保存到此处。')),
                            for (final key in service.allowedContentKeys)
                              ListTile(
                                  title: Text(key),
                                  trailing: IconButton(
                                      icon: const Icon(Icons.close),
                                      tooltip: '移除内容例外：$key',
                                      onPressed: () => _perform(() => service
                                          .setContentAllowed(key, false)))),
                          ]),
                          const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 8),
                              child: Text('误屏蔽时可临时查看、停用规则或添加例外。')),
                        ]))),
          ));
}
