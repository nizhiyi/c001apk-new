import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../logic/announcements/announcement_service.dart';
import '../logic/onboarding/onboarding_state.dart';
import 'announcement_dialog.dart';
import 'onboarding_gate.dart';
import 'prompt_navigation.dart';
import 'update_check_tile.dart';

/// One automatic prompt per process, with version updates taking priority.
class AnnouncementMonitor extends StatefulWidget {
  const AnnouncementMonitor(
      {super.key,
      required this.service,
      required this.child,
      this.checkUpdates,
      this.onboarding,
      this.clock,
      this.updatePromptShown});
  final AnnouncementService service;
  final Widget child;
  final Future<void> Function()? checkUpdates;
  final OnboardingState? onboarding;
  final bool Function()? updatePromptShown;
  final DateTime Function()? clock;
  @override
  State<AnnouncementMonitor> createState() => _AnnouncementMonitorState();
}

class _AnnouncementMonitorState extends State<AnnouncementMonitor>
    with WidgetsBindingObserver {
  bool _foreground = true, _prompting = false, _shown = false;
  DateTime? _lastBodyAttempt;
  String? _lastBodyKey;
  late final OnboardingState? _onboarding;
  bool _startupFinished = false;

  @override
  void initState() {
    super.initState();
    _onboarding = widget.onboarding ?? OnboardingState.current;
    _onboarding?.addListener(_onboardingChanged);
    PromptNavigation.changes.addListener(_navigationChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_startup()));
  }

  Future<void> _startup() async {
    await waitForOnboardingNavigation(_onboarding);
    if (!mounted) return;
    final index = widget.service.sync(SyncReason.coldStart);
    try {
      if (widget.checkUpdates != null) {
        await widget.checkUpdates!();
      } else {
        final context = Get.context;
        if (context != null && context.mounted) {
          await AppUpdates.check(context,
              automatic: true, onboarding: _onboarding);
        }
      }
      await index;
    } catch (_) {
      // Automatic checks never interrupt launch with diagnostic errors.
    } finally {
      _startupFinished = true;
    }
    if (mounted) await _maybePrompt();
  }

  void _onboardingChanged() {
    if (_onboarding?.active == false && _startupFinished) {
      unawaited(_afterOnboarding());
    }
  }

  void _navigationChanged() {
    if (_startupFinished && _onboarding?.active != true) {
      unawaited(_afterOnboarding());
    }
  }

  Future<void> _afterOnboarding() async {
    await waitForOnboardingNavigation(_onboarding);
    if (mounted) await _maybePrompt();
  }

  BuildContext? _safeContext() {
    if (!mounted ||
        !_foreground ||
        _onboarding?.active == true ||
        _shown ||
        !widget.service.automaticEnabled ||
        (widget.updatePromptShown?.call() ?? AppUpdates.hasShownDialog) ||
        AppUpdates.isActive ||
        Get.currentRoute != '/' ||
        Get.isDialogOpen == true ||
        Get.isBottomSheetOpen == true) {
      return null;
    }
    final context = Get.context;
    if (context == null || !context.mounted || Navigator.of(context).canPop()) {
      return null;
    }
    return context;
  }

  Future<void> _maybePrompt() async {
    if (_prompting || _safeContext() == null) return;
    final item = widget.service.pendingImportant;
    if (item == null) return;
    final now = widget.clock?.call() ?? DateTime.now();
    final bodyKey = '${item.cacheKey}:${item.reminderRevision}';
    if (_lastBodyKey == bodyKey &&
        _lastBodyAttempt != null &&
        now.difference(_lastBodyAttempt!) < const Duration(minutes: 1)) {
      return;
    }
    _lastBodyKey = bodyKey;
    _lastBodyAttempt = now;
    _prompting = true;
    try {
      final body = await widget.service.loadBody(item);
      // A successful download may be deferred by navigation. Only failed body
      // loads need backoff; returning home can use this cached body immediately.
      _lastBodyKey = null;
      _lastBodyAttempt = null;
      // Keep the downloaded body and the unconsumed prompt through a reopened
      // guide. The existing retry backoff applies only to actual load failures.
      await waitForOnboardingNavigation(_onboarding);
      final context = _safeContext();
      final pending = widget.service.pendingImportant;
      if (context == null ||
          !context.mounted ||
          !widget.service.isCurrent(item) ||
          pending?.cacheKey != item.cacheKey ||
          pending?.reminderRevision != item.reminderRevision) {
        return;
      }
      _shown = true;
      await showAnnouncement(context, widget.service, item,
          automatic: true, loadedBody: body);
    } catch (_) {
      // Keep unread/prompt receipts unchanged on a failed or obsolete body.
    } finally {
      _prompting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_resume());
  }

  Future<void> _resume() async {
    await waitForOnboardingNavigation(_onboarding);
    if (!mounted || !_startupFinished) return;
    await widget.service.sync(SyncReason.resume);
    if (mounted) await _maybePrompt();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _onboarding?.removeListener(_onboardingChanged);
    PromptNavigation.changes.removeListener(_navigationChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AnnouncementAutoCheckTile extends StatelessWidget {
  const AnnouncementAutoCheckTile({super.key, required this.service});
  final AnnouncementService service;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: service,
      builder: (context, _) => SwitchListTile(
          secondary: const Icon(Icons.campaign_outlined),
          title: const Text('自动检查公告'),
          subtitle: const Text('普通公告进入小助手，重要公告首次弹窗提醒'),
          value: service.automaticEnabled,
          onChanged: (value) async {
            try {
              await service.setAutomaticEnabled(value);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('公告设置保存失败，请稍后重试')));
              }
            }
          }));
}
