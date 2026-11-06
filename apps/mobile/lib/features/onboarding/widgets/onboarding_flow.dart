import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/profile/user_profile.dart';
import '../../../domain/profile/user_profile_validation.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../auth/widgets/sign_in_screen.dart';
import '../../profile/controllers/profile_controller.dart';
import '../../profile/widgets/profile_screen.dart';
import '../../profile/widgets/profile_section_editors.dart';
import '../../settings/repositories/settings_repository.dart';
import '../../settings/widgets/general_settings_screen.dart'
    show SegmentedPreference;
import '../controllers/onboarding_controller.dart';

/// The three first-open screens (Onboarding flow in
/// docs/designs/user-profile.md). Every one can be left at once, and nothing
/// here asks for an OS permission.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key, required this.onDone});

  static const backButtonKey = Key('onboarding.back');
  static const skipAllButtonKey = Key('onboarding.skipAll');
  static const skipThisButtonKey = Key('onboarding.skipThis');
  static const nextButtonKey = Key('onboarding.next');
  static const unitSystemKey = Key('onboarding.unitSystem');
  static const weekStartDayKey = Key('onboarding.weekStartDay');
  static const signInLinkKey = Key('onboarding.signIn');
  static const errorsKey = Key('onboarding.errors');

  /// Called once, when the flow reaches `done`.
  final VoidCallback onDone;

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  final _errorsAnchor = GlobalKey();

  /// What the fields of the current screen report, cleared on every step change
  /// so a screen left behind can't be saved again.
  final _changes = <UserProfileSection, Map<String, Object?>>{};
  UnitSystem? _pickedUnitSystem;
  WeekStartDay? _pickedWeekStartDay;
  List<String> _errors = const <String>[];

  /// True from the first tap of an action to its end, including [_next]'s check
  /// and dialog, which the controller's own guard doesn't cover. A second tap
  /// could otherwise open two dialogs or write two Batches.
  bool _busy = false;

  MaterialPageRoute<void>? _signInRoute;

  void _onFieldsChanged(
    UserProfileSection section,
    Map<String, Object?> changes,
  ) {
    setState(() {
      _changes[section] = changes;
      _errors = const <String>[];
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  OnboardingController get _controller =>
      ref.read(onboardingControllerProvider.notifier);

  Future<void> _next() async {
    final l10n = context.l10n;
    final changes = Map.of(_changes);
    final checks = await _controller.check(changes);
    if (!mounted) {
      return;
    }
    List<String> messages(
      List<UserProfileValidationIssue> Function(ProfileSaveCheck) issues,
    ) {
      return [
        for (final check in checks)
          for (final issue in issues(check))
            profileValidationMessage(l10n, issue, check),
      ];
    }

    final errors = messages((check) => check.errors);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      _showErrors();
      return;
    }
    final warnings = messages((check) => check.warnings);
    if (warnings.isNotEmpty) {
      final confirmed = await showProfileSoftWarningDialog(context, warnings);
      if (!confirmed || !mounted) {
        return;
      }
    }
    await _controller.next(
      changes: changes,
      unitSystem: _pickedUnitSystem,
      weekStartDay: _pickedWeekStartDay,
    );
  }

  /// The errors sit under the fields, so with the keyboard up or at large text
  /// they can land below the fold, and **Next** would look like it did nothing.
  void _showErrors() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final anchor = _errorsAnchor.currentContext;
      if (anchor != null && anchor.mounted) {
        unawaited(Scrollable.ensureVisible(anchor));
      }
    });
  }

  Future<void> _signIn() {
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute<void>(builder: (_) => const SignInScreen());
    _signInRoute = route;
    return _run(() => _controller.signIn(() => navigator.push(route)));
  }

  void _onPopInvoked(bool didPop, Object? _) {
    if (!didPop && !_busy) {
      unawaited(_run(_controller.back));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final state = ref.watch(onboardingControllerProvider);
    final step = state.step;
    ref.listen(onboardingControllerProvider, (previous, next) {
      if (previous?.step == next.step) {
        return;
      }
      setState(() {
        _changes.clear();
        _pickedUnitSystem = null;
        _pickedWeekStartDay = null;
        _errors = const <String>[];
      });
      if (next.step == OnboardingStep.done) {
        widget.onDone();
      }
    });
    final flowRoute = ModalRoute.of(context);
    // SignInScreen stays open on its Account view after a success, so the flow
    // closes it, and the user lands on Today. A loading state can still carry
    // the old session, which is what signing out of that view looks like.
    //
    // An attempt can also succeed after the user backed out of its route. That
    // session is real, so it finishes like any sign-in, but only from a flow that
    // is idle and in front: `onDone` pops the top route, which could be a dialog
    // or a picker, and an action already running decides where the user goes.
    // Otherwise the user carries on here, signed in, and leaves by Next or Skip.
    ref.listen(authControllerProvider, (_, next) {
      final route = _signInRoute;
      if (next.isLoading || next.value?.session == null || route == null) {
        return;
      }
      if (route.isCurrent) {
        route.navigator?.pop();
      } else if (!route.isActive && !_busy && (flowRoute?.isCurrent ?? false)) {
        unawaited(_run(_controller.finishLateSignIn));
      }
    });

    final enabled = !_busy && step != OnboardingStep.done;
    final textButtonStyle = TextButton.styleFrom(
      foregroundColor: colors.textPrimary,
      minimumSize: const Size.square(AppDimens.touchTarget),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: step == OnboardingStep.screen2 ||
                  step == OnboardingStep.screen3
              ? IconButton(
                  key: OnboardingFlow.backButtonKey,
                  tooltip: l10n.onboardingBack,
                  onPressed:
                      enabled ? () => unawaited(_run(_controller.back)) : null,
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
          actions: [
            TextButton(
              key: OnboardingFlow.skipAllButtonKey,
              style: textButtonStyle,
              onPressed:
                  enabled ? () => unawaited(_run(_controller.skipAll)) : null,
              child: Text(l10n.onboardingSkipAll),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // The key rebuilds the fields from the stored profile on every
                // step change and starts the new screen at the top.
                child: KeyedSubtree(
                  key: ValueKey<OnboardingStep>(step),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppDimens.base),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            _title(l10n, step),
                            style: context.textStyles.h2,
                          ),
                        ),
                        const SizedBox(height: AppDimens.base),
                        ..._fields(state),
                        if (_errors.isNotEmpty) ...[
                          const SizedBox(height: AppDimens.base),
                          KeyedSubtree(
                            key: _errorsAnchor,
                            child: ProfileErrorLines(
                              key: OnboardingFlow.errorsKey,
                              lines: _errors,
                            ),
                          ),
                        ],
                        if (step == OnboardingStep.screen1) ...[
                          const SizedBox(height: AppDimens.dense),
                          TextButton(
                            key: OnboardingFlow.signInLinkKey,
                            style: textButtonStyle.copyWith(
                              alignment: AlignmentDirectional.centerStart,
                            ),
                            onPressed:
                                enabled ? () => unawaited(_signIn()) : null,
                            child: Text(l10n.onboardingSignInLink),
                          ),
                        ],
                        const SizedBox(height: AppDimens.base),
                        // It scrolls with the fields: pinned, it would squeeze
                        // them at 200% text.
                        const ProfileDisclosureLine(),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppDimens.base),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        key: OnboardingFlow.skipThisButtonKey,
                        label: l10n.onboardingSkipThis,
                        onPressed: enabled
                            ? () => unawaited(_run(_controller.skipThis))
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppDimens.dense),
                    Expanded(
                      child: _ActionButton(
                        key: OnboardingFlow.nextButtonKey,
                        label: step == OnboardingStep.screen3
                            ? l10n.onboardingDone
                            : l10n.onboardingNext,
                        onPressed:
                            enabled ? () => unawaited(_run(_next)) : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _title(AppLocalizations l10n, OnboardingStep step) {
    return switch (step) {
      OnboardingStep.screen1 => l10n.onboardingTitleAboutYou,
      OnboardingStep.screen2 => l10n.onboardingTitleGoalsExperience,
      OnboardingStep.screen3 ||
      OnboardingStep.done =>
        l10n.onboardingTitleTrainingSetup,
    };
  }

  List<Widget> _fields(OnboardingState state) {
    final l10n = context.l10n;
    final profile = state.profile;
    switch (state.step) {
      case OnboardingStep.screen1:
        final settings =
            ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
        final unitSystem = _pickedUnitSystem ?? settings.unitSystem;
        return [
          SegmentedPreference<UnitSystem>(
            key: OnboardingFlow.unitSystemKey,
            label: l10n.onboardingUnitsLabel,
            selected: unitSystem,
            values: UnitSystem.values,
            labelFor: (value) => value.label,
            onChanged: (value) async {
              setState(() {
                _pickedUnitSystem = value;
                _errors = const <String>[];
              });
            },
          ),
          SegmentedPreference<WeekStartDay>(
            key: OnboardingFlow.weekStartDayKey,
            label: l10n.onboardingWeekStartLabel,
            selected: _pickedWeekStartDay ?? settings.weekStartDay,
            values: WeekStartDay.values,
            labelFor: (value) => value.label,
            onChanged: (value) async {
              setState(() {
                _pickedWeekStartDay = value;
                _errors = const <String>[];
              });
            },
          ),
          const SizedBox(height: AppDimens.base),
          AboutYouFields(
            initial: profile.aboutYou,
            unitSystem: unitSystem,
            onChanged: (changes) =>
                _onFieldsChanged(UserProfileSection.aboutYou, changes),
          ),
        ];
      case OnboardingStep.screen2:
        return [
          _Subheading(l10n.profileSectionTrainingGoals),
          const SizedBox(height: AppDimens.dense),
          TrainingGoalsFields(
            initial: profile.trainingGoals,
            onChanged: (changes) =>
                _onFieldsChanged(UserProfileSection.trainingGoals, changes),
          ),
          const SizedBox(height: AppDimens.base),
          _Subheading(l10n.profileSectionExperience),
          const SizedBox(height: AppDimens.dense),
          ExperienceFields(
            initial: profile.experience,
            onChanged: (changes) =>
                _onFieldsChanged(UserProfileSection.experience, changes),
          ),
        ];
      case OnboardingStep.screen3:
        return [
          TrainingSetupFields(
            initial: profile.trainingSetup,
            onChanged: (changes) =>
                _onFieldsChanged(UserProfileSection.trainingSetup, changes),
          ),
        ];
      case OnboardingStep.done:
        return const <Widget>[];
    }
  }
}

class _Subheading extends StatelessWidget {
  const _Subheading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(text, style: context.textStyles.label),
    );
  }
}

/// Styled like the Profile editor's Save.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.secondary,
        foregroundColor: colorScheme.onSecondary,
        minimumSize: const Size.fromHeight(AppDimens.rowHeight),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardMd),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
