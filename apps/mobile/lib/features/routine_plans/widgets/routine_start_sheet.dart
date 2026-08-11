import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/routine_plan_controller.dart';
import '../repositories/routine_plan_feature_repository.dart';
import 'localized_cadence_slot_label.dart';

/// Opens the "which session?" picker for starting a Routine.
///
/// Returns the chosen [RoutineEntryDetail], or null when dismissed. The
/// caller performs the actual materialize + navigate — this sheet is a pure
/// picker (ROUTINES.md §3.2's "preview-and-trim" picker family, scoped down
/// to entry selection for this slice; the derived Up-next suggestions are a
/// sibling slice).
Future<RoutineEntryDetail?> showRoutineStartSheet(
  BuildContext context, {
  required String routineId,
  required String routineName,
}) {
  return showModalBottomSheet<RoutineEntryDetail>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => RoutineStartSheet(
      routineId: routineId,
      routineName: routineName,
    ),
  );
}

class RoutineStartSheet extends ConsumerWidget {
  const RoutineStartSheet({
    super.key,
    required this.routineId,
    required this.routineName,
  });

  final String routineId;
  final String routineName;

  static const sheetKey = Key('routinePlans.startSheet');

  static Key entryKey(String id) => Key('routinePlans.startSheet.entry.$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final detail = ref.watch(routinePlanDetailControllerProvider(routineId));

    return SafeArea(
      key: sheetKey,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.routinePlansStartSheetTitle(routineName),
                style: context.textStyles.h2,
              ),
              const SizedBox(height: AppDimens.base),
              detail.when(
                data: (routine) {
                  final entries =
                      (routine?.entries ?? const <RoutineEntryDetail>[])
                          .where((entry) => !entry.templateIsArchived)
                          .toList(growable: false);
                  if (entries.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDimens.base,
                      ),
                      child: Text(
                        l10n.routinePlansStartEmptyMessage,
                        style: context.textStyles.body.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    );
                  }
                  final cadenceKind = routine?.cadence?.kind;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in entries)
                        Builder(
                          builder: (itemContext) {
                            final slot = entry.slot;
                            final subtitle = slot != null && cadenceKind != null
                                ? localizedCadenceSlotLabel(
                                    l10n,
                                    kind: cadenceKind,
                                    slot: slot,
                                  )
                                : null;
                            return ListTile(
                              key: RoutineStartSheet.entryKey(entry.id),
                              minTileHeight: AppDimens.rowHeight,
                              title: Text(
                                entry.templateName,
                                style: context.textStyles.h2,
                              ),
                              subtitle: subtitle == null
                                  ? null
                                  : Text(
                                      subtitle,
                                      style: context.textStyles.body.copyWith(
                                        color: context.colors.textSecondary,
                                      ),
                                    ),
                              trailing: const Icon(Icons.play_arrow),
                              onTap: () =>
                                  Navigator.of(itemContext).pop(entry),
                            );
                          },
                        ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => Text(
                  l10n.routinePlansUnavailable,
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
