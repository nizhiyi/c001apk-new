import 'dart:async';

import 'package:c001apk_flutter/components/announcement_monitor.dart';
import 'package:c001apk_flutter/components/onboarding_gate.dart';
import 'package:c001apk_flutter/components/prompt_navigation.dart';
import 'package:c001apk_flutter/components/update_check_tile.dart';
import 'package:c001apk_flutter/logic/announcements/announcement_service.dart';
import 'package:c001apk_flutter/logic/app_update/update_preferences.dart';
import 'package:c001apk_flutter/logic/app_update/update_service.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_service.dart';
import 'package:c001apk_flutter/logic/onboarding/onboarding_state.dart';
import 'package:c001apk_flutter/pages/onboarding/onboarding_page.dart';
import 'package:c001apk_flutter/router/app_pages.dart';
import 'package:c001apk_flutter/utils/android_links.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../announcements/fixtures.dart';
import '../update/app_update_test.dart' show ReleaseAdapter;

class _MainProbe extends StatefulWidget {
  const _MainProbe(this.onMount);
  final VoidCallback onMount;

  @override
  State<_MainProbe> createState() => _MainProbeState();
}

class _MainProbeState extends State<_MainProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('主页面');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.awavenue.c001apk/links');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Box<dynamic> settings, filters, announcements;
  late ContentFilterService filter;
  late OnboardingState state;

  setUpAll(() async {
    settings = await Hive.openBox('startup-settings', bytes: Uint8List(0));
    GStorage.settings = settings;
  });
  tearDownAll(() async => settings.close());

  setUp(() async {
    Get.testMode = true;
    await settings.clear();
    filters = await Hive.openBox('startup-filters', bytes: Uint8List(0));
    announcements =
        await Hive.openBox('startup-announcements', bytes: Uint8List(0));
    filter = ContentFilterService(filters);
    state = OnboardingState(settings: settings, filter: filter);
  });

  tearDown(() async {
    OnboardingState.current = null;
    state.dispose();
    filter.dispose();
    await Future.wait([filters.close(), announcements.close()]);
    channel.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(channel, null);
    Get.reset();
  });

  Future<void> drain(WidgetTester tester, [int frames = 12]) async {
    for (var n = 0; n < frames; n++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> notifyLinks(WidgetTester tester) async {
    unawaited(messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('linksChanged')),
        (_) {}));
    await drain(tester);
  }

  testWidgets(
      'initial guide mounts main only after skip, once across reopening',
      (tester) async {
    var mounts = 0;
    await tester.pumpWidget(MaterialApp(
        home: OnboardingGate(
            state: state,
            mainBuilder: (_) => _MainProbe(() => mounts++),
            onboardingBuilder: (_) => const Text('首次引导'))));
    expect(find.text('首次引导'), findsOneWidget);
    expect(mounts, 0);
    await tester.runAsync(state.skip);
    await tester.pumpAndSettle();
    expect(find.text('主页面'), findsOneWidget);
    expect(mounts, 1);
    state.begin();
    await tester.pump();
    state.end();
    await tester.pump();
    expect(mounts, 1);
    expect(find.text('首次引导'), findsNothing);
  });

  test('onboarding is not replayable through mouse forward history', () {
    expect(AppPages.canReplay('/onboarding'), false);
    expect(AppPages.canReplay('/settings'), true);
  });

  testWidgets('startup update waits until guide finishes and main has mounted',
      (tester) async {
    var mainMounted = false;
    var updateChecks = 0;
    final service = AnnouncementService(announcements,
        dio: Dio()..httpClientAdapter = AnnouncementAdapter());
    addTearDown(service.dispose);
    await tester.pumpWidget(AnnouncementMonitor(
        service: service,
        onboarding: state,
        checkUpdates: () async {
          expect(mainMounted, true);
          expect(state.active, false);
          updateChecks++;
        },
        updatePromptShown: () => false,
        child: GetMaterialApp(
            navigatorObservers: [PromptNavigationObserver()],
            home: OnboardingGate(
                state: state,
                mainBuilder: (_) => _MainProbe(() => mainMounted = true),
                onboardingBuilder: (_) => const Text('首次引导')))));
    await drain(tester);
    expect(updateChecks, 0);
    await tester.runAsync(state.skip);
    await drain(tester);
    expect(updateChecks, 1);
    state.begin();
    state.end();
    await drain(tester);
    expect(updateChecks, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('announcement resumes on home after guide returns to settings',
      (tester) async {
    await tester.runAsync(state.skip);
    final adapter = AnnouncementAdapter()
      ..index = indexJson(1, [noticeJson('a', important: true)])
      ..pendingBody = Completer<void>();
    final service = AnnouncementService(announcements,
        dio: Dio()..httpClientAdapter = adapter,
        clock: () => DateTime.utc(2026, 10, 27));
    addTearDown(service.dispose);
    await tester.pumpWidget(AnnouncementMonitor(
        service: service,
        onboarding: state,
        checkUpdates: () async {},
        updatePromptShown: () => false,
        child: GetMaterialApp(
            navigatorObservers: [PromptNavigationObserver()],
            home: const Scaffold(body: Text('主页面')))));
    await drain(tester);
    expect(adapter.bodyRequests, 1);
    Get.to(() => const Scaffold(body: Text('设置')), routeName: '/settings');
    await tester.pumpAndSettle();
    Get.to(() => OnboardingPage(state: state), routeName: '/onboarding');
    await tester.pumpAndSettle();
    adapter.pendingBody!.complete();
    await drain(tester);
    expect(find.text('知道了'), findsNothing);
    expect(service.pendingImportant, isNotNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(Get.currentRoute, '/settings');
    await drain(tester);
    expect(find.text('知道了'), findsNothing);
    Get.back();
    await drain(tester);
    expect(find.text('知道了'), findsOneWidget);
    expect(adapter.bodyRequests, 1);
    await tester.tap(find.text('知道了'));
    await drain(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('deferred update waits through login and verification routes',
      (tester) async {
    await tester.runAsync(state.skip);
    final adapter = ReleaseAdapter()..pending = Completer<void>();
    final service = UpdateService(
        preferences: UpdatePreferences(settings),
        dio: Dio()..httpClientAdapter = adapter,
        currentVersion: () async => '1.1.5');
    late BuildContext context;
    await tester.pumpWidget(GetMaterialApp(
        navigatorObservers: [PromptNavigationObserver()],
        home: Builder(builder: (value) {
          context = value;
          return const Scaffold(body: Text('主页面'));
        })));
    final checking = AppUpdates.check(context,
        automatic: true, updateService: service, onboarding: state);
    await drain(tester);
    Get.to(() => const Scaffold(body: Text('设置')), routeName: '/settings');
    await tester.pumpAndSettle();
    Get.to(() => OnboardingPage(state: state), routeName: '/onboarding');
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    Get.to(() => const Scaffold(body: Text('登录')), routeName: '/login');
    await tester.pumpAndSettle();
    adapter.pending!.complete();
    await drain(tester);
    expect(find.text('发现新版本'), findsNothing);
    Get.to(() => const Scaffold(body: Text('人机验证')), routeName: '/CaptchaPage');
    await tester.pumpAndSettle();
    await drain(tester);
    expect(find.text('发现新版本'), findsNothing);
    Get.back();
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsNothing);
    Get.back();
    await drain(tester);
    expect(Get.currentRoute, '/settings');
    expect(find.text('发现新版本'), findsOneWidget);
    expect(adapter.requests, hasLength(1));
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    await checking;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native links wait and interrupted batches keep their order',
      (tester) async {
    var pending = ['coolmarket://feed/1', 'coolmarket://feed/2'];
    var reads = 0;
    final opened = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      reads++;
      final result = pending;
      pending = [];
      return result;
    });
    final links = AndroidLinks(
        onboarding: state,
        onOpen: (link) {
          opened.add(link);
          if (opened.length == 1) state.begin();
        })
      ..listen();
    addTearDown(links.dispose);
    await tester.pumpWidget(const MaterialApp(home: Text('引导')));
    unawaited(links.ready());
    await drain(tester);
    expect(reads, 0);
    expect(pending, hasLength(2));
    await tester.runAsync(state.skip);
    await drain(tester);
    expect(opened, ['coolmarket://feed/1']);
    pending.add('coolmarket://feed/3');
    await notifyLinks(tester);
    expect(opened, ['coolmarket://feed/1']);
    expect(pending, ['coolmarket://feed/3']);
    state.end();
    await drain(tester);
    expect(opened,
        ['coolmarket://feed/1', 'coolmarket://feed/2', 'coolmarket://feed/3']);
    expect(pending, isEmpty);
  });

  for (final unmount in [false, true]) {
    testWidgets('in-flight update survives guide reopening; unmount=$unmount',
        (tester) async {
      await tester.runAsync(state.skip);
      final adapter = ReleaseAdapter()..pending = Completer<void>();
      final service = UpdateService(
          preferences: UpdatePreferences(settings),
          dio: Dio()..httpClientAdapter = adapter,
          currentVersion: () async => '1.1.5');
      late BuildContext context;
      await tester.pumpWidget(GetMaterialApp(
          navigatorObservers: [PromptNavigationObserver()],
          home: Builder(builder: (value) {
            context = value;
            return const Scaffold(body: Text('主页面'));
          })));
      final checking = AppUpdates.check(context,
          automatic: true, updateService: service, onboarding: state);
      await drain(tester);
      expect(adapter.requests, hasLength(1));
      Get.to(() => const Scaffold(body: Text('设置')), routeName: '/settings');
      await tester.pumpAndSettle();
      state.begin();
      Get.to(() => const Scaffold(body: Text('重新引导')),
          routeName: '/onboarding');
      await tester.pumpAndSettle();
      adapter.pending!.complete();
      await drain(tester);
      expect(find.text('发现新版本'), findsNothing);
      if (unmount) {
        await tester.pumpWidget(const SizedBox());
      } else {
        Get.back();
        await tester.pumpAndSettle();
        Get.dialog(const AlertDialog(title: Text('已有弹窗')));
        await tester.pumpAndSettle();
      }
      state.end();
      await drain(tester);
      if (!unmount) {
        expect(find.text('已有弹窗'), findsOneWidget);
        expect(find.text('发现新版本'), findsNothing);
        Get.back();
        await drain(tester);
      }
      expect(find.text('发现新版本'), unmount ? findsNothing : findsOneWidget);
      expect(adapter.requests, hasLength(1));
      if (!unmount) {
        await tester.tap(find.text('稍后'));
        await tester.pumpAndSettle();
      }
      await checking;
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
