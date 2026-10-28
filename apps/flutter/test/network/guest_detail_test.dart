import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/logic/state/loading_state.dart';
import 'package:c001apk_flutter/pages/feed/feed_controller.dart';
import 'package:c001apk_flutter/pages/feed/feed_page.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

// Only the external transport is replaced; requests, headers, models and the
// controller all run normally. Content and device data are synthetic.
class GuestDetailAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  dynamic replyBody = {'data': []};
  Map<String, dynamic> apiBody = {
    'code': 403,
    'messageStatus': 'err_request_captcha_v2',
    'message': '需要验证码',
  };
  dynamic webBody = {
    'status': 0,
    'error': 0,
    'messageStatus': 0,
    'data': {
      'id': 123,
      'entityType': 'feed',
      'uid': 10,
      'userInfo': {'uid': 10, 'username': '合成作者'},
      'message': '完整的合成动态正文',
      'message_raw_output': '[]',
      'replynum': 0,
    },
  };

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final isWeb = options.uri.host == 'www.coolapk.com';
    final body = isWeb
        ? webBody
        : options.uri.path == '/v6/feed/replyList'
            ? replyBody
            : apiBody;
    return ResponseBody.fromString(
        body is String ? body : jsonEncode(body), 200,
        headers: {
          Headers.contentTypeHeader: [isWeb ? 'text/html' : 'application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory temp;
  late GuestDetailAdapter adapter;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-guest-detail-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
    GStorage.blackList = await Hive.openBox('blackList');
    GStorage.favFeed = await Hive.openBox('favFeed');
    await GStorage.settings.putAll({
      SettingsBoxKey.xAppDevice: 'synthetic-test-device',
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.versionName: '16.2.0',
      SettingsBoxKey.apiVersion: '16',
      SettingsBoxKey.sdkInt: '33',
      SettingsBoxKey.userAgent: 'SyntheticTest/1.0',
      SettingsBoxKey.recordHistory: false,
    });
    Request();
  });
  setUp(() async {
    await GStorage.settings.delete(SettingsBoxKey.szlmId);
    GlobalData().isLogin = false;
    GlobalData().SESSID = 'SESSID=synthetic-session';
    adapter = GuestDetailAdapter();
    Request.dio.httpClientAdapter = adapter;
  });
  tearDown(() {
    Get.reset();
    Request().captchaVerifier = null;
    GlobalData().isLogin = false;
    GlobalData().SESSID = '';
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('guest opens complete feed through public page when API needs captcha',
      () async {
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    expect(
        (controller.feedState.value as Success).response.message, '完整的合成动态正文');
    final web = adapter.requests
        .singleWhere((request) => request.uri.host == 'www.coolapk.com');
    expect(web.uri.path, '/feed/123');
    expect(web.method, 'GET');
    expect(web.headers['X-App-Token'], startsWith('v3'));
    expect(web.headers, isNot(contains('Cookie')));
    expect(controller.articleList, isEmpty);
  });

  test('guest article renders all structured text and images', () async {
    final data = adapter.webBody['data'] as Map<String, dynamic>;
    data['title'] = '合成内核文章';
    data['message_raw_output'] = jsonEncode([
      {'type': 'text', 'message': '开头'},
      {'type': 'image', 'url': 'https://image.coolapk.com/synthetic.jpg'},
      {'type': 'text', 'message': '文章末尾'},
    ]);
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    expect(controller.articleList!.map((block) => block.type),
        ['title', 'text', 'image', 'text']);
    expect(controller.articleList!.last.message, '文章末尾');
    expect(
        controller.articleImgList, ['https://image.coolapk.com/synthetic.jpg']);
  });

  test('public feed with a summary title keeps its full normal body and photos',
      () async {
    final data = adapter.webBody['data'] as Map<String, dynamic>;
    data['title'] = '分享页摘要标题';
    data['picArr'] = ['https://image.coolapk.com/synthetic-feed.jpg'];
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    expect(controller.articleList, isEmpty);
    final feed = (controller.feedState.value as Success).response;
    expect(feed.message, '完整的合成动态正文');
    expect(feed.picArr, ['https://image.coolapk.com/synthetic-feed.jpg']);
  });

  test('successful API detail does not request the public page', () async {
    adapter.apiBody = {'data': adapter.webBody['data']};
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    expect(adapter.requests.where((r) => r.uri.host == 'www.coolapk.com'),
        isEmpty);
  });

  test('without an imported identity detail and refresh never request replies',
      () async {
    adapter.apiBody = {'data': adapter.webBody['data']};
    var prompts = 0;
    Request().captchaVerifier = (_) async {
      prompts++;
      return null;
    };
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    while (controller.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    controller.onReset();
    await controller.onGetData();
    await controller.onGetData(false);
    expect(controller.feedState.value, isA<Success>());
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
        isEmpty,
        reason: '${adapter.requests.map((r) => r.uri)}; '
            '${controller.loadingState.value}');
    expect(prompts, 0);
  });

  test('imported identity keeps automatic comment loading', () async {
    await GStorage.settings.put(SettingsBoxKey.szlmId, 'synthetic-imported-id');
    adapter.apiBody = {'data': adapter.webBody['data']};
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    while (controller.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(controller.loadingState.value, isA<Empty>());
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
        hasLength(1));
  });

  test('explicit comment action verifies once and supports cancellation retry',
      () async {
    adapter.apiBody = {'data': adapter.webBody['data']};
    adapter.replyBody = {
      'messageStatus': 'err_request_captcha_v2',
      'messageExtra': {
        'captchaId': '0123456789abcdef0123456789abcdef',
        'captchaField': '_token',
      },
    };
    var prompts = 0;
    final started = Completer<void>();
    final cancelled = Completer<String?>();
    Request().captchaVerifier = (_) {
      prompts++;
      started.complete();
      return cancelled.future;
    };
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final body = controller.feedState.value;
    final pending = controller.loadReplies();
    await started.future;
    await controller.loadReplies();
    expect(prompts, 1);
    cancelled.complete(null);
    await pending;
    expect(controller.loadingState.value, isA<Error>());
    expect(controller.feedState.value, same(body));
    controller.onReset();
    await controller.onGetData();
    expect(prompts, 1);
    Request().captchaVerifier = (challenge) async {
      prompts++;
      adapter.replyBody = {'data': []};
      return challenge.proof('synthetic-proof');
    };
    await controller.loadReplies();
    expect(controller.loadingState.value, isA<Empty>());
    expect(controller.feedState.value, same(body));
    expect(prompts, 2);
  });

  for (final initialOffset in [0.0, 140.0]) {
    testWidgets(
        'horizontal Markdown scroll preserves the header at vertical offset $initialOffset',
        (tester) async {
      adapter.apiBody = {
        'data': {
          ...(adapter.webBody['data'] as Map<String, dynamic>),
          'feedTypeName': '图文',
          'message':
              '```text\n${List.filled(12, 'long_code_' * 40).join('\n')}\n```\n\n'
                  '${List.filled(30, '正文段落。' * 20).join('\n\n')}',
        }
      };
      await tester.pumpWidget(const GetMaterialApp(home: FeedPage(id: '123')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final pageScroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView).first)
          .controller!;
      pageScroll.jumpTo(initialOffset);
      await tester.pumpAndSettle();
      final headerAuthor =
          find.descendant(of: find.byType(AppBar), matching: find.text('合成作者'));
      expect(headerAuthor, initialOffset > 50 ? findsOneWidget : findsNothing);
      final codeScroll = find
          .byWidgetPredicate((widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal)
          .first;
      final horizontal = tester
          .state<ScrollableState>(find
              .descendant(of: codeScroll, matching: find.byType(Scrollable))
              .first)
          .position;
      horizontal.jumpTo(180);
      await tester.pumpAndSettle();
      expect(horizontal.pixels, greaterThan(50));
      expect(headerAuthor, initialOffset > 50 ? findsOneWidget : findsNothing);
      horizontal.jumpTo(0);
      await tester.pumpAndSettle();
      expect(headerAuthor, initialOffset > 50 ? findsOneWidget : findsNothing);
      expect(pageScroll.offset, closeTo(initialOffset, 0.1));
      // The article's own vertical scroll must still show and hide the header.
      pageScroll.jumpTo(initialOffset > 50 ? 0 : 140);
      await tester.pumpAndSettle();
      expect(headerAuthor, initialOffset > 50 ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('scrolling to comments shows an action without a request',
      (tester) async {
    adapter.apiBody = {
      'data': {
        ...(adapter.webBody['data'] as Map<String, dynamic>),
        'feedTypeName': '图文',
        'message_raw_output': jsonEncode(List.generate(
            12, (i) => {'type': 'text', 'message': '第 $i 段合成正文。' * 20})),
      }
    };
    await tester.pumpWidget(const GetMaterialApp(home: FeedPage(id: '123')));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final action = find.widgetWithText(FilledButton, '加载评论并验证');
    expect(action.hitTestable(), findsNothing);
    await tester.scrollUntilVisible(action, 400,
        scrollable: find.byType(Scrollable).last, maxScrolls: 50);
    await tester.pumpAndSettle();
    expect(action.hitTestable(), findsOneWidget);
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
        isEmpty);
    await tester.tap(action);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('暂无内容'), findsOneWidget);
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
        hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('cancelled next-page verification preserves comments and pauses refresh',
      () async {
    adapter.apiBody = {'data': adapter.webBody['data']};
    adapter.replyBody = {
      'data': [
        {'id': 456, 'entityType': 'feed_reply', 'message': '已读评论'},
      ]
    };
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    await controller.loadReplies();
    final comments = controller.loadingState.value as Success;
    expect(comments.response.single.message, '已读评论');
    adapter.replyBody = {
      'messageStatus': 'err_request_captcha_v2',
      'messageExtra': {
        'captchaId': '0123456789abcdef0123456789abcdef',
        'captchaField': '_token',
      },
    };
    var prompts = 0;
    Request().captchaVerifier = (_) async {
      prompts++;
      return null;
    };
    await controller.onGetData(false);
    expect(controller.footerState.value, isA<Error>());
    expect(controller.loadingState.value, same(comments));
    controller.listType = 'dateline_desc';
    controller.onReset();
    await controller.onGetData();
    expect(prompts, 1);
    expect(controller.loadingState.value, same(comments));
    adapter.replyBody = {'data': []};
    await controller.loadReplies();
    expect(controller.loadingState.value, isA<Empty>());
    expect(adapter.requests.last.queryParameters['page'], 1);
    expect(adapter.requests.last.queryParameters['listType'], 'dateline_desc');
  });

  test('normal feed without structured article output remains readable',
      () async {
    (adapter.webBody['data'] as Map<String, dynamic>)
        .remove('message_raw_output');
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    expect(controller.articleList, isEmpty);
  });

  test('malformed structured article reports an error without leaving loading',
      () async {
    (adapter.webBody['data'] as Map<String, dynamic>)['message_raw_output'] =
        '{broken';
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Error>());
    expect((controller.feedState.value as Error).errMsg, contains('解析'));
  });

  test('removed content is not retried as a public page', () async {
    adapter.apiBody = {'code': 404, 'message': '动态不存在'};
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Error>());
    expect(adapter.requests, hasLength(1));
  });

  test(
      'logged in captcha reads public body without changing login or like state',
      () async {
    GlobalData().isLogin = true;
    GlobalData().uid = 'synthetic-uid';
    GlobalData().token = 'synthetic-token';
    (adapter.webBody['data'] as Map<String, dynamic>)['userAction'] = {
      'like': 1
    };
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    final result = controller.feedState.value as Success;
    expect(result.response.message, '完整的合成动态正文');
    expect(result.response.userAction, isNull);
    expect(GlobalData().isLogin, isTrue);
    expect(GlobalData().uid, 'synthetic-uid');
    expect(GlobalData().token, 'synthetic-token');
    final web =
        adapter.requests.singleWhere((r) => r.uri.host == 'www.coolapk.com');
    expect(web.headers, isNot(contains('Cookie')));
  });

  test('guest login requirement can read the official public representation',
      () async {
    adapter.apiBody = {'code': 401, 'messageStatus': 'err_not_login'};
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    expect((controller.feedState.value as Success).response.id, 123);
  });

  test('rejected verified detail preserves public body and reports the failure',
      () async {
    GlobalData().isLogin = true;
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final previous = controller.feedState.value;
    Request().captchaVerifier =
        (challenge) async => challenge.proof('synthetic-validate');
    await controller.getFeedData(verify: true);
    expect(controller.feedState.value, same(previous));
    expect((controller as dynamic).accountDetailNotice.value, contains('仍未'));
    expect(adapter.requests.where((r) => r.uri.host == 'www.coolapk.com'),
        hasLength(1));
  });

  test('cancelled verification keeps public body and explains cancellation',
      () async {
    GlobalData().isLogin = true;
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final previous = controller.feedState.value;
    Request().captchaVerifier = (_) async => null;
    await controller.getFeedData(verify: true);
    expect(controller.feedState.value, same(previous));
    expect((controller as dynamic).accountDetailNotice.value, contains('取消'));
  });

  test('verified account detail replaces public body and clears the notice',
      () async {
    GlobalData().isLogin = true;
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    Request().captchaVerifier = (challenge) async {
      adapter.apiBody = {
        'data': {
          ...(adapter.webBody['data'] as Map<String, dynamic>),
          'userAction': {'like': 1},
        }
      };
      return challenge.proof('synthetic-validate');
    };
    await controller.getFeedData(verify: true);
    final result = controller.feedState.value as Success;
    expect(result.isPublic, isFalse);
    expect(result.response.userAction.like, 1);
    expect((controller as dynamic).accountDetailNotice.value, isEmpty);
  });

  test('invalid account article keeps previously readable public article',
      () async {
    (adapter.webBody['data'] as Map<String, dynamic>)['message_raw_output'] =
        jsonEncode([
      {'type': 'text', 'message': '公开文章完整正文'}
    ]);
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final previous = controller.feedState.value;
    adapter.apiBody = {
      'data': {
        ...(adapter.webBody['data'] as Map<String, dynamic>),
        'message_raw_output': '{broken',
      }
    };
    await controller.getFeedData(verify: true);
    expect(controller.feedState.value, same(previous));
    expect(controller.articleList, hasLength(1));
    expect(controller.articleList!.single.message, '公开文章完整正文');
  });

  test('repeated detail retry taps open only one verification request',
      () async {
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final started = Completer<void>();
    final proof = Completer<String?>();
    var prompts = 0;
    Request().captchaVerifier = (_) {
      prompts++;
      started.complete();
      return proof.future;
    };
    final pending = controller.getFeedData(verify: true);
    await started.future;
    await controller.getFeedData(verify: true);
    expect(prompts, 1);
    expect(adapter.requests.where((r) => r.uri.path == '/v6/feed/detail'),
        hasLength(2));
    proof.complete(null);
    await pending;
    expect((controller as dynamic).isLoadingDetail.value, isFalse);
  });

  test('invalid feed identifier never becomes an external request', () async {
    final controller = FeedController(id: '../account', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Error>());
    expect(adapter.requests, isEmpty);
  });

  test('public HTML landing page remains an error instead of fake content',
      () async {
    adapter.webBody = '<html>请下载客户端</html>';
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Error>());
    expect((controller.feedState.value as Error).errMsg, contains('响应'));
    expect(adapter.requests, hasLength(2));
  });

  test('official app-only landing page explains device verification', () async {
    adapter.webBody = '<html><title>动态分享 - 酷安</title>'
        '<div>您当前查看的是「动态分享」，请用酷安手机APP扫码查看详情</div></html>';
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Error>());
    final result = controller.feedState.value as Error;
    expect(result.errMsg, contains('设备需要验证'));
    expect(result.errMsg, isNot(contains('格式异常')));
    expect((result as dynamic).canVerify, isTrue);
    expect(adapter.requests, hasLength(2));
    expect(GlobalData().isLogin, isFalse);
  });

  test('unavailable public representation retains the original login reason',
      () async {
    adapter.apiBody = {'code': 401, 'messageStatus': 'err_not_login'};
    adapter.webBody = '<html><title>图文分享 - 酷安</title>'
        '<div>请用酷安手机APP扫码查看详情</div></html>';
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final result = controller.feedState.value as Error;
    expect(result.errMsg, contains('登录'));
    expect((result as dynamic).canVerify, isTrue);
    expect(adapter.requests, hasLength(2));
  });

  for (final cancelled in [true, false]) {
    test(
        'failed verification keeps identity help without a readable body ($cancelled)',
        () async {
      adapter.webBody = '<html>请用酷安手机APP扫码查看详情</html>';
      final controller = FeedController(id: '123', recordHistory: false);
      await controller.getFeedData();
      Request().captchaVerifier = (challenge) async =>
          cancelled ? null : challenge.proof('synthetic-validation');
      await controller.getFeedData(verify: true);
      final result = controller.feedState.value as Error;
      expect(result.canVerify, isTrue);
      expect(result.errMsg, isNot(contains('正文仍可阅读')));
    });
  }
}
