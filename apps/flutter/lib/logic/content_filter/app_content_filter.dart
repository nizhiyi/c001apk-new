import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';

import 'content_filter_service.dart';

class AppContentFilter with WidgetsBindingObserver {
  AppContentFilter._();
  static ContentFilterService? service;
  static final _observer = AppContentFilter._();
  static Future<void>? _initializing;

  static Future<void> init() => _initializing ??= _initialize();

  static Future<void> _initialize() async {
    final box = await Hive.openBox<dynamic>('contentFilter');
    service ??= ContentFilterService(box);
    WidgetsBinding.instance.addObserver(_observer);
    unawaited(service!.checkForUpdates());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final current = service;
      if (current != null) unawaited(current.checkForUpdates());
    }
  }
}
