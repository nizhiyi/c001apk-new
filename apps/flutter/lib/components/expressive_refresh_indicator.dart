import 'package:flutter/material.dart';

import 'expressive_loading_indicator.dart';

/// Preserve RefreshIndicatorState.show() and the existing refresh lifecycle.
class ExpressiveRefreshIndicator extends StatefulWidget {
  const ExpressiveRefreshIndicator({
    super.key,
    this.refreshKey,
    required this.onRefresh,
    required this.child,
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  final GlobalKey<RefreshIndicatorState>? refreshKey;
  final RefreshCallback onRefresh;
  final Widget child;
  final ScrollNotificationPredicate notificationPredicate;

  @override
  State<ExpressiveRefreshIndicator> createState() =>
      _ExpressiveRefreshIndicatorState();
}

class _ExpressiveRefreshIndicatorState
    extends State<ExpressiveRefreshIndicator> {
  RefreshIndicatorStatus? _status;

  @override
  Widget build(BuildContext context) {
    final visible = switch (_status) {
      RefreshIndicatorStatus.armed ||
      RefreshIndicatorStatus.snap ||
      RefreshIndicatorStatus.refresh =>
        true,
      _ => false,
    };
    return Stack(children: [
      RefreshIndicator.noSpinner(
        key: widget.refreshKey,
        onRefresh: widget.onRefresh,
        notificationPredicate: widget.notificationPredicate,
        onStatusChange: (status) {
          if (mounted) setState(() => _status = status);
        },
        child: widget.child,
      ),
      Positioned(
        top: 16 + MediaQuery.paddingOf(context).top,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              child: visible
                  ? Material(
                      key: const ValueKey('refreshing'),
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      shape: const StadiumBorder(),
                      elevation: 2,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: ExpressiveLoadingIndicator(size: 32),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ]);
  }
}
