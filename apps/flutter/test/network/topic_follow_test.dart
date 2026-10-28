import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/pages/topic/topic_controller.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FollowTransport implements HttpClientAdapter {
  Map<String, dynamic> body = {
    'status': 1,
    'messageStatus': 1,
    'message': '关注成功',
  };
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory temp;
  late _FollowTransport transport;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('topic-follow-test-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
    await GStorage.settings.putAll({
      SettingsBoxKey.xAppDevice: 'synthetic-topic-device',
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.recordHistory: false,
    });
    Request();
  });
  setUp(() {
    transport = _FollowTransport();
    Request.dio.httpClientAdapter = transport;
    GlobalData().isLogin = false;
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [FlutterSmartDialog.observer],
      builder: FlutterSmartDialog.init(),
      home: const Scaffold(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> settleToast(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester
        .runAsync(() => SmartDialog.dismiss(status: SmartStatus.allToast));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('topic follow and unfollow accept message-only success replies',
      (tester) async {
    await mount(tester);
    final controller = TopicController(tag: 'GitHub', id: '20827');
    await tester.runAsync(() =>
        controller.onGetFollow(false, '/v6/feed/followTag', tag: 'GitHub'));
    await settleToast(tester);
    expect(controller.isFollow, isTrue);
    expect(transport.requests.single.method, 'GET');
    expect(transport.requests.single.queryParameters, {'tag': 'GitHub'});
    transport.body = {
      'status': 1,
      'messageStatus': 1,
      'message': '取消关注成功',
    };
    await tester.runAsync(() =>
        controller.onGetFollow(true, '/v6/feed/unFollowTag', tag: 'GitHub'));
    await settleToast(tester);
    expect(controller.isFollow, isFalse);
    expect(transport.requests.last.uri.path, '/v6/feed/unFollowTag');
    await tester.pumpWidget(const SizedBox());
  });

  for (final body in [
    {'status': -2, 'messageStatus': -2, 'message': '缺少参数'},
    {'status': 0, 'message': '缺少参数'},
    {'status': 401, 'message': '请先登录'},
    {
      'status': 1,
      'messageStatus': 'err_request_captcha_v2',
      'message': '需要验证码'
    },
    {'message': '缺少参数'},
  ]) {
    testWidgets('rejected follow leaves state intact: $body', (tester) async {
      await mount(tester);
      transport.body = body;
      final controller = TopicController(tag: 'GitHub', id: '20827');
      await tester.runAsync(() =>
          controller.onGetFollow(false, '/v6/feed/followTag', tag: 'GitHub'));
      await settleToast(tester);
      expect(controller.isFollow, isFalse);
      controller.isFollow = true;
      await tester.runAsync(() =>
          controller.onGetFollow(true, '/v6/feed/unFollowTag', tag: 'GitHub'));
      await settleToast(tester);
      expect(controller.isFollow, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
