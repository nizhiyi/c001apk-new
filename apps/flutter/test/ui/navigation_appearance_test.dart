import 'dart:io';

import 'package:c001apk_flutter/components/settings/navigation_appearance_settings.dart';
import 'package:c001apk_flutter/constants/liquid_glass_level.dart';
import 'package:c001apk_flutter/pages/settings/settings_page.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:get/get.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('navigation-appearance-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox('settings');
  });
  setUp(() => GStorage.settings.clear());
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester,
          {TargetPlatform platform = TargetPlatform.android,
          double scale = 1}) =>
      tester.pumpWidget(MaterialApp(
          theme: ThemeData(platform: platform),
          home: Builder(
              builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                      body: ListView(children: const [
                    NavigationAppearanceSettings(),
                  ]))))));

  testWidgets(
      'floating switch disables glass control but preserves its preference',
      (tester) async {
    Future<void> tap(String label) async {
      await tester.runAsync(() async {
        await tester.tap(find.text(label));
        await GStorage.settings.flush();
      });
      await tester.pumpAndSettle();
    }

    await mount(tester);
    expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '液态玻璃'))
            .value,
        isTrue);
    await tap('悬浮控件');
    expect(GStorage.floatingNavigation, isFalse);
    expect(GStorage.liquidGlass, isTrue);
    expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '液态玻璃'))
            .onChanged,
        isNull);
    await tap('悬浮控件');
    await tap('液态玻璃');
    expect(GStorage.liquidGlass, isFalse);
    await tester.pumpWidget(const SizedBox());
    await mount(tester);
    expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '液态玻璃'))
            .value,
        isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop exposes the same glass preferences', (tester) async {
    await mount(tester, platform: TargetPlatform.windows);
    expect(find.widgetWithText(SwitchListTile, '液态玻璃'), findsOneWidget);
    expect(find.text('中档'), findsOneWidget);
  });

  testWidgets(
      'desktop appearance page actually includes working glass controls',
      (tester) async {
    addTearDown(Get.reset);
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: const SettingsPage(),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationAppearanceSettings), findsOneWidget);
    final control = find.widgetWithText(SwitchListTile, '液态玻璃');
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(control));
    await tester.pumpAndSettle();
    expect(GStorage.liquidGlass, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('glass level defaults to medium and survives a settings reopen',
      (tester) async {
    await mount(tester);
    expect(find.text('中档'), findsOneWidget);
    // Open the route on the real I/O clock too: its completion delivers the
    // selection and starts the Hive write after the dropdown is dismissed.
    await tester.runAsync(() => tester.tap(find.text('中档')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('低档').last));
    await tester.pumpAndSettle();
    await tester.runAsync(() => GStorage.settings.flush());
    expect(GStorage.settings.get('liquidGlassLevel'), 'minimal');
    await tester.pumpWidget(const SizedBox());
    await mount(tester);
    expect(find.text('低档'), findsOneWidget);
    expect(find.text('中档'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabled effects preserve the selected glass level',
      (tester) async {
    await tester
        .runAsync(() => GStorage.settings.put('liquidGlassLevel', 'minimal'));
    for (final disabledKey in ['floatingNavigation', 'liquidGlass']) {
      await tester.runAsync(() => GStorage.settings.put(disabledKey, false));
      await mount(tester);
      final picker = tester.widget<DropdownButton>(
          find.byWidgetPredicate((widget) => widget is DropdownButton));
      expect(picker.onChanged, isNull);
      expect(find.text('低档'), findsOneWidget);
      expect(GStorage.settings.get('liquidGlassLevel'), 'minimal');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => GStorage.settings.put(disabledKey, true));
    }
  });

  testWidgets('unknown stored glass level uses the current medium appearance',
      (tester) async {
    await tester.runAsync(
        () => GStorage.settings.put('liquidGlassLevel', 'future-or-invalid'));
    await mount(tester);
    expect(find.text('中档'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('high glass level is saved and restored', (tester) async {
    await mount(tester);
    await tester.runAsync(() => tester.tap(find.text('中档')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('高档').last));
    await tester.pumpAndSettle();
    await tester.runAsync(() => GStorage.settings.flush());
    expect(GStorage.settings.get('liquidGlassLevel'), 'medium');
    await tester.pumpWidget(const SizedBox());
    await mount(tester);
    expect(find.text('高档'), findsOneWidget);
    expect(GStorage.liquidGlassLevel, LiquidGlassLevel.high);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('glass level menu fits a narrow screen with three times text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await mount(tester, scale: 3);
    await tester.ensureVisible(find.text('中档'));
    await tester.pumpAndSettle();
    final label = tester.renderObject<RenderParagraph>(find.text('中档'));
    expect(label.size.height,
        greaterThanOrEqualTo(label.getMaxIntrinsicHeight(label.size.width)));
    await tester.runAsync(() => tester.tap(find.text('中档')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final low = tester.renderObject<RenderParagraph>(find.text('低档').last);
    expect(low.size.height,
        greaterThanOrEqualTo(low.getMaxIntrinsicHeight(low.size.width)));
    final high = tester.renderObject<RenderParagraph>(find.text('高档').last);
    expect(high.size.height,
        greaterThanOrEqualTo(high.getMaxIntrinsicHeight(high.size.width)));
    expect(find.text('完全').last, findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('低档').last));
    await tester.pumpAndSettle();
    await tester.runAsync(() => GStorage.settings.flush());
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('old stored levels retain their effect under the new labels',
      (tester) async {
    for (final entry in {'low': '中档', 'medium': '高档', 'high': '完全'}.entries) {
      await tester
          .runAsync(() => GStorage.settings.put('liquidGlassLevel', entry.key));
      await mount(tester);
      expect(find.text(entry.value), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
    await mount(tester);
    await tester.runAsync(() => tester.tap(find.text('完全')));
    await tester.pumpAndSettle();
    expect(find.text('低档').last, findsOneWidget);
    expect(find.text('中档').last, findsOneWidget);
    expect(find.text('高档').last, findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('完全').last));
    await tester.pumpAndSettle();
    await tester.runAsync(() => GStorage.settings.flush());
    expect(GStorage.settings.get('liquidGlassLevel'), 'high');
    await tester.pumpWidget(const SizedBox());
    await mount(tester);
    expect(find.text('完全'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('level accessibility action stays within its own settings row',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    final picker = find.byWidgetPredicate((widget) => widget is DropdownButton);
    final row = find.widgetWithText(ListTile, '液态玻璃档位');
    expect(tester.getSemantics(picker).rect.height,
        lessThanOrEqualTo(tester.getSize(row).height));
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });
}
