import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:c001apk_flutter/components/expressive_loading_indicator.dart';
import 'package:c001apk_flutter/pages/home/app/app_list_controller.dart';
import 'package:c001apk_flutter/pages/home/app/app_list_page.dart';
import 'package:c001apk_flutter/pages/home/return_top_controller.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory temp;
  late Completer<List<Map<String, String>>> installedApps;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-app-list-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
  });
  setUp(() {
    installedApps = Completer();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppListController.platform, (call) async {
      expect(call.method, 'getInstalledApps');
      return installedApps.future;
    });
    Get.put(ReturnTopController(), tag: 'home');
  });
  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppListController.platform, null);
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  const apps = [
    {'appName': '测试应用', 'packageName': 'test.app', 'versionName': '1.0'}
  ];

  testWidgets('scrolling fully hides the update action above a floating bar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    installedApps.complete(List.generate(
        40,
        (i) => {
              'appName': '测试应用 $i',
              'packageName': 'test.app.$i',
              'versionName': '1.0',
            }));
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey,
        child: GetMaterialApp(
            theme: ThemeData(scaffoldBackgroundColor: const Color(0xff123456)),
            home: const MediaQuery(
              data: MediaQueryData(
                  padding: EdgeInsets.only(bottom: 102),
                  viewPadding: EdgeInsets.only(bottom: 102)),
              child: AppListPage(),
            ))));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton).hitTestable(), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton).hitTestable(), findsNothing);
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final bytes = (await tester
        .runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    // The legacy 2x-height slide leaves the colored FAB at this visible pixel,
    // even though its original hit box no longer receives taps.
    expect(image.width, 400);
    for (final y in [654, 682, 766]) {
      expect(
          bytes.buffer
              .asUint8List()
              .sublist((y * 400 + 356) * 4, (y * 400 + 356) * 4 + 4),
          [0x12, 0x34, 0x56, 0xff]);
    }
    image.dispose();
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton).hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'installed apps use expressive loading until enumeration finishes',
      (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: AppListPage()));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    installedApps.complete(apps);
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(find.text('测试应用'), findsOneWidget);
    expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'pull to refresh keeps installed apps visible with expressive loading',
      (tester) async {
    installedApps.complete(apps);
    await tester.pumpWidget(const GetMaterialApp(home: AppListPage()));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    installedApps = Completer();
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('测试应用'), findsOneWidget);
    installedApps.complete(apps);
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    expect(find.text('测试应用'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
