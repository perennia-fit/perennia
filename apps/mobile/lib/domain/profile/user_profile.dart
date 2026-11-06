/// The User Profile: the optional, synced record of who the user is and what
/// they train for (docs/designs/user-profile.md, Data model). Six sections, one
/// live row each, and every field may be unset.
///
/// Values are read from a sync payload that nothing validated: the server runs
/// no domain rules at push, so a stored row can hold anything. Every `fromJson`
/// here is tolerant and never throws. A field of the wrong JSON type reads as
/// unset, and an entry a typed getter can't represent (an unknown Training
/// Goal, for example) is dropped.
library;

import 'package:flutter/foundation.dart';

/// Exactly 2.54 cm per inch. Height is stored as entered and converted on read
/// only, so this is the one place the factor lives on the device.
const double centimetresPerInch = 2.54;

/// The longest Equipment id a section may hold. A tolerant read and the
/// validator both apply it, so it lives below both.
const int profileEquipmentIdMaxLength = 64;

/// A User Profile section, with its sync-payload name and the fields its
/// values may carry.
enum UserProfileSection {
  aboutYou('about_you', <String>['sex', 'birth_year', 'height']),
  trainingGoals('training_goals', <String>['goals']),
  experience('experience', <String>['levels']),
  trainingSetup(
    'training_setup',
    <String>['equipment', 'days_per_week', 'session_minutes'],
  ),
  healthLimitations('health_limitations', <String>['text', 'none']),
  generalNotes('general_notes', <String>['text']);

  const UserProfileSection(this.wireName, this.fieldNames);

  final String wireName;
  final List<String> fieldNames;

  /// The section with [wireName], or null when no section has that name.
  static UserProfileSection? fromWireName(Object? wireName) =>
      _enumByWireName(values, wireName, (section) => section.wireName);
}

enum TrainingGoalId {
  longevity('longevity'),
  strength('strength'),
  muscleGain('muscle_gain'),
  bodyComposition('body_composition'),
  endurancePerformance('endurance_performance'),
  mobility('mobility'),
  generalFitness('general_fitness');

  const TrainingGoalId(this.wireName);

  final String wireName;

  static TrainingGoalId? fromWireName(Object? wireName) =>
      _enumByWireName(values, wireName, (goal) => goal.wireName);
}

enum ExperienceLevel {
  beginner('beginner'),
  intermediate('intermediate'),
  advanced('advanced');

  const ExperienceLevel(this.wireName);

  final String wireName;

  static ExperienceLevel? fromWireName(Object? wireName) =>
      _enumByWireName(values, wireName, (level) => level.wireName);
}

enum ProfileSex {
  female('female'),
  male('male');

  const ProfileSex(this.wireName);

  final String wireName;

  static ProfileSex? fromWireName(Object? wireName) =>
      _enumByWireName(values, wireName, (sex) => sex.wireName);
}

enum HeightUnit {
  cm('cm'),
  inch('in');

  const HeightUnit(this.wireName);

  final String wireName;

  static HeightUnit? fromWireName(Object? wireName) =>
      _enumByWireName(values, wireName, (unit) => unit.wireName);
}

/// A height as entered: centimetres, or the total in inches.
@immutable
class ProfileHeight {
  const ProfileHeight({required this.value, required this.unit});

  /// Null unless [json] is an object with a finite number and a known unit.
  static ProfileHeight? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final value = json['value'];
    final unit = HeightUnit.fromWireName(json['unit']);
    if (value is! num || !value.isFinite || unit == null) {
      return null;
    }
    return ProfileHeight(value: value.toDouble(), unit: unit);
  }

  final double value;
  final HeightUnit unit;

  double get inCentimetres =>
      unit == HeightUnit.cm ? value : value * centimetresPerInch;

  /// A whole number encodes with no fraction, so the row reads `66` rather than
  /// `66.0`, the same JSON the server writes for the same value.
  Map<String, Object?> toJson() => <String, Object?>{
        'value': value == value.truncateToDouble() ? value.toInt() : value,
        'unit': unit.wireName,
      };

  @override
  bool operator ==(Object other) =>
      other is ProfileHeight && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => 'ProfileHeight($value ${unit.wireName})';
}

/// One Focus's experience level. `focusId` is a soft reference: an entry whose
/// Focus is archived is kept.
@immutable
class ExperienceEntry {
  const ExperienceEntry({required this.focusId, required this.level});

  final String focusId;
  final ExperienceLevel level;

  Map<String, Object?> toJson() => <String, Object?>{
        'focus_id': focusId,
        'level': level.wireName,
      };

  @override
  bool operator ==(Object other) =>
      other is ExperienceEntry &&
      other.focusId == focusId &&
      other.level == level;

  @override
  int get hashCode => Object.hash(focusId, level);

  @override
  String toString() => 'ExperienceEntry($focusId, ${level.wireName})';
}

/// One section's values, in the wire shape.
@immutable
sealed class UserProfileSectionValues {
  const UserProfileSectionValues();

  factory UserProfileSectionValues.fromJson(
    UserProfileSection section,
    Map<String, Object?> json,
  ) {
    return switch (section) {
      UserProfileSection.aboutYou => AboutYouValues.fromJson(json),
      UserProfileSection.trainingGoals => TrainingGoalsValues.fromJson(json),
      UserProfileSection.experience => ExperienceValues.fromJson(json),
      UserProfileSection.trainingSetup => TrainingSetupValues.fromJson(json),
      UserProfileSection.healthLimitations =>
        HealthLimitationsValues.fromJson(json),
      UserProfileSection.generalNotes => GeneralNotesValues.fromJson(json),
    };
  }

  Map<String, Object?> toJson();

  /// Whether no field says anything. An empty list says something: it is the
  /// section's *none* choice.
  bool get isUnset;
}

class AboutYouValues extends UserProfileSectionValues {
  const AboutYouValues({this.sex, this.birthYear, this.height});

  factory AboutYouValues.fromJson(Map<String, Object?> json) => AboutYouValues(
        sex: ProfileSex.fromWireName(json['sex']),
        birthYear: _readInteger(json['birth_year']),
        height: ProfileHeight.fromJson(json['height']),
      );

  final ProfileSex? sex;
  final int? birthYear;
  final ProfileHeight? height;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'sex': sex?.wireName,
        'birth_year': birthYear,
        'height': height?.toJson(),
      };

  @override
  bool get isUnset => sex == null && birthYear == null && height == null;
}

class TrainingGoalsValues extends UserProfileSectionValues {
  const TrainingGoalsValues({this.goals});

  factory TrainingGoalsValues.fromJson(Map<String, Object?> json) {
    final goals = json['goals'];
    if (goals is! List) {
      return const TrainingGoalsValues();
    }
    return TrainingGoalsValues(
      goals: List<TrainingGoalId>.unmodifiable(
        goals.map(TrainingGoalId.fromWireName).nonNulls.toSet(),
      ),
    );
  }

  final List<TrainingGoalId>? goals;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'goals': goals?.map((goal) => goal.wireName).toList(),
      };

  @override
  bool get isUnset => goals == null;
}

class ExperienceValues extends UserProfileSectionValues {
  const ExperienceValues({this.levels});

  factory ExperienceValues.fromJson(Map<String, Object?> json) {
    final levels = json['levels'];
    if (levels is! List) {
      return const ExperienceValues();
    }
    final byFocus = <String, ExperienceEntry>{};
    for (final entry in levels) {
      if (entry is! Map) {
        continue;
      }
      final focusId = entry['focus_id'];
      final level = ExperienceLevel.fromWireName(entry['level']);
      if (focusId is String && focusId.isNotEmpty && level != null) {
        byFocus.putIfAbsent(
          focusId,
          () => ExperienceEntry(focusId: focusId, level: level),
        );
      }
    }
    return ExperienceValues(
      levels: List<ExperienceEntry>.unmodifiable(byFocus.values),
    );
  }

  final List<ExperienceEntry>? levels;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'levels': levels?.map((entry) => entry.toJson()).toList(),
      };

  @override
  bool get isUnset => levels == null;
}

class TrainingSetupValues extends UserProfileSectionValues {
  const TrainingSetupValues({
    this.equipment,
    this.daysPerWeek,
    this.sessionMinutes,
  });

  factory TrainingSetupValues.fromJson(Map<String, Object?> json) {
    final equipment = json['equipment'];
    return TrainingSetupValues(
      // Unknown ids are kept, as CONTEXT.md allows for Equipment. An entry the
      // validator would reject is dropped, so a stray one in a stored row can't
      // block a later save of this section's other fields.
      equipment: equipment is! List
          ? null
          : List<String>.unmodifiable(
              equipment
                  .whereType<String>()
                  .where(
                    (id) =>
                        id.isNotEmpty &&
                        id.length <= profileEquipmentIdMaxLength,
                  )
                  .toSet(),
            ),
      daysPerWeek: _readInteger(json['days_per_week']),
      sessionMinutes: _readInteger(json['session_minutes']),
    );
  }

  final List<String>? equipment;
  final int? daysPerWeek;
  final int? sessionMinutes;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'equipment': equipment?.toList(),
        'days_per_week': daysPerWeek,
        'session_minutes': sessionMinutes,
      };

  @override
  bool get isUnset =>
      equipment == null && daysPerWeek == null && sessionMinutes == null;
}

class HealthLimitationsValues extends UserProfileSectionValues {
  const HealthLimitationsValues({this.text, this.none = false});

  /// A stored `none: true` wins over any text in the same row, as it does in a
  /// save, so no reader sees both.
  factory HealthLimitationsValues.fromJson(Map<String, Object?> json) {
    final none = json['none'] == true;
    final text = json['text'];
    return HealthLimitationsValues(
      text: none || text is! String ? null : text,
      none: none,
    );
  }

  final String? text;
  final bool none;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'text': text,
        'none': none,
      };

  @override
  bool get isUnset => text == null && !none;
}

class GeneralNotesValues extends UserProfileSectionValues {
  const GeneralNotesValues({this.text});

  factory GeneralNotesValues.fromJson(Map<String, Object?> json) {
    final text = json['text'];
    return GeneralNotesValues(text: text is String ? text : null);
  }

  final String? text;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'text': text};

  @override
  bool get isUnset => text == null;
}

/// The whole record, as `UserProfileRepository.watch()` returns it. A section
/// with no row is null. Other features read the User Profile through these
/// getters only, and each is null when its field is unset.
@immutable
class UserProfile {
  const UserProfile({
    this.aboutYou,
    this.trainingGoals,
    this.experience,
    this.trainingSetup,
    this.healthLimitations,
    this.generalNotes,
  });

  final AboutYouValues? aboutYou;
  final TrainingGoalsValues? trainingGoals;
  final ExperienceValues? experience;
  final TrainingSetupValues? trainingSetup;
  final HealthLimitationsValues? healthLimitations;
  final GeneralNotesValues? generalNotes;

  ProfileSex? get sex => aboutYou?.sex;
  int? get birthYear => aboutYou?.birthYear;
  ProfileHeight? get height => aboutYou?.height;
  List<TrainingGoalId>? get goals => trainingGoals?.goals;
  List<ExperienceEntry>? get experienceLevels => experience?.levels;
  List<String>? get equipment => trainingSetup?.equipment;
  int? get daysPerWeek => trainingSetup?.daysPerWeek;
  int? get sessionMinutes => trainingSetup?.sessionMinutes;
  String? get healthText => healthLimitations?.text;
  bool? get healthNone => healthLimitations?.none;
  String? get generalNotesText => generalNotes?.text;

  /// The user's age in the local calendar year of [date]. Age is never stored:
  /// birth year alone makes this accurate to one year either way.
  int? ageAt(DateTime date) {
    final year = birthYear;
    return year == null ? null : date.toLocal().year - year;
  }
}

/// Merges a save into a section's current values, following Save semantics
/// (docs/designs/user-profile.md): a field absent from [changes] is unchanged,
/// a field given as null is cleared, and a list replaces the whole list. Health
/// & limitations is then normalised, so `none: true` with text can't be stored.
///
/// [current] is the stored row's values, read tolerantly, so a stray value in a
/// stored row is not carried into the merge. Keys this build doesn't know are
/// kept, so saving on an older build doesn't erase a field a newer one wrote.
///
/// This is the only place this logic lives on the device. Throws [ArgumentError]
/// when [changes] names a field the section doesn't have, a programming error
/// that would otherwise be stored and never read.
Map<String, Object?> mergeUserProfileSectionValues(
  UserProfileSection section,
  Map<String, Object?> current,
  Map<String, Object?> changes,
) {
  for (final field in changes.keys) {
    if (!section.fieldNames.contains(field)) {
      throw ArgumentError.value(
        field,
        'changes',
        'Not a field of ${section.wireName}.',
      );
    }
  }
  final merged = <String, Object?>{
    ...current,
    ...UserProfileSectionValues.fromJson(section, current).toJson(),
    ...changes,
  };
  if (section == UserProfileSection.healthLimitations) {
    final none = changes['none'];
    final text = changes['text'];
    if (none == true) {
      merged['text'] = null;
    } else if (text != null) {
      merged['none'] = false;
    }
    if (changes.containsKey('none') && none == null) {
      merged['none'] = false;
    }
  }
  return merged;
}

/// Whether [values] make a section *unset*: every field null, or for Health &
/// limitations `none: false` and `text: null`. A save that would create a row
/// from values like these creates nothing.
bool isUserProfileSectionUnset(
  UserProfileSection section,
  Map<String, Object?> values,
) {
  return UserProfileSectionValues.fromJson(section, values).isUnset;
}

/// A whole number, or null. `1990.0` is the same JSON number as `1990`.
int? _readInteger(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return null;
}

T? _enumByWireName<T>(
  List<T> values,
  Object? wireName,
  String Function(T value) wireNameOf,
) {
  for (final value in values) {
    if (wireNameOf(value) == wireName) {
      return value;
    }
  }
  return null;
}
