import 'dart:async';

import 'package:flutter/widgets.dart';

class _NavigationChanges extends ChangeNotifier {
  void changed() => notifyListeners();
}

/// Wakes deferred prompts after navigation has updated its current route.
/// Waiting prompts subscribe to events; they never poll or keep frames alive.
class PromptNavigation {
  static final _changes = _NavigationChanges();
  static Listenable get changes => _changes;
  static bool _scheduled = false;

  static void _changed() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _changes.changed();
    });
  }

  static Future<void> waitUntil(bool Function() ready,
      {Listenable? alsoListenTo}) {
    if (ready()) return Future.value();
    final completer = Completer<void>();
    void changed() {
      if (!ready()) return;
      _changes.removeListener(changed);
      alsoListenTo?.removeListener(changed);
      completer.complete();
    }

    _changes.addListener(changed);
    alsoListenTo?.addListener(changed);
    return completer.future;
  }
}

class PromptNavigationObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      PromptNavigation._changed();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      PromptNavigation._changed();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      PromptNavigation._changed();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      PromptNavigation._changed();
}
