import 'dart:io';
import 'dart:convert';
import 'package:c001apk_flutter/logic/content_filter/app_content_filter.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_projection.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_service.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/logic/model/feed/relation_row.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory temp;
  late Box<dynamic> box;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('filter-projection-');
    Hive.init(temp.path);
    GStorage.blackList = await Hive.openBox('blackList');
    box = await Hive.openBox('filter');
  });
  setUp(() async {
    await box.clear();
    await GStorage.blackList.clear();
    await box.put('enabled', true);
    AppContentFilter.service = ContentFilterService(box);
  });
  tearDown(() {
    AppContentFilter.service?.dispose();
    AppContentFilter.service = null;
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('topic metadata uses full names and IDs, not similar text', () {
    expect(
        ContentFilterProjection.match(
            Datum(entityType: 'feed', tags: '我在酷安晒女友')),
        isNotNull);
    expect(
        ContentFilterProjection.match(
            Datum(entityType: 'feed', tags: '我在酷安晒女友的手机')),
        isNull);
    expect(
        ContentFilterProjection.match(Datum(
            entityType: 'feed',
            relationRows: [RelationRow(id: 110066, entityType: 'topic')])),
        isNotNull);
  });
  test('normal parent and reply-to blocked author remain visible', () {
    final child =
        Datum(entityType: 'feed_reply', id: 2, uid: 1007278, message: 'hello');
    final parent = Datum(
        entityType: 'feed', id: 1, uid: 7, message: '刷机方法', replyRows: [child]);
    expect(ContentFilterProjection.match(parent), isNull);
    expect(ContentFilterProjection.match(child), isNotNull);
    expect(
        ContentFilterProjection.match(Datum(
            entityType: 'feed_reply', uid: 8, ruid: 1007278, message: '感谢分享')),
        isNull);
  });
  test('quoted text is redacted without hiding the normal reply', () {
    final reply = Datum(
        entityType: 'feed_reply',
        uid: 8,
        message: '<blockquote>想操她</blockquote>请不要这样说');
    expect(ContentFilterProjection.match(reply), isNull);
    final text = ContentFilterProjection.displayMessage(reply);
    expect(text, isNot(contains('想操她')));
    expect(text, contains('请不要这样说'));
  });
  test('export removes blocked nested material without mutating live models',
      () {
    final feed = Datum(
        entityType: 'feed',
        id: 1,
        uid: 7,
        message: '技术',
        forwardSourceType: 'feed',
        forwardSourceFeed:
            Datum(entityType: 'feed', uid: 1007278, message: '敏感原文'),
        replyRows: [
          Datum(
              entityType: 'feed_reply',
              uid: 1007278,
              message: '隐藏父评论',
              replyRows: [
                Datum(entityType: 'feed_reply', uid: 8, message: '正常回复')
              ])
        ]);
    final copy = ContentFilterProjection.exportCopy(feed);
    expect(copy.forwardSourceFeed?.message, isNot(contains('敏感原文')));
    expect(copy.replyRows?.single.message, isNot(contains('隐藏父评论')));
    expect(copy.replyRows?.single.replyRows?.single.message, '正常回复');
    expect(feed.forwardSourceFeed?.message, '敏感原文');
  });
  test('messages and notifications are outside new filtering scope', () {
    expect(
        ContentFilterProjection.match(
            Datum(entityType: 'notification', uid: 1007278, message: '想操她')),
        isNull);
    expect(
        ContentFilterProjection.match(
            Datum(entityType: 'message', uid: 1007278, message: '想操她')),
        isNull);
  });
  test('legacy personal block survives disabling the new service', () async {
    await AppContentFilter.service!.setEnabled(false);
    await GStorage.blackList.put(BlackListBoxKey.userBlackList, ['8']);
    expect(ContentFilterProjection.match(Datum(entityType: 'feed', uid: 8)),
        isNotNull);
    expect(
        ContentFilterProjection.match(Datum(entityType: 'feed', uid: 1007278)),
        isNull);
  });
  test('Markdown quoted expression does not label the ordinary reply', () {
    final data = Datum(entityType: 'feed_reply', message: '> 想操她\n\n请文明讨论');
    expect(ContentFilterProjection.match(data), isNull);
    expect(
        ContentFilterProjection.displayMessage(data), isNot(contains('想操她')));
    expect(ContentFilterProjection.displayMessage(data), contains('请文明讨论'));
  });
  test('nested Markdown quotes are redacted without hiding the outer reply',
      () {
    final data = Datum(entityType: 'feed_reply', message: '> > 想操她\n\n请文明讨论');
    expect(ContentFilterProjection.match(data), isNull);
    expect(
        ContentFilterProjection.displayMessage(data), isNot(contains('想操她')));
  });
  test('quoted reliable topic link is redacted independently', () {
    final data = Datum(
        entityType: 'feed_reply',
        message:
            '<blockquote><a href="/t/我在酷安晒女友">#我在酷安晒女友#</a></blockquote>讨论过滤功能');
    expect(ContentFilterProjection.match(data), isNull);
    expect(
        ContentFilterProjection.displayMessage(data), isNot(contains('href')));
  });
  test('image captions and shared-link titles participate in article judgment',
      () {
    for (final part in [
      {'type': 'image', 'description': '想操她'},
      {'type': 'shareUrl', 'title': '想操她'}
    ]) {
      final data = Datum(
          entityType: 'feed',
          message: '普通摘要',
          messageRawOutput: jsonEncode([part]));
      expect(ContentFilterProjection.match(data), isNotNull);
    }
  });
}
