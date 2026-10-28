import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../utils/storage_util.dart';
import '../content_filter/content_filter_rule.dart';
import '../content_filter/content_filter_service.dart';

enum OnboardingAppearance { m3e, glass, custom }

/// An in-memory draft. Merely opening or previewing onboarding writes nothing.
class OnboardingDraft {
  OnboardingDraft._(this._hidePublish, this._appearance, this._filterEnabled,
      this._filterLevel);
  bool _hidePublish, _filterEnabled;
  OnboardingAppearance _appearance;
  FilterLevel _filterLevel;
  bool _hidePublishChanged = false, _appearanceChanged = false;
  bool _filterEnabledChanged = false, _filterLevelChanged = false;

  // Keep explicit edits even when reverting after a partially successful save.
  // Fields the user never touched must retain their existing values.
  bool get hidePublish => _hidePublish;
  set hidePublish(bool value) {
    _hidePublishChanged |= value != _hidePublish;
    _hidePublish = value;
  }

  OnboardingAppearance get appearance => _appearance;
  set appearance(OnboardingAppearance value) {
    _appearanceChanged |= value != _appearance;
    _appearance = value;
  }

  bool get filterEnabled => _filterEnabled;
  set filterEnabled(bool value) {
    _filterEnabledChanged |= value != _filterEnabled;
    _filterEnabled = value;
  }

  FilterLevel get filterLevel => _filterLevel;
  set filterLevel(FilterLevel value) {
    _filterLevelChanged |= value != _filterLevel;
    _filterLevel = value;
  }
}

class OnboardingState extends ChangeNotifier {
  OnboardingState({required this.settings, required this.filter})
      : _completed = settings.get(completedKey) == true,
        _active = settings.get(completedKey) != true;

  static OnboardingState? current;
  static const completedKey = 'onboardingCompleted';
  final Box<dynamic> settings;
  final ContentFilterService filter;
  bool _completed, _active;
  Future<void>? _saving;
  bool get completed => _completed;
  bool get active => _active;

  void begin() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  void end() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }

  Future<void> waitUntilInactive() {
    if (!active) return Future.value();
    final completer = Completer<void>();
    void changed() {
      if (active) return;
      removeListener(changed);
      completer.complete();
    }

    addListener(changed);
    return completer.future;
  }

  OnboardingDraft createDraft() {
    final floating =
        settings.get(SettingsBoxKey.floatingNavigation, defaultValue: true) ==
            true;
    final glass =
        settings.get(SettingsBoxKey.liquidGlass, defaultValue: true) == true;
    return OnboardingDraft._(
        settings.get(SettingsBoxKey.hideHomePublishButton,
                defaultValue: true) ==
            true,
        !floating
            ? OnboardingAppearance.m3e
            : glass
                ? OnboardingAppearance.glass
                : OnboardingAppearance.custom,
        filter.enabled,
        filter.level);
  }

  Future<void> finish(OnboardingDraft draft) => _saveOnce(draft);
  Future<void> skip() => _saveOnce(null);

  Future<void> _saveOnce(OnboardingDraft? draft) {
    final running = _saving;
    if (running != null) return running;
    late final Future<void> operation;
    operation = _save(draft).whenComplete(() {
      if (identical(_saving, operation)) _saving = null;
    });
    _saving = operation;
    return operation;
  }

  Future<void> _save(OnboardingDraft? draft) async {
    if (draft != null) {
      final changes = <String, dynamic>{};
      if (draft._hidePublishChanged) {
        changes[SettingsBoxKey.hideHomePublishButton] = draft.hidePublish;
      }
      if (draft._appearanceChanged) {
        switch (draft.appearance) {
          case OnboardingAppearance.m3e:
            changes[SettingsBoxKey.floatingNavigation] = false;
          case OnboardingAppearance.glass:
            changes[SettingsBoxKey.floatingNavigation] = true;
            changes[SettingsBoxKey.liquidGlass] = true;
          case OnboardingAppearance.custom:
            changes[SettingsBoxKey.floatingNavigation] = true;
            changes[SettingsBoxKey.liquidGlass] = false;
        }
      }
      if (changes.isNotEmpty) {
        await settings.putAll(changes);
        await settings.flush();
      }
      await filter.applyPreferences(
          enabled: draft._filterEnabledChanged ? draft.filterEnabled : null,
          level: draft._filterLevelChanged ? draft.filterLevel : null);
    }
    // The marker is deliberately last: partial saves can be retried without
    // deleting existing values, and failure cannot release the startup gate.
    await settings.put(completedKey, true);
    await settings.flush();
    _completed = true;
    _active = false;
    notifyListeners();
  }
}
