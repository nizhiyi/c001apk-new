import 'dart:io';

import 'package:c001apk_flutter/logic/content_filter/content_filter_rule.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_service.dart';
import 'package:c001apk_flutter/logic/onboarding/onboarding_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class OfflineFilter extends ContentFilterService {
  OfflineFilter(super.box);
  int updates = 0;
  @override
  Future<void> checkForUpdates({bool force = false}) async {
    updates++;
  }
}

class FailingMarkerBox implements Box<dynamic> {
  FailingMarkerBox(this.base);
  final Box<dynamic> base;
  bool fail = true;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      base.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (fail && key == OnboardingState.completedKey) {
      throw StateError('synthetic disk failure');
    }
    await base.put(key, value);
  }

  @override
  Future<void> putAll(Map<dynamic, dynamic> values) => base.putAll(values);
  @override
  Future<void> flush() => base.flush();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late Box<dynamic> settings, rules;
  late OfflineFilter filter;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('onboarding-state-');
    Hive.init(directory.path);
    settings = await Hive.openBox('settings');
    rules = await Hive.openBox('rules');
  });
  tearDown(() async {
    filter.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  OnboardingState state({Box<dynamic>? box}) {
    filter = OfflineFilter(rules);
    return OnboardingState(settings: box ?? settings, filter: filter);
  }

  test('skip marks seen once while leaving every preference untouched',
      () async {
    await settings.putAll({
      'token': 'synthetic',
      'floatingNavigation': true,
      'liquidGlass': false
    });
    final current = state();
    expect(current.completed, false);
    final draft = current.createDraft()
      ..hidePublish = false
      ..filterEnabled = true;
    expect(draft.appearance, OnboardingAppearance.custom);
    expect(settings.containsKey('hideHomePublishButton'), false);
    await current.skip();
    expect(current.completed, true);
    expect(current.active, false);
    expect(settings.get('token'), 'synthetic');
    expect(settings.containsKey('hideHomePublishButton'), false);
    expect(filter.enabled, false);
    expect(filter.updates, 0);
    current.begin();
    expect(current.active, true);
    current.end();
    expect(current.completed, true);
  });
  test('finish preserves old custom appearance strict level and list choices',
      () async {
    await settings.putAll({
      'floatingNavigation': true,
      'liquidGlass': false,
      'liquidGlassLevel': 'high'
    });
    await rules.putAll({
      'enabled': false,
      'level': 'strict',
      'disabledListKinds': ['author'],
      'allowedAuthorUids': ['synthetic']
    });
    final current = state();
    final draft = current.createDraft()..filterEnabled = true;
    expect(draft.filterLevel, FilterLevel.strict);
    await current.finish(draft);
    expect(settings.get('floatingNavigation'), true);
    expect(settings.get('liquidGlass'), false);
    expect(settings.get('liquidGlassLevel'), 'high');
    expect(filter.enabled, true);
    expect(filter.level, FilterLevel.strict);
    expect(filter.isListEnabled(FilterRuleKind.author), false);
    expect(filter.allowedAuthorUids, contains('synthetic'));
    expect(filter.updates, 1);
  });
  test('explicit appearance presets change only their owned preferences',
      () async {
    await settings.putAll(
        {'floatingNavigation': true, 'liquidGlass': true, 'fontScale': 1.3});
    final current = state();
    await current.finish(current.createDraft()
      ..appearance = OnboardingAppearance.m3e
      ..hidePublish = false);
    expect(settings.get('floatingNavigation'), false);
    expect(settings.get('liquidGlass'), true);
    expect(settings.get('fontScale'), 1.3);
    expect(settings.get('hideHomePublishButton'), false);
    current.begin();
    await current
        .finish(current.createDraft()..appearance = OnboardingAppearance.glass);
    expect(settings.get('floatingNavigation'), true);
    expect(settings.get('liquidGlass'), true);
  });
  test('failed completed marker keeps gate active and permits idempotent retry',
      () async {
    final box = FailingMarkerBox(settings);
    final current = state(box: box);
    final draft = current.createDraft()..hidePublish = false;
    await expectLater(current.finish(draft), throwsStateError);
    expect(current.completed, false);
    expect(current.active, true);
    expect(settings.get('hideHomePublishButton'), false);
    box.fail = false;
    await current.finish(draft);
    expect(current.completed, true);
    expect(current.active, false);
  });
  test('inactive waiter waits through reopening and is released only at end',
      () async {
    final current = state();
    var ready = false;
    final waiter = current.waitUntilInactive().then((_) => ready = true);
    await Future<void>.delayed(Duration.zero);
    expect(ready, false);
    await current.skip();
    await waiter;
    expect(ready, true);
  });

  test('after partial save user can revert to original choices and retry',
      () async {
    final box = FailingMarkerBox(settings);
    final current = state(box: box);
    final draft = current.createDraft()
      ..hidePublish = false
      ..appearance = OnboardingAppearance.m3e
      ..filterEnabled = true
      ..filterLevel = FilterLevel.strict;
    await expectLater(current.finish(draft), throwsStateError);
    expect(settings.get('hideHomePublishButton'), false);
    expect(filter.enabled, true);
    draft
      ..hidePublish = true
      ..appearance = OnboardingAppearance.glass
      ..filterEnabled = false
      ..filterLevel = FilterLevel.standard;
    box.fail = false;
    await current.finish(draft);
    expect(settings.get('hideHomePublishButton'), true);
    expect(settings.get('floatingNavigation'), true);
    expect(settings.get('liquidGlass'), true);
    expect(filter.enabled, false);
    expect(filter.level, FilterLevel.standard);
    expect(current.completed, true);
  });
}
