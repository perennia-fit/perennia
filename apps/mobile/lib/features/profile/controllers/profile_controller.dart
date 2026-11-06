import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/profile/user_profile.dart';
import '../../../domain/profile/user_profile_validation.dart';
import '../../auth/repositories/auth_repository.dart';

enum ProfileDisclosureMode { localOnly, synced }

/// Which disclosure line applies, and the host it names. The app has no separate
/// way to recognise the Official Service, and the host name stays accurate for
/// self-hosters.
@immutable
class ProfileDisclosure {
  const ProfileDisclosure.localOnly()
      : mode = ProfileDisclosureMode.localOnly,
        host = null;

  const ProfileDisclosure.synced(String this.host)
      : mode = ProfileDisclosureMode.synced;

  final ProfileDisclosureMode mode;

  /// The server's host name in Synced Mode, otherwise null.
  final String? host;
}

/// A session means Synced Mode. While the auth state is still loading, or if it
/// failed to load, nothing says the user is signed in, so the line is Local-only
/// Mode's, which also says what happens on sign-in.
final profileDisclosureProvider = Provider<ProfileDisclosure>((ref) {
  final authState = ref.watch(authControllerProvider).value;
  if (authState == null || authState.session == null) {
    return const ProfileDisclosure.localOnly();
  }
  return ProfileDisclosure.synced(authState.serverUrl.host);
});

final profileControllerProvider =
    StreamNotifierProvider<ProfileController, UserProfile>(
  ProfileController.new,
);

/// The result of checking a save against the shared validator.
///
/// [values] and [referenceYear] travel with the issues because two messages name
/// a value the issue doesn't carry: the age and the height.
@immutable
class ProfileSaveCheck {
  const ProfileSaveCheck({
    this.errors = const <UserProfileValidationIssue>[],
    this.warnings = const <UserProfileValidationIssue>[],
    this.values = const <String, Object?>{},
    this.referenceYear = 0,
  });

  factory ProfileSaveCheck.validate(
    UserProfileSection section,
    Map<String, Object?> values, {
    required int referenceYear,
  }) {
    final result = validateUserProfileSection(
      section,
      values,
      referenceYear: referenceYear,
    );
    return ProfileSaveCheck(
      errors: result.errors,
      warnings: result.warnings,
      values: values,
      referenceYear: referenceYear,
    );
  }

  final List<UserProfileValidationIssue> errors;
  final List<UserProfileValidationIssue> warnings;
  final Map<String, Object?> values;
  final int referenceYear;
}

class ProfileController extends StreamNotifier<UserProfile> {
  @override
  Stream<UserProfile> build() {
    return ref.watch(trainingRepositoriesProvider).userProfile.watch();
  }

  /// Checks [changes] against the section's current values and saves them if
  /// nothing stands in the way.
  ///
  /// A returned check with errors saved nothing, and one with warnings saved
  /// nothing either: the screen confirms them and calls [saveAnyway]. A save that
  /// changes nothing writes nothing and warns about nothing, because a write
  /// would add an Activity Log entry for no change.
  Future<ProfileSaveCheck> save(
    UserProfileSection section,
    Map<String, Object?> changes,
  ) async {
    final repository = ref.read(trainingRepositoriesProvider).userProfile;
    final profile = await repository.watch().first;
    final current =
        _sectionValues(profile, section)?.toJson() ?? const <String, Object?>{};
    final merged = mergeUserProfileSectionValues(section, current, changes);
    final unchanged = mergeUserProfileSectionValues(
      section,
      current,
      const <String, Object?>{},
    );
    if (jsonEncode(merged) == jsonEncode(unchanged)) {
      return const ProfileSaveCheck();
    }

    final check = ProfileSaveCheck.validate(
      section,
      merged,
      referenceYear: DateTime.now().year,
    );
    if (check.errors.isEmpty && check.warnings.isEmpty) {
      await repository.saveSection(section, changes);
    }
    return check;
  }

  /// Saves a change whose soft warnings the user has confirmed. Hard errors still
  /// throw [UserProfileValidationException].
  Future<void> saveAnyway(
    UserProfileSection section,
    Map<String, Object?> changes,
  ) {
    return ref
        .read(trainingRepositoriesProvider)
        .userProfile
        .saveSection(section, changes);
  }
}

UserProfileSectionValues? _sectionValues(
  UserProfile profile,
  UserProfileSection section,
) {
  return switch (section) {
    UserProfileSection.aboutYou => profile.aboutYou,
    UserProfileSection.trainingGoals => profile.trainingGoals,
    UserProfileSection.experience => profile.experience,
    UserProfileSection.trainingSetup => profile.trainingSetup,
    UserProfileSection.healthLimitations => profile.healthLimitations,
    UserProfileSection.generalNotes => profile.generalNotes,
  };
}
