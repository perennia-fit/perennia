import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/profile/user_profile.dart';
import '../../../domain/profile/user_profile_validation.dart';
import '../../../domain/training/training_dimensions.dart';
import '../../../domain/training/training_records.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../focus/controllers/focus_providers.dart';
import '../../settings/repositories/settings_repository.dart';
import '../controllers/profile_controller.dart';

/// Keys for the editor sheet's chrome and the soft-warning dialog.
abstract final class ProfileEditorKeys {
  static const saveButton = Key('profile.editor.save');
  static const errors = Key('profile.editor.errors');
  static const warningDialog = Key('profile.warning.dialog');
  static const warningEditButton = Key('profile.warning.edit');
  static const warningSaveAnywayButton = Key('profile.warning.saveAnyway');
  static const healthTextField = Key('profile.health.text');
  static const healthNoneSwitch = Key('profile.health.none');
  static const generalNotesTextField = Key('profile.generalNotes.text');
}

String profileSectionTitle(AppLocalizations l10n, UserProfileSection section) {
  return switch (section) {
    UserProfileSection.aboutYou => l10n.profileSectionAboutYou,
    UserProfileSection.trainingGoals => l10n.profileSectionTrainingGoals,
    UserProfileSection.experience => l10n.profileSectionExperience,
    UserProfileSection.trainingSetup => l10n.profileSectionTrainingSetup,
    UserProfileSection.healthLimitations => l10n.profileSectionHealth,
    UserProfileSection.generalNotes => l10n.profileSectionGeneralNotes,
  };
}

String profileSexLabel(AppLocalizations l10n, ProfileSex sex) {
  return switch (sex) {
    ProfileSex.female => l10n.profileSexFemale,
    ProfileSex.male => l10n.profileSexMale,
  };
}

String trainingGoalLabel(AppLocalizations l10n, TrainingGoalId goal) {
  return switch (goal) {
    TrainingGoalId.longevity => l10n.profileGoalLongevity,
    TrainingGoalId.strength => l10n.profileGoalStrength,
    TrainingGoalId.muscleGain => l10n.profileGoalMuscleGain,
    TrainingGoalId.bodyComposition => l10n.profileGoalBodyComposition,
    TrainingGoalId.endurancePerformance => l10n.profileGoalEndurance,
    TrainingGoalId.mobility => l10n.profileGoalMobility,
    TrainingGoalId.generalFitness => l10n.profileGoalGeneralFitness,
  };
}

String experienceLevelLabel(AppLocalizations l10n, ExperienceLevel level) {
  return switch (level) {
    ExperienceLevel.beginner => l10n.profileLevelBeginner,
    ExperienceLevel.intermediate => l10n.profileLevelIntermediate,
    ExperienceLevel.advanced => l10n.profileLevelAdvanced,
  };
}

String _experienceLevelMeaning(AppLocalizations l10n, ExperienceLevel level) {
  return switch (level) {
    ExperienceLevel.beginner => l10n.profileLevelBeginnerMeaning,
    ExperienceLevel.intermediate => l10n.profileLevelIntermediateMeaning,
    ExperienceLevel.advanced => l10n.profileLevelAdvancedMeaning,
  };
}

/// A registry id's label, or the id itself: an id outside the registry is kept
/// and shown as it is, as CONTEXT.md allows for Equipment. It goes through
/// neither `ExerciseEquipment.fromId`, which throws on a blank id, nor its
/// humanized label, because a stored row can hold anything.
String profileEquipmentLabel(String id) {
  for (final equipment in ExerciseEquipment.known) {
    if (equipment.id == id) {
      return equipment.label;
    }
  }
  return id;
}

/// [height] in the user's unit system. Conversion happens on read only, so this
/// never touches what is stored.
String formatProfileHeight(
  AppLocalizations l10n,
  ProfileHeight height,
  UnitSystem unitSystem,
) {
  final texts = _HeightTexts.of(height, unitSystem);
  return switch (unitSystem) {
    UnitSystem.metric => l10n.profileHeightCentimetresValue(texts.centimetres),
    UnitSystem.imperial => l10n.profileHeightFeetInchesValue(
        texts.feet,
        texts.inches,
      ),
  };
}

/// The one place a validation issue becomes copy. Each string equals the shared
/// module's `message` for the rule; the ARB holds it so it can be translated.
/// The age and height placeholders come from the issue's `placeholder`.
String profileValidationMessage(
  AppLocalizations l10n,
  UserProfileValidationIssue issue,
) {
  switch (issue.rule) {
    case 'birth_year.future':
      return l10n.profileValidationBirthYearFuture;
    case 'birth_year.too_old':
      return l10n.profileValidationBirthYearTooOld;
    case 'birth_year.improbable_age':
      return l10n.profileValidationBirthYearImprobable(
        issue.placeholder! as int,
      );
    case 'height.non_positive':
      return l10n.profileValidationHeightNonPositive;
    case 'height.too_tall':
      return l10n.profileValidationHeightTooTall;
    case 'height.unit':
      return l10n.profileValidationHeightUnit;
    case 'height.improbable':
      return l10n.profileValidationHeightImprobable(
        issue.placeholder! as String,
      );
    case 'days_per_week.range':
      return l10n.profileValidationDaysPerWeekRange;
    case 'session_minutes.range':
      return l10n.profileValidationSessionMinutesRange;
    case 'session_minutes.improbable':
      return l10n.profileValidationSessionMinutesImprobable;
    case 'goals.unknown':
      return l10n.profileValidationGoalsUnknown;
    case 'goals.duplicate' || 'equipment.duplicate':
      return l10n.profileValidationDuplicate;
    case 'equipment.invalid':
      return l10n.profileValidationEquipmentInvalid;
    case 'levels.unknown_level':
      return l10n.profileValidationLevelsUnknownLevel;
    case 'levels.invalid_focus':
      return l10n.profileValidationLevelsInvalidFocus;
    case 'levels.duplicate_focus':
      return l10n.profileValidationLevelsDuplicateFocus;
    case 'text.too_long':
      final limit = issue.limit;
      return limit is int
          ? l10n.profileValidationTextTooLong(limit)
          : issue.message;
    case 'sex.unknown':
      return l10n.profileValidationSexUnknown;
  }
  return issue.message;
}

/// Asks the user to confirm soft warnings. True means **Save anyway**; anything
/// else returns to the field. Shaped like `BodyTrackerScreen`'s dialog for an
/// improbable reading.
Future<bool> showProfileSoftWarningDialog(
  BuildContext context,
  List<String> messages,
) async {
  final l10n = context.l10n;
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            key: ProfileEditorKeys.warningDialog,
            scrollable: true,
            title: Text(l10n.profileWarningTitle),
            content: Text(messages.join('\n')),
            actions: [
              TextButton(
                key: ProfileEditorKeys.warningEditButton,
                style: TextButton.styleFrom(
                  foregroundColor: dialogContext.colors.textPrimary,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.profileWarningEdit),
              ),
              FilledButton(
                key: ProfileEditorKeys.warningSaveAnywayButton,
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.profileWarningSaveAnyway),
              ),
            ],
          );
        },
      ) ??
      false;
}

/// Opens [section]'s editor sheet over the current values in [profile].
Future<void> showProfileSectionEditor(
  BuildContext context, {
  required UserProfileSection section,
  required UserProfile profile,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _ProfileEditorSheet(section: section, profile: profile),
  );
}

/// The sheet chrome: title, one section's fields, errors and Save. The fields
/// report the changes to save; everything else about a save happens here.
class _ProfileEditorSheet extends ConsumerStatefulWidget {
  const _ProfileEditorSheet({required this.section, required this.profile});

  final UserProfileSection section;
  final UserProfile profile;

  @override
  ConsumerState<_ProfileEditorSheet> createState() =>
      _ProfileEditorSheetState();
}

class _ProfileEditorSheetState extends ConsumerState<_ProfileEditorSheet> {
  Map<String, Object?> _changes = const <String, Object?>{};
  List<String> _errors = const <String>[];
  bool _saving = false;

  void _onChanged(Map<String, Object?> changes) {
    setState(() {
      _changes = changes;
      _errors = const <String>[];
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      if (await _trySave() && mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// Whether the sheet is done. False keeps it open, on a hard error or on
  /// **Edit**.
  Future<bool> _trySave() async {
    final l10n = context.l10n;
    final controller = ref.read(profileControllerProvider.notifier);
    final check = await controller.save(widget.section, _changes);
    if (!mounted) {
      return false;
    }
    String message(UserProfileValidationIssue issue) =>
        profileValidationMessage(l10n, issue);
    if (check.errors.isNotEmpty) {
      setState(() => _errors = check.errors.map(message).toList());
      return false;
    }
    if (check.warnings.isEmpty) {
      return true;
    }
    final confirmed = await showProfileSoftWarningDialog(
      context,
      check.warnings.map(message).toList(),
    );
    if (!confirmed) {
      return false;
    }
    await controller.saveAnyway(widget.section, _changes);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textStyles = context.textStyles;
    final profile = widget.profile;
    final unitSystem =
        (ref.watch(settingsControllerProvider).value ?? AppSettings.defaults)
            .unitSystem;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppDimens.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    profileSectionTitle(l10n, widget.section),
                    style: textStyles.h2,
                  ),
                  const SizedBox(height: AppDimens.base),
                  switch (widget.section) {
                    UserProfileSection.aboutYou => AboutYouFields(
                        initial: profile.aboutYou,
                        unitSystem: unitSystem,
                        onChanged: _onChanged,
                      ),
                    UserProfileSection.trainingGoals => TrainingGoalsFields(
                        initial: profile.trainingGoals,
                        onChanged: _onChanged,
                      ),
                    UserProfileSection.experience => ExperienceFields(
                        initial: profile.experience,
                        onChanged: _onChanged,
                      ),
                    UserProfileSection.trainingSetup => TrainingSetupFields(
                        initial: profile.trainingSetup,
                        onChanged: _onChanged,
                      ),
                    UserProfileSection.healthLimitations =>
                      _HealthLimitationsFields(
                        initial: profile.healthLimitations,
                        onChanged: _onChanged,
                      ),
                    UserProfileSection.generalNotes => _GeneralNotesFields(
                        initial: profile.generalNotes,
                        onChanged: _onChanged,
                      ),
                  },
                ],
              ),
            ),
          ),
          if (_errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.base,
                AppDimens.dense,
                AppDimens.base,
                0,
              ),
              child: ProfileErrorLines(
                  key: ProfileEditorKeys.errors, lines: _errors),
            ),
          Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: FilledButton(
              key: ProfileEditorKeys.saveButton,
              style: saveFormButtonStyle(context),
              onPressed: _saving ? null : _save,
              child: Text(l10n.profileSave),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bar Red is for destruction only, so a rejected value reads from the icon and
/// the words.
class ProfileErrorLines extends StatelessWidget {
  const ProfileErrorLines({super.key, required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: AppDimens.dense),
          Expanded(
            child: Text(lines.join('\n'), style: context.textStyles.body),
          ),
        ],
      ),
    );
  }
}

/// About you's fields, shared with onboarding. [onChanged] gets only what the
/// user changed: a stored height is converted for display, and sending it back
/// unedited would rewrite a value stored as entered in the other unit.
class AboutYouFields extends StatefulWidget {
  const AboutYouFields({
    super.key,
    required this.initial,
    required this.unitSystem,
    required this.onChanged,
  });

  static const sexKey = Key('profile.aboutYou.sex');
  static const birthYearKey = Key('profile.aboutYou.birthYear');
  static const heightCentimetresKey = Key('profile.aboutYou.heightCm');
  static const heightFeetKey = Key('profile.aboutYou.heightFeet');
  static const heightInchesKey = Key('profile.aboutYou.heightInches');

  final AboutYouValues? initial;
  final UnitSystem unitSystem;
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  State<AboutYouFields> createState() => _AboutYouFieldsState();
}

class _AboutYouFieldsState extends State<AboutYouFields> {
  final _centimetres = TextEditingController();
  final _feet = TextEditingController();
  final _inches = TextEditingController();
  late ProfileSex? _sex = widget.initial?.sex;
  late int? _birthYear = widget.initial?.birthYear;
  late _HeightTexts _unedited = _HeightTexts.ofNullable(
    widget.initial?.height,
    widget.unitSystem,
  );

  @override
  void initState() {
    super.initState();
    _showHeight(_unedited);
  }

  @override
  void didUpdateWidget(AboutYouFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitSystem == widget.unitSystem) {
      return;
    }
    // Onboarding has the unit control on the same screen. A height the user
    // typed follows the unit; an untouched one goes back to the stored value.
    final wasEdited = _heightEdited(oldWidget.unitSystem);
    final entered = _enteredHeight(oldWidget.unitSystem);
    _unedited = _HeightTexts.ofNullable(
      widget.initial?.height,
      widget.unitSystem,
    );
    _showHeight(
      wasEdited
          ? _HeightTexts.ofNullable(entered, widget.unitSystem)
          : _unedited,
    );
  }

  @override
  void dispose() {
    _centimetres.dispose();
    _feet.dispose();
    _inches.dispose();
    super.dispose();
  }

  void _showHeight(_HeightTexts texts) {
    _centimetres.text = texts.centimetres;
    _feet.text = texts.feet;
    _inches.text = texts.inches;
  }

  bool _heightEdited(UnitSystem unitSystem) {
    return switch (unitSystem) {
      UnitSystem.metric => _centimetres.text != _unedited.centimetres,
      UnitSystem.imperial =>
        _feet.text != _unedited.feet || _inches.text != _unedited.inches,
    };
  }

  /// What the fields say: centimetres, or feet and inches as total inches, each
  /// to one decimal place. Null when they are empty.
  ProfileHeight? _enteredHeight(UnitSystem unitSystem) {
    switch (unitSystem) {
      case UnitSystem.metric:
        final centimetres = _parseDecimal(_centimetres.text);
        return centimetres == null
            ? null
            : ProfileHeight(
                value: _roundToTenth(centimetres),
                unit: HeightUnit.cm,
              );
      case UnitSystem.imperial:
        final feet = _parseDecimal(_feet.text);
        final inches = _parseDecimal(_inches.text);
        if (feet == null && inches == null) {
          return null;
        }
        return ProfileHeight(
          value: _roundToTenth((feet ?? 0) * 12 + (inches ?? 0)),
          unit: HeightUnit.inch,
        );
    }
  }

  void _report() {
    final initial = widget.initial;
    widget.onChanged(<String, Object?>{
      if (_sex != initial?.sex) 'sex': _sex?.wireName,
      if (_birthYear != initial?.birthYear) 'birth_year': _birthYear,
      if (_heightEdited(widget.unitSystem))
        'height': _enteredHeight(widget.unitSystem)?.toJson(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currentYear = DateTime.now().year;
    final years = <int>{
      for (var year = currentYear;
          year >=
              currentYear - UserProfileValidationLimits.birthYearMaxAgeYears;
          year -= 1)
        year,
      // A pulled row can hold a year outside the range, and the dropdown needs
      // its current value among its items.
      if (widget.initial?.birthYear case final stored?) stored,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.profileFieldSex, style: context.textStyles.caption),
        const SizedBox(height: AppDimens.dense),
        Semantics(
          label: l10n.profileFieldSex,
          child: SegmentedButton<ProfileSex?>(
            key: AboutYouFields.sexKey,
            selected: <ProfileSex?>{_sex},
            segments: [
              for (final sex in ProfileSex.values)
                ButtonSegment<ProfileSex?>(
                  value: sex,
                  label: Text(profileSexLabel(l10n, sex)),
                ),
              ButtonSegment<ProfileSex?>(
                value: null,
                label: Text(l10n.profileNotSet),
              ),
            ],
            onSelectionChanged: (selection) {
              setState(() => _sex = selection.single);
              _report();
            },
          ),
        ),
        const SizedBox(height: AppDimens.base),
        DropdownButtonFormField<int?>(
          key: AboutYouFields.birthYearKey,
          initialValue: _birthYear,
          isExpanded: true,
          menuMaxHeight: MediaQuery.sizeOf(context).height * 0.6,
          decoration: _fieldDecoration(label: l10n.profileFieldBirthYear),
          items: [
            DropdownMenuItem<int?>(
                value: null, child: Text(l10n.profileNotSet)),
            for (final year in years)
              DropdownMenuItem<int?>(value: year, child: Text('$year')),
          ],
          onChanged: (year) {
            setState(() => _birthYear = year);
            _report();
          },
        ),
        const SizedBox(height: AppDimens.base),
        if (widget.unitSystem == UnitSystem.metric)
          TextField(
            key: AboutYouFields.heightCentimetresKey,
            controller: _centimetres,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_decimalFormatter(wholeDigits: 3)],
            decoration: _fieldDecoration(
              label: l10n.profileFieldHeightCentimetres,
              hint: l10n.profileNotSet,
            ),
            onChanged: (_) => _report(),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: AboutYouFields.heightFeetKey,
                  controller: _feet,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: _fieldDecoration(
                    label: l10n.profileFieldHeightFeet,
                    hint: l10n.profileNotSet,
                  ),
                  onChanged: (_) => _report(),
                ),
              ),
              const SizedBox(width: AppDimens.dense),
              Expanded(
                child: TextField(
                  key: AboutYouFields.heightInchesKey,
                  controller: _inches,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [_decimalFormatter(wholeDigits: 2)],
                  decoration: _fieldDecoration(
                    label: l10n.profileFieldHeightInches,
                  ),
                  onChanged: (_) => _report(),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Training Goals' fields, shared with onboarding. Selecting nothing is *unset*;
/// only **None** says the user has no goals to list.
class TrainingGoalsFields extends StatefulWidget {
  const TrainingGoalsFields({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  static Key goalKey(TrainingGoalId goal) =>
      Key('profile.goals.${goal.wireName}');
  static const noneKey = Key('profile.goals.none');

  final TrainingGoalsValues? initial;
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  State<TrainingGoalsFields> createState() => _TrainingGoalsFieldsState();
}

class _TrainingGoalsFieldsState extends State<TrainingGoalsFields> {
  late final Set<TrainingGoalId> _selected = {...?widget.initial?.goals};
  late bool _none = widget.initial?.goals?.isEmpty ?? false;

  void _report() {
    final current = _selectionValue(_none, _selected);
    widget.onChanged(<String, Object?>{
      if (!_sameSelection(current, widget.initial?.goals))
        'goals': current?.map((goal) => goal.wireName).toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: AppDimens.dense,
      children: [
        for (final goal in TrainingGoalId.values)
          FilterChip(
            key: TrainingGoalsFields.goalKey(goal),
            label: Text(trainingGoalLabel(l10n, goal)),
            selected: _selected.contains(goal),
            onSelected: (selected) {
              setState(() {
                selected ? _selected.add(goal) : _selected.remove(goal);
                _none = false;
              });
              _report();
            },
          ),
        FilterChip(
          key: TrainingGoalsFields.noneKey,
          label: Text(l10n.profileNone),
          selected: _none,
          onSelected: (selected) {
            setState(() {
              _none = selected;
              _selected.clear();
            });
            _report();
          },
        ),
      ],
    );
  }
}

/// Experience's fields, shared with onboarding: one level selector per active
/// Focus. A save replaces the whole list, so entries for Focuses not shown here
/// (archived, or not on this device yet) are carried along. Only **None** drops
/// them.
class ExperienceFields extends ConsumerStatefulWidget {
  const ExperienceFields({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  static Key levelKey(String focusId, ExperienceLevel? level) =>
      Key('profile.experience.$focusId.${level?.wireName ?? 'unset'}');
  static const noneKey = Key('profile.experience.none');

  final ExperienceValues? initial;
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  ConsumerState<ExperienceFields> createState() => _ExperienceFieldsState();
}

class _ExperienceFieldsState extends ConsumerState<ExperienceFields> {
  late final Map<String, ExperienceLevel> _levels = {
    for (final entry in widget.initial?.levels ?? const <ExperienceEntry>[])
      entry.focusId: entry.level,
  };
  late bool _none = widget.initial?.levels?.isEmpty ?? false;

  void _report() {
    final entries = _levels.entries.map(
      (entry) => ExperienceEntry(focusId: entry.key, level: entry.value),
    );
    final current = _selectionValue(_none, entries);
    widget.onChanged(<String, Object?>{
      if (!_sameSelection(current, widget.initial?.levels))
        'levels': current?.map((entry) => entry.toJson()).toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final focuses =
        ref.watch(activeFocusesProvider).value ?? const <FocusRecord>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final focus in focuses) ...[
          _FocusLevelRow(
            focus: focus,
            level: _none ? null : _levels[focus.id],
            onChanged: (level) {
              setState(() {
                if (level == null) {
                  _levels.remove(focus.id);
                } else {
                  _levels[focus.id] = level;
                }
                _none = false;
              });
              _report();
            },
          ),
          const SizedBox(height: AppDimens.dense),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilterChip(
            key: ExperienceFields.noneKey,
            label: Text(l10n.profileNone),
            selected: _none,
            onSelected: (selected) {
              setState(() {
                _none = selected;
                if (selected) {
                  // The hidden entries stay in the map, so turning **None**
                  // back off before saving loses nothing. While it is on, the
                  // save writes `[]` whatever the map holds.
                  for (final focus in focuses) {
                    _levels.remove(focus.id);
                  }
                }
              });
              _report();
            },
          ),
        ),
      ],
    );
  }
}

class _FocusLevelRow extends StatelessWidget {
  const _FocusLevelRow({
    required this.focus,
    required this.level,
    required this.onChanged,
  });

  final FocusRecord focus;
  final ExperienceLevel? level;
  final ValueChanged<ExperienceLevel?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final level = this.level;
    return Semantics(
      container: true,
      label: focus.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(focus.name, style: context.textStyles.label),
          Wrap(
            spacing: AppDimens.dense,
            children: [
              for (final option in <ExperienceLevel?>[
                ...ExperienceLevel.values,
                null,
              ])
                ChoiceChip(
                  key: ExperienceFields.levelKey(focus.id, option),
                  label: Text(
                    option == null
                        ? l10n.profileNotSet
                        : experienceLevelLabel(l10n, option),
                  ),
                  selected: option == level,
                  onSelected: (_) => onChanged(option),
                ),
            ],
          ),
          if (level != null)
            Text(
              _experienceLevelMeaning(l10n, level),
              style: context.textStyles.caption.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// Training setup's fields, shared with onboarding. **None** is the only way to
/// say "bodyweight only", so the registry's `bodyweight` isn't offered, and ids
/// outside what is offered stay as extra selected chips.
class TrainingSetupFields extends StatefulWidget {
  const TrainingSetupFields({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  static Key equipmentKey(String id) => Key('profile.equipment.$id');
  static const equipmentNoneKey = Key('profile.equipment.none');
  static const daysValueKey = Key('profile.days.value');
  static const daysDecreaseKey = Key('profile.days.decrease');
  static const daysIncreaseKey = Key('profile.days.increase');
  static const sessionMinutesKey = Key('profile.sessionMinutes');

  final TrainingSetupValues? initial;
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  State<TrainingSetupFields> createState() => _TrainingSetupFieldsState();
}

class _TrainingSetupFieldsState extends State<TrainingSetupFields> {
  late final Set<String> _equipment = {...?widget.initial?.equipment};
  late bool _none = widget.initial?.equipment?.isEmpty ?? false;
  late int? _days = widget.initial?.daysPerWeek;
  late final TextEditingController _minutes = TextEditingController(
    text: widget.initial?.sessionMinutes?.toString() ?? '',
  );

  late final List<String> _offered = [
    for (final equipment in ExerciseEquipment.known)
      if (equipment != ExerciseEquipment.bodyweight) equipment.id,
    ...?widget.initial?.equipment?.where(
      (id) =>
          id == ExerciseEquipment.bodyweight.id ||
          !ExerciseEquipment.known.any((equipment) => equipment.id == id),
    ),
  ];

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _report() {
    final initial = widget.initial;
    final equipment = _selectionValue(_none, _equipment);
    final minutes = int.tryParse(_minutes.text);
    widget.onChanged(<String, Object?>{
      if (!_sameSelection(equipment, initial?.equipment))
        'equipment': equipment?.toList(),
      if (_days != initial?.daysPerWeek) 'days_per_week': _days,
      if (minutes != initial?.sessionMinutes) 'session_minutes': minutes,
    });
  }

  void _setDays(int? days) {
    setState(() => _days = days);
    _report();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textStyles = context.textStyles;
    final days = _days;
    const minDays = UserProfileValidationLimits.daysPerWeekMin;
    const maxDays = UserProfileValidationLimits.daysPerWeekMax;
    final stepperShape = IconButton.styleFrom(
      minimumSize: const Size.square(AppDimens.touchTarget),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardMd),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.profileFieldEquipment, style: textStyles.caption),
        Wrap(
          spacing: AppDimens.dense,
          children: [
            for (final id in _offered)
              FilterChip(
                key: TrainingSetupFields.equipmentKey(id),
                label: Text(profileEquipmentLabel(id)),
                selected: _equipment.contains(id),
                onSelected: (selected) {
                  setState(() {
                    selected ? _equipment.add(id) : _equipment.remove(id);
                    _none = false;
                  });
                  _report();
                },
              ),
            FilterChip(
              key: TrainingSetupFields.equipmentNoneKey,
              label: Text(l10n.profileNone),
              selected: _none,
              onSelected: (selected) {
                setState(() {
                  _none = selected;
                  _equipment.clear();
                });
                _report();
              },
            ),
          ],
        ),
        const SizedBox(height: AppDimens.base),
        Text(l10n.profileFieldDaysPerWeek, style: textStyles.caption),
        const SizedBox(height: AppDimens.dense),
        Row(
          children: [
            IconButton.outlined(
              key: TrainingSetupFields.daysDecreaseKey,
              tooltip: l10n.profileDaysPerWeekDecrease,
              style: stepperShape,
              onPressed: days == null
                  ? null
                  : () => _setDays(
                        days <= minDays
                            ? null
                            : (days - 1).clamp(minDays, maxDays),
                      ),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Text(
                days?.toString() ?? l10n.profileNotSet,
                key: TrainingSetupFields.daysValueKey,
                textAlign: TextAlign.center,
                style: textStyles.numeralRow,
              ),
            ),
            IconButton.outlined(
              key: TrainingSetupFields.daysIncreaseKey,
              tooltip: l10n.profileDaysPerWeekIncrease,
              style: stepperShape,
              onPressed: (days ?? 0) >= maxDays
                  ? null
                  : () => _setDays((days ?? 0) + 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.base),
        TextField(
          key: TrainingSetupFields.sessionMinutesKey,
          controller: _minutes,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          decoration: _fieldDecoration(
            label: l10n.profileFieldSessionMinutes,
            hint: l10n.profileNotSet,
          ),
          onChanged: (_) => _report(),
        ),
      ],
    );
  }
}

class _HealthLimitationsFields extends StatefulWidget {
  const _HealthLimitationsFields({
    required this.initial,
    required this.onChanged,
  });

  final HealthLimitationsValues? initial;
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  State<_HealthLimitationsFields> createState() =>
      _HealthLimitationsFieldsState();
}

class _HealthLimitationsFieldsState extends State<_HealthLimitationsFields> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial?.text ?? '',
  );
  late bool _none = widget.initial?.none ?? false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _report() {
    final text = _storedText(_text.text);
    final changed = text != widget.initial?.text ||
        _none != (widget.initial?.none ?? false);
    widget.onChanged(<String, Object?>{
      if (changed) ...{'text': text, 'none': _none},
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CappedTextField(
          fieldKey: ProfileEditorKeys.healthTextField,
          controller: _text,
          label: l10n.profileSectionHealth,
          limit: UserProfileValidationLimits.healthLimitationsTextMaxLength,
          onChanged: (text) {
            setState(() {
              if (_storedText(text) != null) {
                _none = false;
              }
            });
            _report();
          },
        ),
        SwitchListTile(
          key: ProfileEditorKeys.healthNoneSwitch,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.profileNone),
          value: _none,
          onChanged: (none) {
            setState(() {
              _none = none;
              if (none) {
                _text.clear();
              }
            });
            _report();
          },
        ),
        _EditorLine(l10n.profileHealthMedicationsLine),
        const SizedBox(height: AppDimens.dense),
        _EditorLine(l10n.profileAgentHistoryLine),
      ],
    );
  }
}

class _GeneralNotesFields extends StatefulWidget {
  const _GeneralNotesFields({required this.initial, required this.onChanged});

  final GeneralNotesValues? initial;
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  State<_GeneralNotesFields> createState() => _GeneralNotesFieldsState();
}

class _GeneralNotesFieldsState extends State<_GeneralNotesFields> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial?.text ?? '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CappedTextField(
          fieldKey: ProfileEditorKeys.generalNotesTextField,
          controller: _text,
          label: l10n.profileSectionGeneralNotes,
          limit: UserProfileValidationLimits.generalNotesTextMaxLength,
          onChanged: (value) {
            final text = _storedText(value);
            widget.onChanged(<String, Object?>{
              if (text != widget.initial?.text) 'text': text,
            });
          },
        ),
        _EditorLine(l10n.profileAgentHistoryLine),
      ],
    );
  }
}

/// A free-text field with a counter against its cap.
///
/// The counter is built here because the validator's cap is in UTF-16 code units
/// (String `.length`), while `TextField.maxLength`'s counter and enforcement
/// count grapheme clusters: an astral character would read as 1 here and 2 in
/// the rule. Going over the cap is allowed while typing, so a paste is not cut
/// short; Save reports `text.too_long`.
class _CappedTextField extends StatelessWidget {
  const _CappedTextField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.limit,
    required this.onChanged,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final int limit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final count = controller.text.length;
        return TextField(
          key: fieldKey,
          controller: controller,
          minLines: 3,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: _fieldDecoration(label: label).copyWith(
            alignLabelWithHint: true,
            counter: Text(
              l10n.profileCharacterCount(count, limit),
              semanticsLabel: l10n.profileCharacterCountSemantics(count, limit),
              style: context.textStyles.caption.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
          onChanged: onChanged,
        );
      },
    );
  }
}

class _EditorLine extends StatelessWidget {
  const _EditorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: context.textStyles.caption.copyWith(
        color: context.colors.textSecondary,
      ),
    );
  }
}

/// DESIGN.md forms have no floating labels, so the label stays above the field.
InputDecoration _fieldDecoration({required String label, String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    floatingLabelBehavior: FloatingLabelBehavior.always,
  );
}

/// The value a multi-select stands for: `[]` for **None**, null when nothing is
/// selected, otherwise the selection. Only **None** may write an empty list.
Iterable<T>? _selectionValue<T>(bool none, Iterable<T> selected) {
  if (none) {
    return Iterable<T>.empty();
  }
  return selected.isEmpty ? null : selected;
}

/// Whether two values of an unordered list say the same thing. Null (*unset*)
/// and empty (*none*) differ.
bool _sameSelection<T>(Iterable<T>? a, Iterable<T>? b) {
  if (a == null || b == null) {
    return a == null && b == null;
  }
  final setA = a.toSet();
  return setA.length == b.length && setA.containsAll(b);
}

/// Text as entered, or null when there is nothing in it.
String? _storedText(String text) => text.trim().isEmpty ? null : text;

double? _parseDecimal(String text) {
  return double.tryParse(text.replaceAll(',', '.'));
}

double _roundToTenth(double value) => (value * 10).round() / 10;

String _formatTenths(int tenths) {
  return tenths % 10 == 0
      ? '${tenths ~/ 10}'
      : '${tenths ~/ 10}.${tenths % 10}';
}

/// Digits with at most one decimal place.
TextInputFormatter _decimalFormatter({required int wholeDigits}) {
  final allowed = RegExp('^\\d{0,$wholeDigits}([.,]\\d?)?');
  return TextInputFormatter.withFunction((oldValue, newValue) {
    return allowed.stringMatch(newValue.text) == newValue.text
        ? newValue
        : oldValue;
  });
}

/// A height as the editor's fields and the card show it, converted on read at
/// exactly 2.54 cm per inch. Feet and inches are split after rounding, so a value
/// can't read as 5 ft 12 in.
class _HeightTexts {
  const _HeightTexts({
    required this.centimetres,
    required this.feet,
    required this.inches,
  });

  factory _HeightTexts.of(ProfileHeight height, UnitSystem unitSystem) {
    switch (unitSystem) {
      case UnitSystem.metric:
        return _HeightTexts(
          centimetres: _formatTenths((height.inCentimetres * 10).round()),
          feet: '',
          inches: '',
        );
      case UnitSystem.imperial:
        final tenths = (height.inCentimetres / centimetresPerInch * 10).round();
        return _HeightTexts(
          centimetres: '',
          feet: '${tenths ~/ 120}',
          inches: _formatTenths(tenths % 120),
        );
    }
  }

  factory _HeightTexts.ofNullable(
    ProfileHeight? height,
    UnitSystem unitSystem,
  ) {
    return height == null
        ? const _HeightTexts(centimetres: '', feet: '', inches: '')
        : _HeightTexts.of(height, unitSystem);
  }

  final String centimetres;
  final String feet;
  final String inches;
}
