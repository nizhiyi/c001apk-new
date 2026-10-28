import 'dart:io';

import 'package:c001apk_flutter/components/home_publish_action.dart';
import 'package:c001apk_flutter/pages/settings/settings_page.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('publish-action-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox('settings');
  });
  setUp(() => GStorage.settings.clear());
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets('theme preference hides both publish actions and persists',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const floatingKey = ValueKey('floating-publish');
    const railKey = ValueKey('rail-publish');
    const app = MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Row(children: [
            SizedBox(key: floatingKey, width: 80, child: HomePublishAction()),
            SizedBox(
                key: railKey,
                width: 80,
                child: HomePublishAction(extended: true)),
          ]),
          Expanded(
              child: SettingsDetailPage(section: SettingsSection.appearance)),
        ]),
      ),
    );
    final floating = find.descendant(
        of: find.byKey(floatingKey), matching: find.byTooltip('发布动态'));
    final rail = find.descendant(
        of: find.byKey(railKey), matching: find.byTooltip('发布动态'));

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(floating, findsNothing);
    expect(rail, findsNothing);

    Future<void> toggle() async {
      final setting = find.widgetWithText(ListTile, '不写东西');
      await tester.ensureVisible(setting);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(setting);
        await GStorage.settings.flush();
      });
      await tester.pumpAndSettle();
    }

    await toggle();
    expect(floating, findsOneWidget);
    expect(rail, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(floating, findsOneWidget);

    await tester
        .runAsync(() => GStorage.settings.put('floatingNavigation', false));
    await tester.pumpAndSettle();
    expect(floating, findsOneWidget);
    await toggle();
    expect(floating, findsNothing);
    expect(rail, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rail publish keeps its label within the control at large text',
      (tester) async {
    await tester.runAsync(() =>
        GStorage.settings.put(SettingsBoxKey.hideHomePublishButton, false));
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(3)),
      child: Scaffold(
          body: Center(
              child: SizedBox(
                  width: 80, child: HomePublishAction(extended: true)))),
    )));
    await tester.pumpAndSettle();
    final button = tester.getRect(find.byTooltip('发布动态'));
    final label = tester.getRect(find.text('发布'));
    final text = tester.renderObject<RenderParagraph>(find.text('发布'));
    expect(text.size.height,
        greaterThanOrEqualTo(text.getMaxIntrinsicHeight(text.size.width)));
    expect(label.top, greaterThanOrEqualTo(button.top));
    expect(label.bottom, lessThanOrEqualTo(button.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mounted appearance preference follows external onboarding saves',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    final setting = find.widgetWithText(ListTile, '不写东西');
    final switchFinder =
        find.descendant(of: setting, matching: find.byType(Switch));
    await tester.ensureVisible(setting);
    await tester.pumpAndSettle();
    final mountedPage = tester.state(find.byType(SettingsDetailPage));
    expect(tester.widget<Switch>(switchFinder).value, isTrue);

    // Onboarding writes the existing preference while this settings route
    // remains mounted underneath it. Returning must reveal the saved value.
    await tester.runAsync(() async {
      await GStorage.settings.putAll({
        SettingsBoxKey.hideHomePublishButton: false,
        SettingsBoxKey.floatingNavigation: false,
      });
      await GStorage.settings.flush();
    });
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(SettingsDetailPage)), same(mountedPage));
    expect(tester.widget<Switch>(switchFinder).value, isFalse);

    // Re-enabling from the retained row also uses the latest saved value.
    await tester.runAsync(() async {
      await tester.tap(setting);
      await GStorage.settings.flush();
    });
    await tester.pumpAndSettle();
    expect(GStorage.hideHomePublishButton, isTrue);
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
