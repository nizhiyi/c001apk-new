import 'package:flutter/material.dart';

import 'feed_navigation.dart';
import 'keyboard_scroll_region.dart';
import 'app_navigation_history.dart';

enum ReadingMode { automatic, enabled, disabled }

class _ReadingSnapshot {
  const _ReadingSnapshot(
      this.trail, this.cursor, this.sidebarVisible, this.offsets);
  final List<String> trail;
  final int cursor;
  final bool sidebarVisible;
  final Map<String, List<double>> offsets;
}

/// Keeps the original page mounted while a detail is read beside it. The same
/// detail becomes full width when the window can no longer fit both panes.
class AdaptiveReadingPane extends StatefulWidget {
  const AdaptiveReadingPane(
      {super.key,
      required this.child,
      required this.detailBuilder,
      this.leadingInset = 0,
      this.mode = ReadingMode.automatic});

  final Widget child;
  final ReadingMode mode;
  final double leadingInset;
  final Widget Function(BuildContext, String, VoidCallback) detailBuilder;

  @override
  State<AdaptiveReadingPane> createState() => AdaptiveReadingPaneState();
}

class AdaptiveReadingPaneState extends State<AdaptiveReadingPane> {
  String? _selectedId;
  LocalHistoryEntry? _history;
  bool _disposing = false;
  bool _canSplit = false;
  bool _sidebarVisible = true;
  final _trail = <String>[];
  final _details = <String, Widget>{};
  final _detailKeys = <String, GlobalKey>{};
  final _savedOffsets = <String, List<double>>{};
  final _scheduledRestores = <String>{};
  int _cursor = -1;
  AppNavigationHistory? _navigationHistory;
  ModalRoute<dynamic>? _route;
  late final _historyClient = ReadingHistoryClient(
    canGoForward: () => _cursor + 1 < _trail.length,
    goForward: _forward,
    discardForward: _discardForward,
    reset: reset,
    save: _save,
    restore: _restore,
    cancelRestore: () => _savedOffsets.remove(_selectedId),
  );

  Object _save() {
    final offsets = Map<String, List<double>>.from(_savedOffsets);
    for (final entry in _detailKeys.entries) {
      final context = entry.value.currentContext;
      if (context != null && !offsets.containsKey(entry.key)) {
        offsets[entry.key] =
            AppNavigationHistory.scrollPositions(context, skipOffstage: false)
                .map((p) => p.pixels)
                .toList();
      }
    }
    return _ReadingSnapshot(List.of(_trail), _cursor, _sidebarVisible, offsets);
  }

  void _restore(Object value) {
    if (value is! _ReadingSnapshot) return;
    _trail.addAll(value.trail);
    _cursor = value.cursor;
    _sidebarVisible = value.sidebarVisible;
    _savedOffsets.addAll(value.offsets);
    _selectedId = _cursor >= 0 ? _trail[_cursor] : null;
    if (_selectedId != null) _ensureDetail(_selectedId!);
    _ensureHistory();
  }

  void _ensureDetail(String id) {
    _details.putIfAbsent(id, () => widget.detailBuilder(context, id, close));
    _restoreDetail(id);
  }

  void _restoreDetail(String id) {
    if (!_savedOffsets.containsKey(id) || !_scheduledRestores.add(id)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduledRestores.remove(id);
      if (!mounted) return;
      final context = _detailKeys[id]?.currentContext;
      final offsets = _savedOffsets[id];
      if (context == null || offsets == null) return;
      final positions =
          AppNavigationHistory.scrollPositions(context, skipOffstage: false);
      var done = positions.length >= offsets.length;
      for (var i = 0; i < positions.length && i < offsets.length; i++) {
        final position = positions[i];
        if (!position.hasContentDimensions) {
          done = false;
          continue;
        }
        if (position.maxScrollExtent < offsets[i]) done = false;
        position.jumpTo(offsets[i]
            .clamp(position.minScrollExtent, position.maxScrollExtent));
      }
      if (done) _savedOffsets.remove(id);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final history = AppNavigationHistoryScope.maybeOf(context);
    final route = ModalRoute.of(context);
    if (_route != null) _navigationHistory?.unregister(_route!, _historyClient);
    _navigationHistory = history;
    _route = route;
    if (route != null) history?.register(route, _historyClient);
  }

  void _discardForward() {
    if (_cursor + 1 < _trail.length) {
      setState(() {
        _trail.removeRange(_cursor + 1, _trail.length);
        _details.removeWhere((id, _) => !_trail.contains(id));
        _detailKeys.removeWhere((id, _) => !_trail.contains(id));
        _savedOffsets.removeWhere((id, _) => !_trail.contains(id));
      });
    }
  }

  void _forward() {
    if (_cursor + 1 >= _trail.length) return;
    _navigationHistory?.cancelRouteRestore();
    setState(() => _selectedId = _trail[++_cursor]);
    _ensureDetail(_selectedId!);
    _ensureHistory();
  }

  void _ensureHistory() {
    if (_history != null || _route == null || _cursor < 0) return;
    _history = LocalHistoryEntry(onRemove: () {
      _history = null;
      if (!_disposing && mounted) {
        setState(() {
          _cursor--;
          _selectedId = _cursor >= 0 ? _trail[_cursor] : null;
          if (_selectedId != null) _ensureDetail(_selectedId!);
        });
        // LocalHistoryRoute finishes its dismissal bookkeeping after this
        // callback. Re-adding synchronously corrupts that bookkeeping.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_disposing) _ensureHistory();
        });
      }
    });
    _route!.addLocalHistoryEntry(_history!);
  }

  bool _open(String id) {
    if (!_canSplit || ModalRoute.of(context)?.isCurrent != true) return false;
    if (_selectedId == id) return true;
    _navigationHistory?.cancelRestore();
    _navigationHistory?.discardForward();
    _discardForward();
    setState(() {
      _trail.add(id);
      if (_trail.length > 8) _trail.removeAt(0);
      _cursor = _trail.length - 1;
      _selectedId = id;
      _details.removeWhere((id, _) => !_trail.contains(id));
      _detailKeys.removeWhere((id, _) => !_trail.contains(id));
      _savedOffsets.removeWhere((id, _) => !_trail.contains(id));
      _ensureDetail(id);
    });
    _ensureHistory();
    return true;
  }

  void close() => _history?.remove();

  void reset() {
    _disposing = true;
    _history?.remove();
    _disposing = false;
    if (!mounted) return;
    setState(() {
      _history = null;
      _cursor = -1;
      _selectedId = null;
      _trail.clear();
      _details.clear();
      _detailKeys.clear();
      _savedOffsets.clear();
    });
  }

  @override
  void dispose() {
    _disposing = true;
    if (_route != null) _navigationHistory?.unregister(_route!, _historyClient);
    _history?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scale =
            (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1.0, 1.5);
        final minimumWidth = widget.mode == ReadingMode.automatic &&
                MediaQuery.sizeOf(context).shortestSide < 600
            ? double.infinity
            : 720.0;
        _canSplit = widget.mode != ReadingMode.disabled &&
            width >= minimumWidth * scale;
        final reading = _selectedId != null;
        final detailWidth = width < 720 * scale
            ? width
            : (680.0 * scale).clamp(680.0, 760.0).clamp(0.0, width);
        // Account for the navigation rail so the article follows the window's
        // center, rather than the center of the space left by the sidebar.
        final detailLeft = ((width - widget.leadingInset - detailWidth) / 2)
            .clamp(0.0, width - detailWidth);
        final sidebarLeft = detailLeft + detailWidth + 16;
        final sidebarWidth = (width - sidebarLeft - 16).clamp(0.0, 300.0);
        final sidebarFits = width >= 720 * scale && sidebarWidth >= 260;
        final showSidebar = reading && sidebarFits && _sidebarVisible;
        // LocalHistoryEntry alone does not notify Flutter 3.24's native back
        // bridge. PopScope keeps Android back inside the app while reading.
        return PopScope(
            canPop: _selectedId == null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) close();
            },
            child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Stack(children: [
                  Positioned.fill(
                    left: showSidebar ? sidebarLeft : 0,
                    right: showSidebar ? width - sidebarLeft - sidebarWidth : 0,
                    top: showSidebar ? 48 : 0,
                    child: Offstage(
                      offstage: reading && !showSidebar,
                      child: FeedNavigation(
                        compact: showSidebar,
                        openFeed: _open,
                        selectedId: _selectedId,
                        child: ExcludeFocus(
                            excluding: reading && !showSidebar,
                            child: ExcludeSemantics(
                                excluding: reading && !showSidebar,
                                child:
                                    KeyboardScrollRegion(child: widget.child))),
                      ),
                    ),
                  ),
                  for (final entry in _details.entries)
                    Positioned(
                      key: _detailKeys.putIfAbsent(entry.key, GlobalKey.new),
                      top: 0,
                      bottom: 0,
                      left: detailLeft,
                      width: detailWidth,
                      child: Offstage(
                          offstage: entry.key != _selectedId,
                          child: TickerMode(
                              enabled: entry.key == _selectedId,
                              child: ExcludeFocus(
                                  excluding: entry.key != _selectedId,
                                  child: ClipRect(
                                      child: Material(
                                    child: KeyboardScrollRegion(
                                        autofocus: entry.key == _selectedId,
                                        child: FeedNavigation(
                                            openFeed: _open,
                                            selectedId: _selectedId,
                                            child: NotificationListener<
                                                    ScrollMetricsNotification>(
                                                onNotification: (_) {
                                                  _restoreDetail(entry.key);
                                                  return false;
                                                },
                                                child: entry.value))),
                                  ))))),
                    ),
                  if (showSidebar)
                    Positioned(
                        top: 0,
                        height: 48,
                        left: sidebarLeft,
                        width: sidebarWidth,
                        child: Row(children: [
                          const Expanded(
                              child: Padding(
                            padding: EdgeInsets.only(left: 12),
                            child: Text('继续浏览'),
                          )),
                          IconButton(
                            tooltip: '收起信息流',
                            onPressed: () =>
                                setState(() => _sidebarVisible = false),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ])),
                  if (reading && sidebarFits && !_sidebarVisible)
                    Positioned(
                      top: 8,
                      right: 16,
                      child: IconButton.filledTonal(
                        tooltip: '显示信息流',
                        onPressed: () => setState(() => _sidebarVisible = true),
                        icon: const Icon(Icons.view_sidebar_outlined),
                      ),
                    ),
                ])));
      });
}

/// Standalone detail routes use the same readable line length as embedded ones.
class ReadingContentFrame extends StatelessWidget {
  const ReadingContentFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale =
        (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1.0, 1.5);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Center(
          child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: (680 * scale).clamp(680.0, 760.0)),
        child: child,
      )),
    );
  }
}
