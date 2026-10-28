import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:c001apk_flutter/logic/content_filter/builtin_filter_rules.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_rule.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class RuleAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  String body = '';
  int status = 200;
  Map<String, List<String>> headers = {
    Headers.contentTypeHeader: ['application/json']
  };
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(body, status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

FilterRuleSet subscription(int revision, List<FilterRule> rules) =>
    FilterRuleSet(
        revision: revision,
        publishedAt: DateTime.utc(2026, 10, 26),
        rules: rules);
FilterRule personal() => const FilterRule(
        id: 'personal.one',
        reason: '个人',
        kind: FilterRuleKind.text,
        groups: [
          ['个人屏蔽词']
        ]);

void main() {
  late Directory temp;
  late Box<dynamic> box;
  late RuleAdapter adapter;
  late Dio dio;
  late DateTime now;
  late ContentFilterService service;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('content_filter_test_');
    Hive.init(temp.path);
    box = await Hive.openBox<dynamic>('filter');
    adapter = RuleAdapter();
    dio = Dio()..httpClientAdapter = adapter;
    now = DateTime.utc(2026, 10, 26);
    adapter.body = jsonEncode(subscription(2, []).toJson());
    service = ContentFilterService(box, dio: dio, now: () => now);
  });
  tearDown(() async {
    service.dispose();
    await box.close();
    await temp.delete(recursive: true);
  });

  test('默认关闭不自动联网，首次开启标准并保存选择', () async {
    expect(service.enabled, isFalse);
    await service.checkForUpdates();
    expect(adapter.requests, isEmpty);
    await service.setEnabled(true);
    expect(service.level, FilterLevel.standard);
    expect(adapter.requests, hasLength(1));
    await service.setLevel(FilterLevel.strict);
    await service.setEnabled(false);
    await service.setEnabled(true);
    expect(service.level, FilterLevel.strict);
    final restored = ContentFilterService(box, dio: dio);
    expect(restored.enabled, isTrue);
    expect(restored.level, FilterLevel.strict);
    restored.dispose();
  });

  test('成功检查六小时冷却，强制检查可提前执行，失败不记成功', () async {
    await service.setEnabled(true);
    await service.checkForUpdates();
    expect(adapter.requests, hasLength(1));
    now = now.add(const Duration(hours: 6));
    await service.checkForUpdates();
    expect(adapter.requests, hasLength(2));
    final success = service.lastCheckedAt;
    adapter.status = 404;
    await service.checkForUpdates(force: true);
    expect(service.lastCheckedAt, success);
    expect(service.updateMessage, isNotNull);
    expect(service.ruleSet.revision, 2);
  });

  test('订阅整体替换可撤回，个人规则和例外独立保留', () async {
    adapter.body = jsonEncode(subscription(2, [
      const FilterRule(
          id: 'author.one',
          reason: '已审核',
          kind: FilterRuleKind.author,
          values: ['123'])
    ]).toJson());
    await service.setEnabled(true);
    await service.addPersonalRule(personal());
    await service.setRuleDisabled('other', true);
    await service.setAuthorAllowed('456', true);
    await service.setContentAllowed('feed:7', true);
    expect(
        service.evaluate(
            const FilterInput(scope: FilterScope.feed, authorUid: '123')),
        isNotNull);
    adapter.body = jsonEncode(subscription(3, []).toJson());
    await service.checkForUpdates(force: true);
    expect(
        service.evaluate(
            const FilterInput(scope: FilterScope.feed, authorUid: '123')),
        isNull);
    expect(
        service.evaluate(
            const FilterInput(scope: FilterScope.comment, text: '个人屏蔽词')),
        isNotNull);
    final restored = ContentFilterService(box, dio: dio);
    expect(restored.personalRules, hasLength(1));
    expect(restored.disabledRuleIds, contains('other'));
    expect(restored.allowedAuthorUids, contains('456'));
    expect(restored.allowedContentKeys, contains('feed:7'));
    restored.dispose();
    await service.removePersonalRule('personal.one');
    expect(service.personalRules, isEmpty);
  });

  test('分类关闭覆盖后续订阅新增，重启保持，个人规则独立', () async {
    List<FilterRule> rules(String uid, String topic) => [
          FilterRule(
              id: 'author.$uid',
              reason: '用户分类',
              kind: FilterRuleKind.author,
              values: [uid]),
          FilterRule(
              id: 'topic.$topic',
              reason: '话题分类',
              kind: FilterRuleKind.topic,
              values: [topic]),
          const FilterRule(
              id: 'text.synthetic',
              reason: '文本分类',
              kind: FilterRuleKind.text,
              groups: [
                ['合成过滤短语']
              ]),
        ];
    adapter.body = jsonEncode(subscription(2, rules('123', '456')).toJson());
    await service.setEnabled(true);
    expect(
        service.evaluate(
            const FilterInput(scope: FilterScope.feed, authorUid: '123')),
        isNotNull);
    await service.setListEnabled(FilterRuleKind.author, false);
    expect(
        service.evaluate(
            const FilterInput(scope: FilterScope.feed, authorUid: '123')),
        isNull);
    expect(
        service.evaluate(
            const FilterInput(scope: FilterScope.feed, topicIds: {'456'})),
        isNotNull);
    expect(
        service.evaluate(
            const FilterInput(scope: FilterScope.feed, text: '合成过滤短语')),
        isNotNull);
    await service.setListEnabled(FilterRuleKind.topic, false);
    await service.addPersonalRule(const FilterRule(
        id: 'personal.author',
        reason: '个人用户',
        kind: FilterRuleKind.author,
        values: ['123']));
    expect(
        service
            .evaluate(
                const FilterInput(scope: FilterScope.feed, authorUid: '123'))
            ?.ruleId,
        'personal.author');
    adapter.body = jsonEncode(subscription(3, rules('789', '987')).toJson());
    await service.checkForUpdates(force: true);
    final restored = ContentFilterService(box, dio: dio);
    expect(restored.isListEnabled(FilterRuleKind.author), isFalse);
    expect(restored.isListEnabled(FilterRuleKind.topic), isFalse);
    expect(
        restored.evaluate(
            const FilterInput(scope: FilterScope.feed, authorUid: '789')),
        isNull);
    expect(
        restored.evaluate(
            const FilterInput(scope: FilterScope.feed, topicIds: {'987'})),
        isNull);
    expect(
        restored
            .evaluate(
                const FilterInput(scope: FilterScope.feed, authorUid: '123'))
            ?.ruleId,
        'personal.author');
    await restored.setListEnabled(FilterRuleKind.author, true);
    expect(
        restored
            .evaluate(
                const FilterInput(scope: FilterScope.feed, authorUid: '789'))
            ?.ruleId,
        'author.789');
    expect(
        restored.evaluate(
            const FilterInput(scope: FilterScope.feed, topicIds: {'987'})),
        isNull);
    restored.dispose();
  });

  test('保留旧单条停用，主动开启分类恢复该类规则且不影响其他规则', () async {
    adapter.body = jsonEncode(subscription(2, [
      const FilterRule(
          id: 'author.one',
          reason: '用户分类',
          kind: FilterRuleKind.author,
          values: ['123']),
      const FilterRule(
          id: 'topic.one',
          reason: '话题分类',
          kind: FilterRuleKind.topic,
          values: ['456']),
    ]).toJson());
    await service.setEnabled(true);
    await service.setRuleDisabled('author.one', true);
    await service.setRuleDisabled('topic.one', true);
    final restored = ContentFilterService(box, dio: dio);
    expect(restored.isListEnabled(FilterRuleKind.author), isTrue);
    expect(
        restored.evaluate(
            const FilterInput(scope: FilterScope.feed, authorUid: '123')),
        isNull);
    await restored.setListEnabled(FilterRuleKind.author, true);
    expect(
        restored
            .evaluate(
                const FilterInput(scope: FilterScope.feed, authorUid: '123'))
            ?.ruleId,
        'author.one');
    expect(restored.disabledRuleIds, contains('topic.one'));
    restored.dispose();
  });

  test('快速连续切换两个名单不会覆盖彼此选择', () async {
    await Future.wait([
      service.setListEnabled(FilterRuleKind.author, false),
      service.setListEnabled(FilterRuleKind.topic, false),
    ]);
    final restored = ContentFilterService(box, dio: dio);
    expect(restored.isListEnabled(FilterRuleKind.author), isFalse);
    expect(restored.isListEnabled(FilterRuleKind.topic), isFalse);
    restored.dispose();
  });

  test('名单切换不覆盖同时发生的单条停用', () async {
    await Future.wait([
      service.setListEnabled(FilterRuleKind.author, false),
      service.setRuleDisabled('text.explicit-solicitation', true),
    ]);
    final restored = ContentFilterService(box, dio: dio);
    expect(restored.isListEnabled(FilterRuleKind.author), isFalse);
    expect(restored.disabledRuleIds, contains('text.explicit-solicitation'));
    expect(service.disabledRuleIds, contains('text.explicit-solicitation'));
    restored.dispose();
  });

  test('坏缓存回退内置，拒绝降级、同版本篡改、HTML、超大和重定向', () async {
    await box.put('ruleSet', {'schemaVersion': 999});
    final fallback = ContentFilterService(box, dio: dio);
    expect(fallback.ruleSet.toJson(), builtinFilterRules.toJson());
    fallback.dispose();
    await service.setEnabled(true);
    for (final payload in [
      subscription(1, []).toJson(),
      subscription(2, [personal()]).toJson(),
      '<html>error</html>',
      ' ' * (1024 * 1024 + 1),
    ]) {
      adapter.body = payload is String ? payload : jsonEncode(payload);
      await service.checkForUpdates(force: true);
      expect(service.ruleSet.toJson(), subscription(2, []).toJson());
    }
    adapter.status = 302;
    await service.checkForUpdates(force: true);
    expect(service.ruleSet.revision, 2);
    expect(adapter.requests.last.followRedirects, isFalse);
  });

  test('规则下载请求不发送身份或个人数据', () async {
    dio.options.headers['Cookie'] = 'synthetic-account-cookie';
    dio.options.headers['User-Agent'] = 'synthetic-coolapk-user-agent';
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      options.headers['X-App-Token'] = 'synthetic-account-token';
      handler.next(options);
    }));
    await service.setEnabled(true);
    final request = adapter.requests.single;
    expect(request.uri.toString(), ContentFilterService.rulesUrl);
    expect(
        request.headers.keys.map((e) => e.toLowerCase()),
        isNot(anyElement(anyOf('cookie', 'authorization', 'x-app-token',
            'x-app-device', 'x-app-id'))));
    expect(request.data, isNull);
    expect(request.queryParameters, isEmpty);
    expect(request.followRedirects, isFalse);
    expect(request.headers['User-Agent'], 'c001apk-content-filter/1');
  });

  test('个人规则也拒绝排除词', () async {
    await expectLater(
        service.addPersonalRule(const FilterRule(
            id: 'personal.bad',
            reason: '无效',
            kind: FilterRuleKind.text,
            groups: [
              ['ＬＳＰ']
            ])),
        throwsFormatException);
    expect(service.personalRules, isEmpty);
  });

  test('远端规则不能进入个人命名空间，个人规则必须使用专属前缀', () async {
    await service.setEnabled(true);
    await service.addPersonalRule(personal());
    await service.setRuleDisabled('personal.one', true);
    adapter.body = jsonEncode(subscription(3, [
      const FilterRule(
          id: 'personal.one',
          reason: '远端冲突',
          kind: FilterRuleKind.author,
          values: ['123'])
    ]).toJson());
    await service.checkForUpdates(force: true);
    expect(service.ruleSet.revision, 2);
    expect(service.personalRules.single.id, 'personal.one');
    expect(service.disabledRuleIds, contains('personal.one'));
    await expectLater(
        service.addPersonalRule(const FilterRule(
            id: 'not-personal',
            reason: '前缀无效',
            kind: FilterRuleKind.text,
            groups: [
              ['合成词']
            ])),
        throwsFormatException);
    await box.put(
        'ruleSet',
        subscription(4, [
          const FilterRule(
              id: 'personal.cached',
              reason: '缓存冲突',
              kind: FilterRuleKind.author,
              values: ['123'])
        ]).toJson());
    final restored = ContentFilterService(box, dio: dio);
    expect(restored.ruleSet.revision, builtinFilterRules.revision);
    expect(restored.personalRules.single.id, 'personal.one');
    restored.dispose();
  });
}
