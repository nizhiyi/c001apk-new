import 'content_filter_rule.dart';

/// Reviewed local defaults; a newer subscription replaces this entire set.
FilterRuleSet get builtinFilterRules =>
    FilterRuleSet(revision: 1, publishedAt: DateTime.utc(2026, 10, 26), rules: [
      FilterRule(
          id: 'topic.partner-showcase',
          reason: '伴侣展示话题',
          kind: FilterRuleKind.topic,
          values: const ['110066', '我在酷安晒女友'],
          reviewedAt: DateTime.utc(2026, 10, 26),
          sources: const ['https://www.coolapk.com/t/我在酷安晒女友']),
      FilterRule(
          id: 'author.partner-showcase.1007278',
          reason: '持续发布伴侣展示内容',
          kind: FilterRuleKind.author,
          values: const ['1007278'],
          reviewedAt: DateTime.utc(2026, 10, 26),
          sources: const ['https://www.coolapk.com/u/1007278']),
      FilterRule(
          id: 'author.model-series.10202630',
          reason: '持续发布模特／Cos摄影系列',
          kind: FilterRuleKind.author,
          values: const ['10202630'],
          reviewedAt: DateTime.utc(2026, 10, 26),
          sources: const ['https://www.coolapk.com/u/10202630']),
      const FilterRule(
          id: 'text.explicit-solicitation',
          reason: '明确的性邀约',
          kind: FilterRuleKind.text,
          scopes: {
            FilterScope.feed,
            FilterScope.comment
          },
          groups: [
            ['想约炮', '求约炮', '来约炮', '一起约炮', '找人约炮', '约炮吗', '约炮么']
          ],
          exceptions: [
            '反对',
            '拒绝',
            '不要',
            '抵制',
            '警惕',
            '骚扰',
            '举报',
            '困扰'
          ]),
      const FilterRule(
          id: 'text.explicit-objectification',
          reason: '明确的性意淫表达',
          kind: FilterRuleKind.text,
          scopes: {FilterScope.feed, FilterScope.comment},
          groups: [
            ['想操她', '想艹她', '想操这个妹', '想艹这个妹', '想操这女的', '想艹这女的']
          ],
          maxDistance: 24),
      const FilterRule(
          id: 'text.strict-suggestive-solicitation',
          reason: '性暗示索取内容',
          kind: FilterRuleKind.text,
          level: FilterLevel.strict,
          scopes: {FilterScope.feed, FilterScope.comment},
          groups: [
            ['女菩萨'],
            ['发福利']
          ],
          maxDistance: 32),
      const FilterRule(
          id: 'text.strict-comment-spouse-bait',
          reason: '评论中的性化起哄',
          kind: FilterRuleKind.text,
          level: FilterLevel.strict,
          scopes: {
            FilterScope.comment
          },
          groups: [
            ['叫我老公', '叫声老公', '现在得叫老公']
          ]),
    ]);
