import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/labs/lab_test_catalogue.generated.dart';
import '../../../l10n/l10n.dart';
import '../../activity/undo_conflict_message.dart';
import '../../../theme/theme.dart';
import '../../protocols/widgets/protocols_lock_screen.dart';
import '../controllers/lab_results_providers.dart';
import '../controllers/lab_test_detail_controller.dart';
import 'lab_result_row.dart';

/// One Lab Test's collapsed results, newest first, each dated from
/// `lab.collected` (docs/designs/lab-results.md, "The display"), with
/// archive.
///
/// Wrapped in [ProtocolsLockGate] inside its own `build`, as
/// the Lab Results screen is, so every path to it is gated; the archive
/// confirmation sits behind [ProtocolsLockSheetGuard].
class LabTestDetailScreen extends StatelessWidget {
  const LabTestDetailScreen({super.key, required this.labTestKey});

  /// The route argument is the Lab Test key, a `String`.
  static const routeName = '/labs/test';

  static const archiveConfirmKey = Key('labs.detail.archiveConfirm');
  static const emptyKey = Key('labs.detail.empty');
  static const archivedSnackBarKey = Key('labs.detail.archivedSnackBar');

  static Key resultRowKey(String readingId) =>
      Key('labs.detail.result.$readingId');

  static Key archiveButtonKey(String readingId) =>
      Key('labs.detail.archive.$readingId');

  final String labTestKey;

  @override
  Widget build(BuildContext context) {
    return ProtocolsLockGate(
      subject: ProtocolsLockSubject.labResults,
      child: _LabTestDetailScaffold(labTestKey: labTestKey),
    );
  }
}

class _LabTestDetailScaffold extends ConsumerWidget {
  const _LabTestDetailScaffold({required this.labTestKey});

  final String labTestKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.colors;
    final state = ref.watch(labTestDetailProvider(labTestKey));
    final views = state.value;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.chrome,
        title: Text(_title(ref)),
      ),
      body: SafeArea(
        child: switch (views) {
          null when state.hasError => Padding(
              padding: const EdgeInsets.all(AppDimens.base),
              child: Text(
                l10n.labResultsUnavailable,
                style: context.textStyles.body.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          null => const SizedBox.shrink(),
          [] => Padding(
              key: LabTestDetailScreen.emptyKey,
              padding: const EdgeInsets.all(AppDimens.base),
              child: Text(
                l10n.labTestDetailEmpty,
                style: context.textStyles.body.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          final list => ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: colors.divider),
              itemBuilder: (context, index) {
                final view = list[index];
                final readingId = view.record.readingId;
                return LabResultRow(
                  key: LabTestDetailScreen.resultRowKey(readingId),
                  view: view,
                  archiveButtonKey:
                      LabTestDetailScreen.archiveButtonKey(readingId),
                  onArchive: () => _archive(context, ref, view),
                );
              },
            ),
        },
      ),
    );
  }

  /// The catalogue name, or for "Other" the stored name the Lab Results
  /// screen shows.
  String _title(WidgetRef ref) {
    final labTest = labTestByKey(labTestKey);
    if (labTest != null) return labTest.name;
    final summaries = ref.watch(labTestsProvider).value;
    if (summaries == null) return '';
    for (final summary in summaries) {
      if (summary.labTestKey == labTestKey) return summary.name;
    }
    return '';
  }

  /// Confirms, stating how many saved copies go with it, then archives every
  /// live row of the result's identity in one Batch
  /// ([LabResultsRepository.archiveResult]) and offers Undo of that Batch for
  /// 4 s, as other archive and remove actions in the app do. The bar names no
  /// Lab Test or value, so it is safe to show over the lock screen.
  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    LabResultView view,
  ) async {
    final l10n = context.l10n;
    final record = view.record;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ProtocolsLockSheetGuard(
        child: AlertDialog(
          content: Text(
            l10n.labResultArchiveConfirm(record.identityRowCount),
            style: dialogContext.textStyles.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.labResultArchiveCancel),
            ),
            TextButton(
              key: LabTestDetailScreen.archiveConfirmKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.labResultArchiveConfirmAction),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final activityLog = ref.read(trainingRepositoriesProvider).activityLog;
    final batchId = await ref
        .read(labResultsRepositoryProvider)
        .archiveResult(record.readingId);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: LabTestDetailScreen.archivedSnackBarKey,
          content: Text(l10n.labResultArchived),
          duration: const Duration(seconds: 4),
          // An action would otherwise keep the bar up until dismissed.
          persist: false,
          action: SnackBarAction(
            label: l10n.labResultArchiveUndo,
            onPressed: () => unawaited(() async {
              final result = await activityLog.undoBatch(batchId);
              if (!result.hasConflicts) return;
              messenger.showSnackBar(
                SnackBar(content: Text(undoConflictMessage(l10n, result))),
              );
            }()),
          ),
        ),
      );
  }
}
