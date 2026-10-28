import 'package:c001apk_flutter/logic/content_filter/builtin_filter_rules.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_engine.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_rule.dart';
import 'package:flutter_test/flutter_test.dart';

FilterRule textRule(
        {List<List<String>>? groups, List<String> exceptions = const []}) =>
    FilterRule(
        id: 'text.test',
        reason: '测试组合',
        kind: FilterRuleKind.text,
        groups: groups ??
            [
              ['想'],
              ['约炮']
            ],
        maxDistance: 12,
        exceptions: exceptions);

FilterRuleSet rules(List<FilterRule> rules, {int revision = 1}) =>
    FilterRuleSet(
        revision: revision,
        publishedAt: DateTime.utc(2026, 10, 26),
        rules: rules);

FilterInput feed(String text,
        {String? uid,
        Set<String> ids = const {},
        Set<String> names = const {}}) =>
    FilterInput(
        scope: FilterScope.feed,
        id: '1',
        authorUid: uid,
        text: text,
        topicIds: ids,
        topicNames: names);

void main() {
  test('指定排除词不命中，也不豁免独立命中', () {
    final engine = ContentFilterEngine(builtinFilterRules);
    for (final text in [
      'LSP',
      'lsp',
      'ＬＳＰ',
      '手冲',
      '后入',
      '性压抑',
      '本人女，想选手机',
      '我是女生，健身装机'
    ]) {
      expect(engine.evaluate(feed(text), level: FilterLevel.strict), isNull,
          reason: text);
    }
    expect(engine.evaluate(feed('LSP 想约炮')), isNotNull);
  });

  test('标准与严格档有区别且严格包含标准', () {
    final engine = ContentFilterEngine(builtinFilterRules);
    expect(engine.evaluate(feed('想约炮')), isNotNull);
    expect(engine.evaluate(feed('求 女菩萨 发福利')), isNull);
    expect(engine.evaluate(feed('求 女菩萨 发福利'), level: FilterLevel.strict),
        isNotNull);
    expect(engine.evaluate(feed('给女友选机，恋爱，女性健身')), isNull);
  });

  test('食品和游戏语境不会误中性暗示组合', () {
    final engine = ContentFilterEngine(builtinFilterRules);
    for (final text in [
      '求烧鸡做法',
      '想干掉她的游戏角色',
      '我想操作她的电脑安装系统',
      '收到约炮骚扰，该怎么举报',
      '拒绝别人约炮要求',
      '我老公用的这款手机'
    ]) {
      expect(engine.evaluate(feed(text), level: FilterLevel.strict), isNull,
          reason: text);
    }
  });

  test('排除词拆组也不能参与命中，保留独立明确性化表达', () {
    final examples = <String, List<List<String>>>{
      '手冲': [
        ['手'],
        ['冲']
      ],
      'ＬＳＰ': [
        ['l'],
        ['s'],
        ['p']
      ],
      '后入': [
        ['后'],
        ['入']
      ],
      '性压抑': [
        ['性'],
        ['压抑']
      ],
    };
    for (final entry in examples.entries) {
      final engine =
          ContentFilterEngine(rules([textRule(groups: entry.value)]));
      expect(engine.evaluate(feed(entry.key)), isNull, reason: entry.key);
    }
    final engine = ContentFilterEngine(builtinFilterRules);
    expect(engine.evaluate(feed('手冲，我想约炮')), isNotNull);
    expect(engine.evaluate(feed('反对别人约炮骚扰。想操她')), isNotNull);
    expect(engine.evaluate(feed('想操作她的电脑。想艹她')), isNotNull);
  });

  test('严格评论起哄短语不影响普通关系语境或主帖', () {
    final engine = ContentFilterEngine(builtinFilterRules);
    for (final phrase in ['叫我老公', '叫声老公', '现在得叫老公']) {
      final comment = FilterInput(scope: FilterScope.comment, text: phrase);
      expect(engine.evaluate(comment), isNull);
      expect(engine.evaluate(comment, level: FilterLevel.strict), isNotNull);
      expect(engine.evaluate(feed(phrase), level: FilterLevel.strict), isNull);
    }
    expect(
        engine.evaluate(
            const FilterInput(scope: FilterScope.comment, text: '我老公刚买的手机'),
            level: FilterLevel.strict),
        isNull);
  });

  test('密集重叠组合与缺组仍保持邻近语义', () {
    final engine = ContentFilterEngine(rules([
      textRule(groups: [
        ['a'],
        ['aa'],
        ['aaa'],
        ['aaaa'],
        ['aaaaa'],
        ['aaaaaa'],
        ['aaaaaaa'],
        ['z']
      ])
    ]));
    expect(engine.evaluate(feed('a' * 4800)), isNull);
    expect(engine.evaluate(feed('${'a' * 4800}z')), isNotNull);
  });

  test('话题完整匹配，作者只匹配实际UID', () {
    final engine = ContentFilterEngine(rules([
      const FilterRule(
          id: 'topic',
          reason: '话题',
          kind: FilterRuleKind.topic,
          values: ['110066', '我在酷安晒女友']),
      const FilterRule(
          id: 'author',
          reason: '作者',
          kind: FilterRuleKind.author,
          values: ['123']),
    ]));
    expect(engine.evaluate(feed('', ids: {'110066'}))?.ruleId, 'topic');
    expect(engine.evaluate(feed('', names: {'我在酷安晒女友'}))?.ruleId, 'topic');
    expect(engine.evaluate(feed('我在酷安晒女友', names: {'我在酷安晒女友讨论'})), isNull);
    expect(engine.evaluate(feed('回复 @123', uid: '1234')), isNull);
    expect(engine.evaluate(feed('', uid: '123'))?.ruleId, 'author');
    expect(
        engine
            .evaluate(
                const FilterInput(scope: FilterScope.comment, authorUid: '123'))
            ?.ruleId,
        'author');
  });

  test('HTML仅可见文字参与匹配，归一化全角与实体', () {
    final engine = ContentFilterEngine(rules([
      textRule(groups: [
        ['约炮']
      ])
    ]));
    expect(
        engine.evaluate(
            feed('<a href="https://x/约炮">正常技术</a><img alt="约炮" src="约炮">')),
        isNull);
    expect(engine.evaluate(feed('<script>约炮</script><style>约炮</style>正常')),
        isNull);
    expect(engine.evaluate(feed('<b>约</b>&#x70ae;')), isNotNull);
  });

  test('组合在局部窗口出现，例外仅影响命中句段', () {
    final engine = ContentFilterEngine(rules([
      textRule(exceptions: ['反对约炮'])
    ]));
    expect(engine.evaluate(feed('想 约炮')), isNotNull);
    expect(engine.evaluate(feed('想${'普通技术' * 10}约炮')), isNull);
    expect(engine.evaluate(feed('想反对约炮')), isNull);
    expect(engine.evaluate(feed('反对约炮。想约炮')), isNotNull);
  });

  test('停用、作者例外、内容例外互不越界', () {
    final engine = ContentFilterEngine(rules([textRule()]));
    final input = feed('想约炮', uid: '123');
    expect(engine.evaluate(input, disabledRuleIds: {'text.test'}), isNull);
    expect(engine.evaluate(input, allowedAuthorUids: {'123'}), isNull);
    expect(engine.evaluate(input, allowedContentKeys: {'feed:1'}), isNull);
    expect(
        engine.evaluate(input, allowedContentKeys: {'comment:1'}), isNotNull);
  });

  test('严格JSON往返且拒绝排除词、重复ID、错误字段和超限', () {
    final json = rules([textRule()]).toJson();
    expect(FilterRuleSet.fromJson(json).toJson(), json);
    for (final excluded in ['LSP', 'ｌｓｐ', '手冲', '后入', '性压抑']) {
      final bad = textRule().toJson()
        ..['groups'] = [
          [excluded]
        ];
      expect(() => FilterRule.fromJson(bad), throwsFormatException);
    }
    expect(() => FilterRuleSet.fromJson({...json, 'revision': 0}),
        throwsFormatException);
    expect(() => FilterRuleSet.fromJson({...json, 'schemaVersion': 2}),
        throwsFormatException);
    expect(() => FilterRuleSet.fromJson({...json, 'extra': true}),
        throwsFormatException);
    expect(
        () => FilterRuleSet.fromJson({
              ...json,
              'rules': [textRule().toJson(), textRule().toJson()]
            }),
        throwsFormatException);
    expect(
        () => FilterRule.fromJson(
            {...textRule().toJson(), 'maxDistance': 100000}),
        throwsFormatException);
    expect(
        () => FilterRule.fromJson({
              ...textRule().toJson(),
              'groups': [
                ['a' * 257]
              ]
            }),
        throwsFormatException);
  });
}
