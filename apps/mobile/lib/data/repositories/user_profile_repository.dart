part of 'training_repositories.dart';

/// The User Profile's section rows (docs/designs/user-profile.md, Data model).
///
/// Reads take the live row with the greatest `updated_at` for each section, and
/// ties go to the greatest id, as the agent read does. Writes update that row in
/// place, so a section gains a second row only when another install created its
/// own before the two synced. The older row stays in the table, unread.
///
/// The User Profile is never deleted by the app: clearing every field keeps the
/// row with all fields unset. The only tombstones here come from undoing a
/// section's first write, from Erase all data and from a full re-sync, and a
/// section left with only tombstones reads as no row.
class UserProfileRepository {
  UserProfileRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Stream<UserProfile> watch() {
    final query = _database.select(_database.userProfileSections)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy(_userProfileSectionsNewestFirst);
    return query.watch().map(_userProfileFromNewestFirstRows);
  }

  Future<bool> hasAnySection() async {
    final row = await (_database.select(_database.userProfileSections)
          ..where((row) => row.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// [section]'s values after [changes], or null when saving them would change
  /// nothing, which includes empty [changes]. The caller validates them; nothing
  /// is written.
  Future<Map<String, Object?>?> mergedIfChanged(
    UserProfileSection section,
    Map<String, Object?> changes,
  ) async {
    final existing = await _newestRow(section);
    return _mergedIfChanged(
      section,
      existing == null
          ? const <String, Object?>{}
          : _userProfileSectionValues(existing.valuesJson),
      changes,
    );
  }

  /// Saves [changes] into [section], following Save semantics: a field absent
  /// from [changes] is unchanged, null clears it, and a list replaces the whole
  /// list. A save that changes nothing writes nothing, because a write would
  /// make undo of the earlier Batch read as changed since. A save that would
  /// create a row with every field unset writes nothing either.
  ///
  /// Throws [UserProfileValidationException] on a hard error, before any write.
  /// The no-change test comes first: with nothing to write there is nothing to
  /// reject, so a stored row holding a value the rules refuse can't make a retry
  /// throw. Warnings are not checked here: the controller asks first, so a
  /// confirmed improbable value saves.
  Future<void> saveSection(
    UserProfileSection section,
    Map<String, Object?> changes, {
    String? batchId,
  }) {
    final context = _repositories._writeContexts.create(
      actor: 'user',
      batchId: batchId,
    );

    return _database.transaction(() async {
      final existing = await _newestRow(section);
      final merged = _mergedIfChanged(
        section,
        existing == null
            ? const <String, Object?>{}
            : _userProfileSectionValues(existing.valuesJson),
        changes,
      );
      if (merged == null) {
        return;
      }
      validateUserProfileSection(
        section,
        merged,
        referenceYear: context.timestamp.toLocal().year,
      ).throwIfRejected();

      if (existing == null) {
        if (isUserProfileSectionUnset(section, merged)) {
          return;
        }
        final id = _repositories._ids.create(context.timestamp);
        await _database.into(_database.userProfileSections).insert(
              UserProfileSectionsCompanion.insert(
                id: id,
                section: section.wireName,
                valuesJson: jsonEncode(merged),
                updatedAt: context.timestamp,
              ),
            );
        await _appendChange(context, id, beforeImage: null);
        return;
      }

      await (_database.update(_database.userProfileSections)
            ..where((row) => row.id.equals(existing.id)))
          .write(
        UserProfileSectionsCompanion(
          valuesJson: Value<String>(jsonEncode(merged)),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      await _appendChange(
        context,
        existing.id,
        beforeImage: _userProfileSectionImage(existing),
      );
    });
  }

  /// Applies a pulled row, as `NutritionRepository.applySyncImage` does. A
  /// malformed image raises [FormatException], for the pull's quarantine.
  Future<void> applySyncImage({
    required Map<String, Object?> image,
    required String deviceId,
    required String batchId,
    String actor = 'sync',
    String? activityLogId,
    Map<String, Object?>? activityBeforeImage,
    Map<String, Object?>? activityAfterImage,
    DateTime? activityOccurredAt,
  }) {
    final context = _repositories._writeContexts.create(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final id = _activityRequiredString(image, 'id');
      final localBeforeImage = await _currentImage(id);
      await _database
          .into(_database.userProfileSections)
          .insertOnConflictUpdate(
            _userProfileSectionSyncCompanionFromImage(
              image,
              syncDeviceId: deviceId,
            ),
          );
      final localAfterImage = await _currentImage(id);
      if (localAfterImage == null ||
          (localBeforeImage != null &&
              _activityImagesEqual(localBeforeImage, localAfterImage))) {
        return;
      }

      await _repositories._activityLogWriter.append(
        context,
        entityTable: AppDatabase.userProfileSectionsTable,
        entityId: id,
        beforeImage: activityBeforeImage ?? localBeforeImage,
        afterImage: activityAfterImage ?? localAfterImage,
        id: activityLogId,
        occurredAt: activityOccurredAt,
        syncAcknowledgedAt: context.timestamp,
      );
    });
  }

  Future<UserProfileSectionRow?> _newestRow(UserProfileSection section) {
    return (_database.select(_database.userProfileSections)
          ..where(
            (row) =>
                row.section.equals(section.wireName) & row.deletedAt.isNull(),
          )
          ..orderBy(_userProfileSectionsNewestFirst)
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> _appendChange(
    WriteContext context,
    String id, {
    required Map<String, Object?>? beforeImage,
  }) async {
    await _repositories._activityLogWriter.append(
      context,
      entityTable: AppDatabase.userProfileSectionsTable,
      entityId: id,
      beforeImage: beforeImage,
      afterImage: await _currentImage(id),
    );
  }

  Future<Map<String, Object?>?> _currentImage(String id) {
    return _repositories.activityLog._currentImageFor(
      entityTable: AppDatabase.userProfileSectionsTable,
      entityId: id,
    );
  }
}

/// Newest first, so a read's first row for a section is the one that wins:
/// greatest `updated_at`, then greatest id. `updated_at` is stored in whole
/// seconds, so ties are ordinary.
List<OrderClauseGenerator<$UserProfileSectionsTable>>
    get _userProfileSectionsNewestFirst {
  return <OrderClauseGenerator<$UserProfileSectionsTable>>[
    (row) => OrderingTerm.desc(row.updatedAt),
    (row) => OrderingTerm.desc(row.id),
  ];
}

/// The merged values, or null when they match what merging no changes gives.
/// Both sides go through the merge, so a stray value a tolerant read drops does
/// not count as a change.
Map<String, Object?>? _mergedIfChanged(
  UserProfileSection section,
  Map<String, Object?> current,
  Map<String, Object?> changes,
) {
  final merged = mergeUserProfileSectionValues(section, current, changes);
  final unchanged = mergeUserProfileSectionValues(
    section,
    current,
    const <String, Object?>{},
  );
  return jsonEncode(merged) == jsonEncode(unchanged) ? null : merged;
}

UserProfile _userProfileFromNewestFirstRows(List<UserProfileSectionRow> rows) {
  final newest = <UserProfileSection, UserProfileSectionValues>{};
  for (final row in rows) {
    final section = UserProfileSection.fromWireName(row.section);
    if (section != null && !newest.containsKey(section)) {
      newest[section] = UserProfileSectionValues.fromJson(
        section,
        _userProfileSectionValues(row.valuesJson),
      );
    }
  }
  return UserProfile(
    aboutYou: newest[UserProfileSection.aboutYou] as AboutYouValues?,
    trainingGoals:
        newest[UserProfileSection.trainingGoals] as TrainingGoalsValues?,
    experience: newest[UserProfileSection.experience] as ExperienceValues?,
    trainingSetup:
        newest[UserProfileSection.trainingSetup] as TrainingSetupValues?,
    healthLimitations: newest[UserProfileSection.healthLimitations]
        as HealthLimitationsValues?,
    generalNotes:
        newest[UserProfileSection.generalNotes] as GeneralNotesValues?,
  );
}

/// A stored row's values. Push does no domain validation and an archive can
/// hold anything, so a column that isn't a JSON object reads as no values: an
/// unreadable row must neither break a read nor block the next save.
Map<String, Object?> _userProfileSectionValues(String valuesJson) {
  try {
    final decoded = jsonDecode(valuesJson);
    return decoded is Map ? Map<String, Object?>.from(decoded) : {};
  } on FormatException {
    return <String, Object?>{};
  }
}

/// `values` is a nested object, not the column's string: the image is the push
/// payload, so it has to be the wire shape, and the server's agent redaction
/// reads inside it.
Map<String, Object?> _userProfileSectionImage(UserProfileSectionRow row) {
  return <String, Object?>{
    'id': row.id,
    'section': row.section,
    'values': _userProfileSectionValues(row.valuesJson),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

/// Raises [FormatException] for an image the server would have refused, which
/// is what the pull quarantines. The messages name fields only: these values
/// are health data, and an exception can reach a log.
UserProfileSectionsCompanion _userProfileSectionCompanionFromImage(
  Map<String, Object?> image,
) {
  final section = image['section'];
  if (section is! String || UserProfileSection.fromWireName(section) == null) {
    throw const FormatException('section must be a User Profile section.');
  }
  final values = image['values'];
  if (values is! Map) {
    throw const FormatException('values must be an object.');
  }
  return UserProfileSectionsCompanion(
    section: Value<String>(section),
    valuesJson: Value<String>(jsonEncode(values)),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

UserProfileSectionsCompanion _userProfileSectionSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _userProfileSectionCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

/// An image with its stamps at the whole seconds a row stores. An agent write's
/// after-image keeps the server's milliseconds, so without this a pulled agent
/// write would look changed since and its undo would always be refused (CUJ 6).
Map<String, Object?> _userProfileSectionImageNormalized(
  Map<String, Object?> image,
) {
  Object? wholeSeconds(Object? stamp) {
    final parsed = stamp is String ? DateTime.tryParse(stamp) : null;
    return parsed == null ? stamp : parsed.millisecondsSinceEpoch ~/ 1000;
  }

  return <String, Object?>{
    ...image,
    'updated_at': wholeSeconds(image['updated_at']),
    'deleted_at': wholeSeconds(image['deleted_at']),
  };
}
