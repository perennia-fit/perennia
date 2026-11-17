import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../settings/repositories/settings_repository.dart';

/// Whether first-open onboarding should show: the device setting
/// `onboardingDone` is false and no live User Profile section row exists (see
/// Onboarding gate in docs/designs/user-profile.md).
///
/// Settings are read first and the provider returns before touching
/// `trainingRepositoriesProvider`, so a test harness that stubs the database
/// never reaches it. `retry` is off because Riverpod 3 would otherwise retry a
/// failure with backoff, and that would delay `.future`.
final onboardingGateProvider = FutureProvider<bool>(
  (ref) async {
    final settings = await ref.read(settingsControllerProvider.future);
    if (settings.onboardingDone) {
      return false;
    }
    return !(await ref
        .read(trainingRepositoriesProvider)
        .userProfile
        .hasAnySection());
  },
  retry: (_, __) => null,
);
