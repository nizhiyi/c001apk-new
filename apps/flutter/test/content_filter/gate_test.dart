import 'dart:io';
import 'dart:async';
import 'package:c001apk_flutter/components/content_filter_gate.dart';
import 'package:c001apk_flutter/logic/content_filter/app_content_filter.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_service.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory temp;
  late Box<dynamic> box;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('filter-gate-');
    Hive.init(temp.path);
    box = await Hive.openBox('filter');
    await box.put('enabled', true);
    AppContentFilter.service = ContentFilterService(box);
  });
  tearDown(() async {
    AppContentFilter.service!.dispose();
    AppContentFilter.service = null;
    await box.close();
    await temp.delete(recursive: true);
  });

  testWidgets(
      'hidden content builds only after temporary reveal; replies remain',
      (tester) async {
    var built = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ContentFilterGate(
      data: Datum(entityType: 'feed_reply', id: 1, uid: 1007278),
      hiddenChildren: (_) => const Text('正常回复'),
      builder: (_) {
        built++;
        return const Text('被过滤原文');
      },
    ))));
    expect(built, 0);
    expect(find.text('正常回复'), findsOneWidget);
    await tester.tap(find.text('仅本次查看'));
    await tester.pump();
    expect(find.text('被过滤原文'), findsOneWidget);
    expect(AppContentFilter.service!.allowedContentKeys, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('disabled rule restores visible content immediately',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ContentFilterGate(
      data: Datum(entityType: 'feed', id: 1, uid: 1007278),
      builder: (_) => const Text('恢复内容'),
    ))));
    await tester.runAsync(() async {
      final changed = Completer<void>();
      void listener() {
        if (!changed.isCompleted) changed.complete();
      }

      AppContentFilter.service!.addListener(listener);
      try {
        await tester.tap(find.text('停用此规则'));
        await changed.future.timeout(const Duration(seconds: 3));
      } finally {
        AppContentFilter.service!.removeListener(listener);
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('恢复内容'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('comment placeholder works on the Cupertino reply sheet',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CupertinoPageScaffold(
            child: ContentFilterGate(
      data: Datum(entityType: 'feed_reply', id: 1, uid: 1007278),
      builder: (_) => const Text('hidden'),
    ))));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
