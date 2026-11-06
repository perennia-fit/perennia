import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/profile/user_profile.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../profile/controllers/profile_controller.dart';
import '../../settings/repositories/settings_repository.dart';

enum OnboardingStep { screen1, screen2, screen3, done }

/// Where the flow is, and the stored User Profile as of the last step change.
///
/// [step] and [profile] change together, so a screen's fields start from what
/// is stored. Until the first read returns, [profile] is empty: the gate only
/// opens the flow when no section row exists, so that is also what is stored.
@immutable
class OnboardingState {
  const OnboardingState({required this.step, required this.profile});

  final OnboardingStep step;
  final UserProfile profile;
}

final onboardingControllerProvider =
    NotifierProvider.autoDispose<OnboardingController, OnboardingState>(
  OnboardingController.new,
);

/// Flow state and saves for first-open onboarding (Onboarding flow in
/// docs/designs/user-profile.md).
///
/// A write that has started finishes even if the provider is disposed on the
/// way, so `onboardingDone` can't be lost after its screen saved. Only setting
/// [state] stops at that point.
class OnboardingController extends Notifier<OnboardingState> {
  /// Set while a step action runs. A second tap in that time does nothing:
  /// it would read the same stored values as the first, so both would write,
  /// and the extra Batch makes undo of the first read as changed since.
  bool _acting = false;

  /// The latest step change. The read at start-up can return after the user
  /// has already moved on, and must not put them back on screen 1.
  int _latestStepChange = 0;

  @override
  OnboardingState build() {
    // A read still pending when the flow closes fails with the database's stream
    // closing. Nobody is waiting for it, so that failure goes nowhere.
    unawaited(
      _goTo(OnboardingStep.screen1).catchError(
        (Object _) {},
        test: (_) => !ref.mounted,
      ),
    );
    return const OnboardingState(
      step: OnboardingStep.screen1,
      profile: UserProfile(),
    );
  }

  /// Checks [changes] against each section's stored values. It writes nothing.
  ///
  /// The caller validates every section before saving any, so a rejected
  /// Experience can't leave Training Goals half-saved on screen 2. A section
  /// whose save would change nothing has no check, as under
  /// `ProfileController.save`: going back and tapping Next again must not ask
  /// the user to confirm a warning for a save that writes nothing.
  Future<List<ProfileSaveCheck>> check(
    Map<UserProfileSection, Map<String, Object?>> changes,
  ) async {
    final profile =
        await ref.read(trainingRepositoriesProvider).userProfile.watch().first;
    final referenceYear = DateTime.now().year;
    final checks = <ProfileSaveCheck>[];
    for (final MapEntry(key: section, value: sectionChanges)
        in changes.entries) {
      final merged = _mergedIfChanged(profile, section, sectionChanges);
      if (merged != null) {
        checks.add(
          ProfileSaveCheck.validate(
            section,
            merged,
            referenceYear: referenceYear,
          ),
        );
      }
    }
    return checks;
  }

  /// Saves the current screen and moves on. Call it only after [check] and the
  /// user's confirmation: a hard error here throws
  /// `UserProfileValidationException` and the step stays.
  ///
  /// Screen 1 saves in the order the spec fixes: each changed setting, then the
  /// About you section, then `onboardingDone`. `onboardingDone` goes last and
  /// is no Activity Log Batch, so no undo can bring onboarding back.
  Future<void> next({
    required Map<UserProfileSection, Map<String, Object?>> changes,
    UnitSystem? unitSystem,
    WeekStartDay? weekStartDay,
  }) {
    return _act(() async {
      final step = state.step;
      if (step == OnboardingStep.done) {
        return;
      }
      final repositories = ref.read(trainingRepositoriesProvider);
      final settingsController = ref.read(settingsControllerProvider.notifier);
      final settings = await ref.read(settingsControllerProvider.future);

      if (step == OnboardingStep.screen1) {
        if (unitSystem != null && unitSystem != settings.unitSystem) {
          await settingsController.setUnitSystem(unitSystem);
        }
        if (weekStartDay != null && weekStartDay != settings.weekStartDay) {
          await settingsController.setWeekStartDay(weekStartDay);
        }
      }
      await _saveSections(repositories, changes);
      if (step == OnboardingStep.screen1 && !settings.onboardingDone) {
        await settingsController.setOnboardingDone();
      }
      await _goTo(_stepAfter(step));
    });
  }

  /// Moves on and saves nothing for the screen. Leaving screen 1 this way still
  /// sets `onboardingDone`.
  Future<void> skipThis() {
    return _act(() async {
      final step = state.step;
      if (step == OnboardingStep.done) {
        return;
      }
      if (step == OnboardingStep.screen1) {
        await _setOnboardingDone();
      }
      await _goTo(_stepAfter(step));
    });
  }

  /// Leaves onboarding from any screen. The current screen saves nothing.
  Future<void> skipAll() {
    return _act(() async {
      await _setOnboardingDone();
      await _goTo(OnboardingStep.done);
    });
  }

  /// Goes back one screen. Screen 1 has no back arrow, so it does nothing there.
  Future<void> back() {
    return _act(() async {
      final previous = switch (state.step) {
        OnboardingStep.screen2 => OnboardingStep.screen1,
        OnboardingStep.screen3 => OnboardingStep.screen2,
        OnboardingStep.screen1 || OnboardingStep.done => null,
      };
      if (previous != null) {
        await _goTo(previous);
      }
    });
  }

  /// Runs the sign-in flow from screen 1, then acts on the session it left.
  ///
  /// [openSignIn] pushes `SignInScreen` and completes when it is gone. The
  /// widget passes it because a controller never touches a Navigator, and
  /// because `SignInScreen` returns no result: on success it stays open and
  /// shows its Account view, so only the auth state says how it ended.
  ///
  /// A session sets `onboardingDone` and goes to `done`. It writes no section
  /// and does not touch sync: the first Sync Run happens in the background, as
  /// for any sign-in. A session that already existed (an iOS keychain survives
  /// reinstall) counts too once the user returns. No session, whether from a
  /// cancel, a failed attempt or an auth state that failed to load, stays on
  /// screen 1.
  Future<void> signIn(Future<void> Function() openSignIn) {
    return _act(() async {
      if (state.step != OnboardingStep.screen1) {
        return;
      }
      await openSignIn();
      if (!ref.mounted) {
        return;
      }
      final AuthSession? session;
      try {
        session = (await ref.read(authControllerProvider.future)).session;
      } on Object {
        return;
      }
      if (session == null || !ref.mounted) {
        return;
      }
      await _setOnboardingDone();
      await _goTo(OnboardingStep.done);
    });
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_acting) {
      return;
    }
    _acting = true;
    try {
      await action();
    } finally {
      _acting = false;
    }
  }

  /// Saves each section that changes as one Batch: screens 2 and 3 save as one
  /// Activity Log Batch, and screen 1 has only the one section.
  ///
  /// It calls `saveSection` directly because `ProfileController` takes no
  /// `batchId`. `saveSection` writes even when nothing changes on an existing
  /// row, and Save semantics requires no write, so the no-op test is here.
  Future<void> _saveSections(
    TrainingRepositories repositories,
    Map<UserProfileSection, Map<String, Object?>> changes,
  ) async {
    final userProfile = repositories.userProfile;
    final profile = await userProfile.watch().first;
    final batchId = repositories.uuidGenerator.generate();
    for (final MapEntry(key: section, value: sectionChanges)
        in changes.entries) {
      if (_mergedIfChanged(profile, section, sectionChanges) != null) {
        await userProfile.saveSection(
          section,
          sectionChanges,
          batchId: batchId,
        );
      }
    }
  }

  Future<void> _setOnboardingDone() async {
    final settingsController = ref.read(settingsControllerProvider.notifier);
    final settings = await ref.read(settingsControllerProvider.future);
    if (!settings.onboardingDone) {
      await settingsController.setOnboardingDone();
    }
  }

  Future<void> _goTo(OnboardingStep step) async {
    if (!ref.mounted) {
      return;
    }
    final stepChange = ++_latestStepChange;
    final profile =
        await ref.read(trainingRepositoriesProvider).userProfile.watch().first;
    if (!ref.mounted || stepChange != _latestStepChange) {
      return;
    }
    state = OnboardingState(step: step, profile: profile);
  }
}

/// The section's values after [changes], or null when saving them would change
/// nothing, which includes empty [changes].
Map<String, Object?>? _mergedIfChanged(
  UserProfile profile,
  UserProfileSection section,
  Map<String, Object?> changes,
) {
  final current =
      profileSectionValues(profile, section)?.toJson() ?? <String, Object?>{};
  final merged = mergeUserProfileSectionValues(section, current, changes);
  final unchanged = mergeUserProfileSectionValues(
    section,
    current,
    const <String, Object?>{},
  );
  return jsonEncode(merged) == jsonEncode(unchanged) ? null : merged;
}

OnboardingStep _stepAfter(OnboardingStep step) {
  return switch (step) {
    OnboardingStep.screen1 => OnboardingStep.screen2,
    OnboardingStep.screen2 => OnboardingStep.screen3,
    OnboardingStep.screen3 || OnboardingStep.done => OnboardingStep.done,
  };
}
