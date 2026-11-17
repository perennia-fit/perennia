import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/onboarding_gate.dart';
import 'onboarding_flow.dart';

/// Shows [child] (Today) from the first frame, then pushes [OnboardingFlow] over
/// it if the gate says so. It shows no spinner, and nothing here waits on the
/// network (When it runs in docs/designs/user-profile.md).
class OnboardingLauncher extends ConsumerStatefulWidget {
  const OnboardingLauncher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OnboardingLauncher> createState() => _OnboardingLauncherState();
}

class _OnboardingLauncherState extends ConsumerState<OnboardingLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openIfGateAllows());
    });
  }

  Future<void> _openIfGateAllows() async {
    bool show;
    try {
      show = await ref.read(onboardingGateProvider.future);
    } on Object {
      // A failed gate shows no onboarding, so Today still works.
      show = false;
    }
    if (!mounted || !show) {
      return;
    }
    final navigator = Navigator.of(context);
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => OnboardingFlow(onDone: () => navigator.pop()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
