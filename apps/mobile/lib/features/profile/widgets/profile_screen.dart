import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/profile/user_profile.dart';
import '../../../domain/training/training_records.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../focus/controllers/focus_providers.dart';
import '../../settings/repositories/settings_repository.dart';
import '../controllers/profile_controller.dart';
import 'profile_section_editors.dart';

/// The User Profile under Account & app: the disclosure line for the current
/// mode, then one card per section, each opening that section's editor sheet.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const routeName = '/profile';

  static Key sectionCardKey(UserProfileSection section) =>
      Key('profile.card.${section.wireName}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final profile = ref.watch(profileControllerProvider).value;
    final focuses =
        ref.watch(activeFocusesProvider).value ?? const <FocusRecord>[];
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.base),
          children: [
            const ProfileDisclosureLine(),
            if (profile != null)
              for (final section in UserProfileSection.values) ...[
                const SizedBox(height: AppDimens.dense),
                _SectionCard(
                  key: sectionCardKey(section),
                  title: profileSectionTitle(l10n, section),
                  lines: _sectionLines(
                    l10n,
                    section,
                    profile,
                    focuses,
                    settings.unitSystem,
                  ),
                  onTap: () => showProfileSectionEditor(
                    context,
                    section: section,
                    profile: profile,
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

/// The DESIGN.md disclosure line: who can read the User Profile in the current
/// mode. The onboarding footer shows the same line.
class ProfileDisclosureLine extends ConsumerWidget {
  const ProfileDisclosureLine({super.key});

  static const textKey = Key('profile.disclosure');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final disclosure = ref.watch(profileDisclosureProvider);
    return Text(
      switch (disclosure.mode) {
        ProfileDisclosureMode.localOnly => l10n.profileDisclosureLocalOnly,
        ProfileDisclosureMode.synced =>
          l10n.profileDisclosureSynced(disclosure.host ?? ''),
      },
      key: textKey,
      style: context.textStyles.caption.copyWith(
        color: context.colors.textSecondary,
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.title,
    required this.lines,
    required this.onTap,
  });

  final String title;

  /// The section's values, one per line. Empty means *unset*.
  final List<String> lines;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyles = context.textStyles;
    return Material(
      color: colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: textStyles.h2),
                      const SizedBox(height: AppDimens.dense),
                      if (lines.isEmpty)
                        Text(
                          context.l10n.profileNotSet,
                          style: textStyles.body.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      for (final line in lines)
                        Text(
                          line,
                          style: textStyles.body,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.dense),
                Icon(Icons.chevron_right, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<String> _sectionLines(
  AppLocalizations l10n,
  UserProfileSection section,
  UserProfile profile,
  List<FocusRecord> focuses,
  UnitSystem unitSystem,
) {
  String line(String label, String value) => l10n.profileFieldValue(
        label,
        value,
      );

  switch (section) {
    case UserProfileSection.aboutYou:
      final sex = profile.sex;
      final birthYear = profile.birthYear;
      final height = profile.height;
      return [
        if (sex != null) line(l10n.profileFieldSex, profileSexLabel(l10n, sex)),
        if (birthYear != null) line(l10n.profileFieldBirthYear, '$birthYear'),
        if (height != null)
          line(
            l10n.profileFieldHeight,
            formatProfileHeight(l10n, height, unitSystem),
          ),
      ];
    case UserProfileSection.trainingGoals:
      final goals = profile.goals;
      return [
        if (goals != null)
          goals.isEmpty
              ? l10n.profileNone
              : goals.map((goal) => trainingGoalLabel(l10n, goal)).join(', '),
      ];
    case UserProfileSection.experience:
      final levels = profile.experienceLevels;
      if (levels == null) {
        return const <String>[];
      }
      if (levels.isEmpty) {
        return [l10n.profileNone];
      }
      // An entry whose Focus is archived is kept and hidden, so a Focus's
      // position in the user's order decides the lines, not the stored order.
      final levelsByFocus = {
        for (final entry in levels) entry.focusId: entry.level,
      };
      return [
        for (final focus in focuses)
          if (levelsByFocus[focus.id] case final level?)
            line(focus.name, experienceLevelLabel(l10n, level)),
      ];
    case UserProfileSection.trainingSetup:
      final equipment = profile.equipment;
      final days = profile.daysPerWeek;
      final minutes = profile.sessionMinutes;
      return [
        if (equipment != null)
          line(
            l10n.profileFieldEquipment,
            equipment.isEmpty
                ? l10n.profileNone
                : equipment.map(profileEquipmentLabel).join(', '),
          ),
        if (days != null) line(l10n.profileFieldDaysPerWeek, '$days'),
        if (minutes != null)
          line(
            l10n.profileFieldSessionLength,
            l10n.profileSessionMinutesValue(minutes),
          ),
      ];
    case UserProfileSection.healthLimitations:
      final text = profile.healthText;
      return [
        if (profile.healthNone ?? false) l10n.profileNone,
        if (text != null) text,
      ];
    case UserProfileSection.generalNotes:
      final text = profile.generalNotesText;
      return [if (text != null) text];
  }
}
