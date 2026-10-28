import 'dart:convert';
import 'dart:io';
import 'package:c001apk_flutter/logic/content_filter/app_content_filter.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_service.dart';
import 'package:c001apk_flutter/logic/local_follow/local_follow_pager.dart';
import 'package:c001apk_flutter/logic/local_follow/local_follow_store.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/logic/model/feed_article/feed_article.dart';
import 'package:c001apk_flutter/logic/state/loading_state.dart';
import 'package:c001apk_flutter/pages/local_follow/local_follow_controller.dart';
import 'package:c001apk_flutter/pages/user/user_controller.dart';
import 'package:c001apk_flutter/utils/content_export_service.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _RevealedUser extends UserController {
  _RevealedUser() : super(uid: '1007278');
  int calls = 0;
  @override
  Future<LoadingState> customGetData() async {
    calls++;
    return Success([Datum(entityType: 'feed', uid: 1007278, id: 1)]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Box<dynamic> box;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('filter-data-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
    GStorage.blackList = await Hive.openBox('blackList');
    box = await Hive.openBox('filter');
  });
  setUp(() async {
    await box.clear();
    await box.put('enabled', true);
    AppContentFilter.service = ContentFilterService(box);
  });
  tearDown(() {
    AppContentFilter.service!.dispose();
    AppContentFilter.service = null;
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('local follow uses raw rows and cursors before display filtering',
      () async {
    final cursors = <String?>[];
    final pager =
        LocalFollowPager(['7'], fetch: (uid, page, first, last) async {
      cursors.add(last);
      return page == 1
          ? Success(<Datum>[],
              rawResponse: [Datum(id: 3, uid: 7, entityType: 'feed')],
              firstItem: '1',
              lastItem: '4')
          : const Empty();
    });
    expect((await pager.next()).map((e) => e.id), [3]);
    expect(cursors, [null, '4']);
  });
  test('local follow filters rows and restores them without a reload',
      () async {
    await LocalFollowStore().follow('1007278', '测试', '');
    var calls = 0;
    final c = LocalFollowController(fetch: (uid, page, first, last) async {
      calls++;
      return page == 1
          ? Success(
              [Datum(id: 1, uid: 1007278, entityType: 'feed', dateline: 10)])
          : const Empty();
    });
    await c.onGetData();
    expect((c.loadingState.value as Success).response, isEmpty);
    expect(c.filteredItems.length, 1);
    final oldCalls = calls;
    await AppContentFilter.service!.setEnabled(false);
    expect((c.loadingState.value as Success).response.single.id, 1);
    expect(calls, oldCalls);
    c.onClose();
  });
  test('export applies identical comment and nested-forward decisions',
      () async {
    final feed = Datum(
        id: 1,
        entityType: 'feed',
        uid: 7,
        message: '正常正文',
        forwardSourceType: 'feed',
        forwardSourceFeed:
            Datum(uid: 1007278, entityType: 'feed', message: '屏蔽原帖'),
        topReplyRows: [
          Datum(id: 2, uid: 1007278, entityType: 'feed_reply', message: '屏蔽置顶')
        ]);
    final service = ContentExportService(
        blockedUids: () => {},
        loadPopular: (_) async => Success([
              Datum(id: 3, uid: 8, entityType: 'feed_reply', message: '想操她'),
              Datum(id: 4, uid: 9, entityType: 'feed_reply', message: '正常回复'),
            ]));
    final prepared = await service.prepare(feed, format: ExportFormat.markdown);
    final text = utf8.decode(prepared.bytes);
    expect(text, contains('正常正文'));
    expect(text, contains('正常回复'));
    expect(text, isNot(contains('屏蔽置顶')));
    expect(text, isNot(contains('想操她')));
    expect(text, isNot(contains('屏蔽原帖')));
    expect(prepared.commentIds, ['4']);
    expect(feed.forwardSourceFeed!.message, '屏蔽原帖');
  });
  test('structured article quote is redacted in exported body', () async {
    final service = ContentExportService(
        blockedUids: () => {}, loadPopular: (_) async => const Empty());
    final prepared = await service.prepare(
        Datum(id: 1, uid: 7, entityType: 'feed'),
        articles: [
          FeedArticle(
              type: 'text', message: '<blockquote>想操她</blockquote>请文明讨论')
        ],
        format: ExportFormat.markdown);
    expect(utf8.decode(prepared.bytes), isNot(contains('想操她')));
    expect(utf8.decode(prepared.bytes), contains('请文明讨论'));
  });
  test('nested raw article is sanitized before export reparses it', () async {
    final service = ContentExportService(
        blockedUids: () => {}, loadPopular: (_) async => const Empty());
    final feed = Datum(
        id: 1,
        uid: 7,
        entityType: 'feed',
        message: '正文',
        forwardSourceType: 'feed',
        forwardSourceFeed: Datum(
            id: 2,
            uid: 8,
            entityType: 'feed',
            messageRawOutput: jsonEncode([
              {'type': 'text', 'message': '<blockquote>想操她</blockquote>请文明讨论'}
            ])));
    final prepared = await service.prepare(feed, format: ExportFormat.markdown);
    expect(utf8.decode(prepared.bytes), isNot(contains('想操她')));
    expect(utf8.decode(prepared.bytes), contains('请文明讨论'));
  });
  test('temporary viewing starts a previously blocked user timeline', () async {
    await GStorage.blackList.put(BlackListBoxKey.userBlackList, ['1007278']);
    final c = _RevealedUser()..isBlocked = true;
    c.setUserState(Success(Datum(entityType: 'user', uid: 1007278)));
    c.setBlockedLoaidngState();
    c.revealAuthorForPage('1007278');
    await Future<void>.delayed(Duration.zero);
    expect(c.calls, 1);
    expect((c.loadingState.value as Success).response.single.id, 1);
    c.onClose();
    await GStorage.blackList.clear();
  });
  test('reveal while profile is loading waits for the profile response',
      () async {
    await GStorage.blackList.put(BlackListBoxKey.userBlackList, ['1007278']);
    final c = _RevealedUser()..isBlocked = true;
    c.setBlockedLoaidngState();
    c.revealAuthorForPage('1007278');
    await Future<void>.delayed(Duration.zero);
    expect(c.calls, 0);
    expect(c.revealedAuthorUids, contains('1007278'));
    c.onClose();
    await GStorage.blackList.clear();
  });
}
