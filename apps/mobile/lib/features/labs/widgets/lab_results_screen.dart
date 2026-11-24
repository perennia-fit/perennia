import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/labs/lab_result.dart';
import '../../../domain/labs/lab_test_catalogue.generated.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../profile/widgets/profile_screen.dart';
import '../../protocols/widgets/protocols_lock_screen.dart';
import '../controllers/lab_results_controller.dart';
import 'lab_entry_sheet.dart';
import 'lab_result_row.dart';
import 'lab_test_detail_screen.dart';
import 'lab_test_picker.dart';

/// The Lab Results screen (docs/designs/lab-results.md, "The display"): the
/// Disclosure line, the general-ranges Profile line, the recognised Lab Tests
/// link, Add results, and the Lab Tests with results grouped by panel, with
/// "Other" last.
///
/// The screen wraps itself in [ProtocolsLockGate] rather than relying on its
/// route entry to do it, as the Protocols routes do: lab results share the
/// Protocols lock, and gating inside `build` means every path that reaches
/// this widget (a named route, a pushed route, a test host) is gated. The
/// content is a separate widget so nothing is read while locked.
class LabResultsScreen extends StatelessWidget {
  const LabResultsScreen({super.key});

  static const routeName = '/labs';

  static const addResultsButtonKey = Key('labs.results.addResults');
  static const profileLinkKey = Key('labs.results.profileLink');
  static const recognisedLinkKey = Key('labs.results.recognised');
  static const emptyKey = Key('labs.results.empty');
  static const otherHeaderKey = Key('labs.results.panel.other');

  static Key testRowKey(String key) => Key('labs.results.test.$key');

  static Key panelHeaderKey(String panel) => Key('labs.results.panel.$panel');

  @override
  Widget build(BuildContext context) {
    return const ProtocolsLockGate(child: _LabResultsScaffold());
  }
}

class _LabResultsScaffold extends ConsumerWidget {
  const _LabResultsScaffold();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.colors;
    final state = ref.watch(labResultsScreenProvider);
    final sections = state.value;

    final addResults = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.base,
        AppDimens.dense,
        AppDimens.base,
        AppDimens.dense,
      ),
      child: FilledButton.icon(
        key: LabResultsScreen.addResultsButtonKey,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppDimens.touchTarget),
        ),
        icon: const Icon(Icons.add),
        label: Text(l10n.labResultsAddResults),
        onPressed: () => unawaited(showLabEntrySheet(context)),
      ),
    );

    final children = <Widget>[
      const Padding(
        padding: EdgeInsets.fromLTRB(
          AppDimens.base,
          AppDimens.base,
          AppDimens.base,
          AppDimens.dense,
        ),
        child: ProfileDisclosureLine(),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.base),
        child: Text(
          l10n.labResultsProfileLine,
          style: context.textStyles.body.copyWith(color: colors.textSecondary),
        ),
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.dense / 2),
          child: TextButton(
            key: LabResultsScreen.profileLinkKey,
            // Signal Cyan text is below AA on the light ground.
            style: TextButton.styleFrom(
              foregroundColor: colors.textPrimary,
              minimumSize: const Size(
                AppDimens.touchTarget,
                AppDimens.touchTarget,
              ),
            ),
            onPressed: () => unawaited(
              Navigator.of(context).pushNamed<void>(ProfileScreen.routeName),
            ),
            child: Text(l10n.labResultsProfileLink),
          ),
        ),
      ),
      ListTile(
        key: LabResultsScreen.recognisedLinkKey,
        minTileHeight: AppDimens.touchTarget,
        title: Text(
          l10n.labTestPickerRecognisedTitle(labTestCatalogue.length),
          style: context.textStyles.body.copyWith(color: colors.textPrimary),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(showLabTestPicker(context, readOnly: true)),
      ),
      if (state.hasError && sections == null)
        Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: Text(
            l10n.labResultsUnavailable,
            style: context.textStyles.body.copyWith(
              color: colors.textSecondary,
            ),
          ),
        )
      else if (sections == null)
        const SizedBox.shrink()
      else if (sections.isEmpty) ...[
        Padding(
          key: LabResultsScreen.emptyKey,
          padding: const EdgeInsets.fromLTRB(
            AppDimens.base,
            AppDimens.base,
            AppDimens.base,
            0,
          ),
          child: Text(
            l10n.labResultsEmpty,
            style: context.textStyles.body.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
        addResults,
      ] else ...[
        addResults,
        for (final section in sections) ...[
          _SectionHeader(
            key: section.panel == null
                ? LabResultsScreen.otherHeaderKey
                : LabResultsScreen.panelHeaderKey(section.panel!),
            title: section.panel ?? l10n.labResultsOtherPanel,
          ),
          for (final summary in section.tests) _LabTestRow(summary: summary),
        ],
      ],
      const SizedBox(height: AppDimens.base),
    ];

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.chrome,
        title: Text(l10n.labResultsTitle),
      ),
      body: SafeArea(child: ListView(children: children)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.base,
        AppDimens.base,
        AppDimens.base,
        AppDimens.dense / 2,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: context.textStyles.label.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// One Lab Test with results: its name, the latest collapsed result as
/// entered with its unit, and that result's collection date.
class _LabTestRow extends StatelessWidget {
  const _LabTestRow({required this.summary});

  final LabTestSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final latest = summary.latest;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = DateFormat.yMMMd(locale)
        .format(collectedLocal(latest.lab.collected).dateTime);
    final unit =
        latest.enteredUnit.trim().isEmpty ? summary.unit : latest.enteredUnit;
    return ListTile(
      key: LabResultsScreen.testRowKey(summary.labTestKey),
      minTileHeight: AppDimens.touchTarget,
      title: Text(
        summary.name,
        style: context.textStyles.body.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        l10n.labResultsLatest(
          labResultValueText(l10n, latest.entered, unit),
          date,
        ),
        style: context.textStyles.caption.copyWith(
          color: colors.textSecondary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(
        Navigator.of(context).pushNamed<void>(
          LabTestDetailScreen.routeName,
          arguments: summary.labTestKey,
        ),
      ),
    );
  }
}
