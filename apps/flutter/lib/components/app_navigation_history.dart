import 'package:flutter/material.dart';

class ReadingHistoryClient {
  const ReadingHistoryClient({
    required this.canGoForward,
    required this.goForward,
    required this.discardForward,
    required this.reset,
    required this.save,
    required this.restore,
    required this.cancelRestore,
  });
  final bool Function() canGoForward;
  final VoidCallback goForward;
  final VoidCallback discardForward;
  final VoidCallback reset;
  final Object Function() save;
  final void Function(Object snapshot) restore;
  final VoidCallback cancelRestore;
}

class _ForwardRoute {
  const _ForwardRoute(
      this.origin, this.route, this.settings, this.offsets, this.reader);
  final Route<dynamic> origin;
  final Route<dynamic> route;
  final RouteSettings settings;
  final List<double> offsets;
  final Object? reader;
}

/// Transient navigation history. Dialogs and write flows are never replayed.
class AppNavigationHistory extends NavigatorObserver {
  AppNavigationHistory({this.isReplayable});
  final bool Function(String name)? isReplayable;
  final _routes = <Route<dynamic>>[];
  final _forward = <_ForwardRoute>[];
  final _readers = <Route<dynamic>, ReadingHistoryClient>{};
  final _restoring = <Route<dynamic>, List<double>>{};
  final _readerSnapshots = <Route<dynamic>, Object>{};
  _ForwardRoute? _replaying;
  bool _restoreScheduled = false;
  bool _clearing = false;
  bool _forwarding = false;
  int _generation = 0;

  void register(Route<dynamic> route, ReadingHistoryClient client) {
    _readers[route] = client;
    final snapshot = _readerSnapshots.remove(route);
    if (snapshot != null) client.restore(snapshot);
  }

  void unregister(Route<dynamic> route, ReadingHistoryClient client) {
    if (identical(_readers[route], client)) _readers.remove(route);
  }

  void discardForward() => _forward.clear();

  void clear() {
    _clearing = true;
    final generation = ++_generation;
    _forward.clear();
    _restoring.clear();
    _readerSnapshots.clear();
    for (final client in _readers.values.toList()) {
      client.reset();
    }
    // Account cleanup pops routes in post-frame callbacks. Record nothing
    // until all of those callbacks have finished.
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (_generation == generation) _clearing = false;
    });
  }

  void cancelRouteRestore() => _restoring.clear();

  void cancelRestore() {
    cancelRouteRestore();
    if (_routes.isNotEmpty) _readers[_routes.last]?.cancelRestore();
  }

  Future<void> forward() async {
    if (_routes.isEmpty || _forwarding) return;
    final current = _routes.last;
    if (current is! PageRoute || !current.isCurrent) return;
    final reader = _readers[current];
    if (reader?.canGoForward() == true) {
      reader!.goForward();
      return;
    }
    if (_forward.isEmpty || !identical(_forward.last.origin, current)) return;
    final entry = _forward.last;
    final generation = _generation;
    _forwarding = true;
    try {
      // A popped route can still own Get controllers during its animation.
      // Recreating it early would reuse state that its old instance disposes.
      if (entry.route is TransitionRoute) {
        await (entry.route as TransitionRoute).completed;
      }
      if (_generation != generation ||
          _forward.isEmpty ||
          !identical(_forward.last, entry) ||
          _routes.isEmpty ||
          !identical(_routes.last, current)) {
        return;
      }
      _forward.removeLast();
      _replaying = entry;
      navigator?.pushNamed(entry.settings.name!,
          arguments: entry.settings.arguments);
    } finally {
      _replaying = null;
      _forwarding = false;
    }
  }

  static List<ScrollPosition> scrollPositions(BuildContext root,
      {bool skipOffstage = true}) {
    final positions = <ScrollPosition>[];
    void visit(Element element) {
      if (skipOffstage &&
          element.widget is Offstage &&
          (element.widget as Offstage).offstage) {
        return;
      }
      if (element is StatefulElement && element.state is ScrollableState) {
        positions.add((element.state as ScrollableState).position);
      }
      element.visitChildren(visit);
    }

    root.visitChildElements(visit);
    return positions;
  }

  List<ScrollPosition> _positions(Route<dynamic> route) =>
      route is ModalRoute && route.subtreeContext != null
          ? scrollPositions(route.subtreeContext!)
          : [];

  void restorePending() {
    if (_restoring.isEmpty || _restoreScheduled) return;
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScheduled = false;
      for (final route in _restoring.keys.toList()) {
        final offsets = _restoring[route]!;
        final positions = _positions(route);
        var done = positions.length >= offsets.length;
        for (var i = 0; i < positions.length && i < offsets.length; i++) {
          final position = positions[i];
          if (!position.hasContentDimensions) {
            done = false;
            continue;
          }
          if (position.maxScrollExtent < offsets[i]) done = false;
          // Reach the available end so lazy pagination can load more content.
          position.jumpTo(offsets[i]
              .clamp(position.minScrollExtent, position.maxScrollExtent));
        }
        if (done) _restoring.remove(route);
      }
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    if (_replaying != null) {
      // Forward creates a fresh route. Later entries must point to that new
      // instance rather than to the disposed route they originally followed.
      for (var i = 0; i < _forward.length; i++) {
        final entry = _forward[i];
        if (identical(entry.origin, _replaying!.route)) {
          _forward[i] = _ForwardRoute(
              route, entry.route, entry.settings, entry.offsets, entry.reader);
        }
      }
      _restoring[route] = _replaying!.offsets;
      if (_replaying!.reader != null) {
        _readerSnapshots[route] = _replaying!.reader!;
      }
      restorePending();
    } else if (route is PageRoute) {
      _forward.clear();
      _readers[previousRoute]?.discardForward();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (!_clearing &&
        route is PageRoute &&
        previousRoute != null &&
        name != null &&
        (isReplayable?.call(name) ?? true)) {
      _forward.add(_ForwardRoute(
          previousRoute,
          route,
          route.settings,
          _positions(route).map((p) => p.pixels).toList(),
          _readers[route]?.save()));
      if (_forward.length > 20) _forward.removeAt(0);
    }
    _routes.remove(route);
    _restoring.remove(route);
    _readerSnapshots.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _restoring.remove(route);
    _readerSnapshots.remove(route);
    _forward.clear();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = _routes.indexOf(oldRoute!);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _restoring.remove(oldRoute);
    _readerSnapshots.remove(oldRoute);
    _forward.clear();
  }
}

class AppNavigationHistoryScope extends InheritedWidget {
  const AppNavigationHistoryScope(
      {super.key, required this.history, required super.child});
  final AppNavigationHistory? history;
  static AppNavigationHistory? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppNavigationHistoryScope>()
      ?.history;
  @override
  bool updateShouldNotify(AppNavigationHistoryScope oldWidget) =>
      oldWidget.history != history;
}
