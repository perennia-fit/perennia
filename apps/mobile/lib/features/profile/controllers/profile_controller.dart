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

class ProfileController extends StreamNotifier<UserProfile> {
  @override
  Stream<UserProfile> build() {
    return ref.watch(trainingRepositoriesProvider).userProfile.watch();
  }

  /// Checks [changes] against the section's current values and saves them if
  /// nothing stands in the way.
  ///
  /// A returned result with errors saved nothing, and one with warnings saved
  /// nothing either: the screen confirms them and calls [saveAnyway]. When the
  /// repository says saving would change nothing, the result is empty, so it
  /// warns about nothing.
  Future<UserProfileValidationResult> save(
    UserProfileSection section,
    Map<String, Object?> changes,
  ) async {
    final repository = ref.read(trainingRepositoriesProvider).userProfile;
    final merged = await repository.mergedIfChanged(section, changes);
    if (merged == null) {
      return UserProfileValidationResult(
        errors: const <UserProfileValidationIssue>[],
        warnings: const <UserProfileValidationIssue>[],
      );
    }

    final result = validateUserProfileSection(
      section,
      merged,
      referenceYear: DateTime.now().year,
    );
    if (result.errors.isEmpty && result.warnings.isEmpty) {
      await repository.saveSection(section, changes);
    }
    return result;
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
