import 'package:flutter/widgets.dart';

import '../logic/onboarding/onboarding_state.dart';

/// Keeps the main page (and its initial requests) unmounted until completion.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({
    super.key,
    required this.state,
    required this.mainBuilder,
    required this.onboardingBuilder,
  });

  final OnboardingState state;
  final WidgetBuilder mainBuilder;
  final WidgetBuilder onboardingBuilder;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  late bool _completed;
  Widget? _main;

  @override
  void initState() {
    super.initState();
    _completed = widget.state.completed;
    widget.state.addListener(_changed);
  }

  void _changed() {
    // Reopening the guide only changes active, and must not recreate main.
    if (_completed != widget.state.completed) {
      setState(() => _completed = widget.state.completed);
    }
  }

  @override
  void didUpdateWidget(covariant OnboardingGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_changed);
      widget.state.addListener(_changed);
      _completed = widget.state.completed;
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _completed
      ? _main ??= widget.mainBuilder(context)
      : widget.onboardingBuilder(context);
}

/// A completed save can release the state before the main route is mounted.
/// Recheck after the frame too: the guide may have reopened in the meantime.
Future<void> waitForOnboardingNavigation(OnboardingState? state) async {
  if (state == null) return;
  do {
    await state.waitUntilInactive();
    await WidgetsBinding.instance.endOfFrame;
  } while (state.active);
}
