import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:c001apk_flutter/logic/content_filter/app_content_filter.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_rule.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_service.dart';
import 'package:c001apk_flutter/pages/settings/content_filter_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _MissingRules implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString('未发布', 404);
  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late ContentFilterService service;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('filter-settings-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('filter-settings');
    final dio = Dio()..httpClientAdapter = _MissingRules();
    service = ContentFilterService(box, dio: dio);
  });
  tearDown(() async {
    AppContentFilter.service = null;
    service.dispose();
    await box.close();
    await directory.delete(recursive: true);
  });

  Future<void> showPage(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: ContentFilterPage(service: service))));
    await tester.pumpAndSettle();
  }

  Future<void> performAction(
      WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(() async {
      final changed = Completer<void>();
      void listener() {
        if (!changed.isCompleted) changed.complete();
      }

      service.addListener(listener);
      try {
        await action();
        // Await the actual persistence notification, rather than assuming a
        // widget pump also advances Hive's real IO work.
        await changed.future.timeout(const Duration(seconds: 3));
        for (var attempt = 0; attempt < 200; attempt++) {
          if (!service.updating) return;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        fail('规则更新未在离线测试中完成');
      } finally {
        service.removeListener(listener);
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets('默认关闭，开关和档位变化保存，404保留内置规则', (tester) async {
    await showPage(tester);
    expect(find.text('屏蔽傻逼内容'), findsWidgets);
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('filter-enabled')))
            .value,
        isFalse);
    await performAction(tester, () async {
      await tester.tap(find.byKey(const ValueKey('filter-enabled')));
    });
    await tester.pumpAndSettle();
    expect(service.enabled, isTrue);
    await tester.scrollUntilVisible(find.text('严格'), 150);
    await performAction(tester, () async {
      await tester.tap(find.text('严格'));
    });
    await tester.pumpAndSettle();
    expect(service.level, FilterLevel.strict);
    await tester.scrollUntilVisible(find.text('检查规则更新'), 150);
    expect(find.textContaining('规则更新失败'), findsOneWidget);
    expect(service.ruleSet.rules, isNotEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('规则可停用恢复，个人规则可添加删除', (tester) async {
    await showPage(tester);
    await tester.scrollUntilVisible(find.text('规则与名单'), 200);
    await tester.tap(find.text('规则与名单'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('filter-list-topic'));
    await tester.scrollUntilVisible(toggle, 120);
    await tester.pumpAndSettle();
    await performAction(tester, () async {
      await tester.tap(toggle);
    });
    await tester.pumpAndSettle();
    expect(service.isListEnabled(FilterRuleKind.topic), isFalse);
    await performAction(tester, () async {
      await tester.tap(toggle);
    });
    await tester.pumpAndSettle();
    expect(service.isListEnabled(FilterRuleKind.topic), isTrue);
    await tester.scrollUntilVisible(find.text('添加个人规则'), 200);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('添加个人规则'));
    });
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('filter-rule-value')), '个人测试短语');
    await performAction(tester, () async {
      await tester.tap(find.text('添加'));
    });
    await tester.pumpAndSettle();
    expect(service.personalRules.single.groups, [
      ['个人测试短语']
    ]);
    await tester.scrollUntilVisible(find.byTooltip('删除个人规则：个人测试短语'), 100);
    await performAction(tester, () async {
      await tester.tap(find.byTooltip('删除个人规则：个人测试短语'));
    });
    await tester.pumpAndSettle();
    expect(service.personalRules, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('订阅名单只提供分类开关，不展示用户或话题条目', (tester) async {
    await showPage(tester);
    await tester.scrollUntilVisible(find.text('规则与名单'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('规则与名单'));
    await tester.pumpAndSettle();
    final authorToggle = find.byKey(const ValueKey('filter-list-author'));
    await tester.scrollUntilVisible(authorToggle, 150);
    await tester.pumpAndSettle();
    expect(find.text('频繁发布低俗内容的用户'), findsOneWidget);
    expect(find.text('低俗内容相关话题'), findsOneWidget);
    for (final rule in service.ruleSet.rules) {
      if (rule.kind == FilterRuleKind.text) {
        expect(find.text(rule.reason), findsOneWidget);
      } else {
        expect(find.textContaining(rule.reason), findsNothing);
        for (final value in rule.values) {
          expect(find.textContaining(value), findsNothing);
        }
      }
    }
    await performAction(tester, () async {
      await tester.tap(authorToggle);
    });
    expect(service.isListEnabled(FilterRuleKind.author), isFalse);
    expect(service.isListEnabled(FilterRuleKind.topic), isTrue);
    await performAction(tester, () async {
      await tester.tap(authorToggle);
    });
    expect(service.isListEnabled(FilterRuleKind.author), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('排除词无法添加，例外可移除', (tester) async {
    await tester.runAsync(() async {
      await service.setAuthorAllowed('123', true);
      await service.setContentAllowed('feed:77', true);
    });
    await showPage(tester);
    await tester.scrollUntilVisible(find.text('添加个人规则'), 200);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('添加个人规则'));
    });
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('filter-rule-value')), 'ＬＳＰ');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(service.personalRules, isEmpty);
    expect(find.text('该短语不能作为过滤规则'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('移除作者例外：123'), 150);
    await performAction(tester, () async {
      await tester.tap(find.byTooltip('移除作者例外：123'));
    });
    await tester.pumpAndSettle();
    expect(service.allowedAuthorUids, isEmpty);
    await tester.scrollUntilVisible(find.byTooltip('移除内容例外：feed:77'), 150);
    await performAction(tester, () async {
      await tester.tap(find.byTooltip('移除内容例外：feed:77'));
    });
    await tester.pumpAndSettle();
    expect(service.allowedContentKeys, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('个人作者、话题和作者例外可添加', (tester) async {
    await showPage(tester);
    for (final entry in [
      (kind: FilterRuleKind.author, label: '作者 UID', value: '3456'),
      (kind: FilterRuleKind.topic, label: '话题', value: '合成话题'),
    ]) {
      await tester.scrollUntilVisible(find.text('添加个人规则'), 180);
      await tester.runAsync(() async {
        await tester.tap(find.text('添加个人规则'));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<FilterRuleKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.label).last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('filter-rule-value')), entry.value);
      await performAction(tester, () async {
        await tester.tap(find.text('添加'));
      });
      await tester.pumpAndSettle();
      expect(service.personalRules.last.kind, entry.kind);
      expect(service.personalRules.last.values, [entry.value]);
    }
    await tester.scrollUntilVisible(find.text('添加作者例外'), 180);
    await tester.runAsync(() async {
      await tester.tap(find.text('添加作者例外'));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '999');
    await performAction(tester, () async {
      await tester.tap(find.text('添加'));
    });
    await tester.pumpAndSettle();
    expect(service.allowedAuthorUids, contains('999'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('320窄窗和大字可滚动浏览，无溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showPage(tester, scale: 1.7);
    await tester.scrollUntilVisible(find.text('规则与名单'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('规则与名单'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('filter-list-topic')), 250);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('允许显示的内容'), 250);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
