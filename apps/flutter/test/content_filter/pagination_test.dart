import 'dart:io';

import 'package:c001apk_flutter/logic/network/network_repo.dart';
import 'package:c001apk_flutter/logic/content_filter/app_content_filter.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_service.dart';
import 'package:c001apk_flutter/logic/state/loading_state.dart';
import 'package:c001apk_flutter/pages/common/common_controller.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class Pages extends CommonController {
  Pages(this.rows);
  final List<List<Map<String, dynamic>>> rows;
  final cursors = <String?>[];
  int calls = 0;

  @override
  Future<LoadingState> customGetData() async {
    cursors.add(lastItem);
    final data = calls < rows.length ? rows[calls] : <Map<String, dynamic>>[];
    calls++;
    return NetworkRepo.handleListResponse(Response(
      requestOptions: RequestOptions(path: '/v6/feed/test'),
      statusCode: 200,
      data: {'data': data},
    ));
  }
}

Map<String, dynamic> feed(int id, {String uid = '99'}) => {
      'entityType': 'feed',
      'entityId': id,
      'id': id,
      'uid': uid,
      'message': '正常技术内容',
    };

void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('filter-pagination-');
    Hive.init(temp.path);
    GStorage.blackList = await Hive.openBox('blackList');
  });
  setUp(() async {
    await GStorage.blackList.put(BlackListBoxKey.userBlackList, ['99']);
  });
  tearDown(() {
    AppContentFilter.service?.dispose();
    AppContentFilter.service = null;
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('pagination retains original last cursor when last row is blocked',
      () async {
    final controller = Pages([
      [feed(1, uid: '1'), feed(2)]
    ]);
    await controller.onGetData();
    expect(controller.lastItem, '2');
    expect((controller.loadingState.value as Success).response.single.id, 1);
    controller.onClose();
  });

  test('fully filtered page advances raw cursor to next visible page',
      () async {
    final controller = Pages([
      [feed(1)],
      [feed(2, uid: '1')]
    ]);
    await controller.onGetData();
    expect(controller.cursors, [null, '1']);
    expect((controller.loadingState.value as Success).response.single.id, 2);
    controller.onClose();
  });

  test('fully filtered pages stop after three requests and remain retryable',
      () async {
    final controller = Pages(List.generate(6, (i) => [feed(i + 1)]));
    await controller.onGetData();
    expect(controller.calls, 3);
    expect(controller.lastItem, '3');
    expect(controller.isEnd, isFalse);
    expect(controller.footerState.value, isA<Error>());
    await controller.onGetData(false);
    expect(controller.calls, 6);
    expect(controller.lastItem, '6');
    controller.onClose();
  });
  test(
      'changing filter restores cached rows without fetching or resetting cursors',
      () async {
    final box = await Hive.openBox('filter');
    await box.put('enabled', true);
    AppContentFilter.service = ContentFilterService(box);
    final controller = Pages([
      [feed(1, uid: '1007278'), feed(2, uid: '7')]
    ]);
    await controller.onGetData();
    expect((controller.loadingState.value as Success).response.length, 1);
    await AppContentFilter.service!.setEnabled(false);
    expect((controller.loadingState.value as Success).response.length, 2);
    expect(controller.calls, 1);
    expect(controller.lastItem, '2');
    controller.onClose();
  });
}
