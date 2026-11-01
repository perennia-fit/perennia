import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../home/controllers/home_controller.dart';
import '../../protocols/widgets/consistency_screen.dart';
import '../../protocols/widgets/protocols_lock_screen.dart';
import '../controllers/progress_controller.dart';
import 'progress_card.dart';
import 'this_week_card.dart' show progressSeparator;

/// Each Compound's Day Status counts for the period (D7, D8 card 7), behind
/// the Protocols lock. While a lock is set and locked, or its state cannot be
/// read, the card shows only a lock row that looks the same whether or not
/// any Protocol exists, and no Compound name renders.
class ProtocolsProgressCard extends ConsumerWidget {
  const ProtocolsProgressCard({super.key});

  static const cardKey = Key('progress.protocols');
  static const lockedRowKey = Key('progress.protocols.locked');
  static const unlockButtonKey = Key('progress.protocols.unlock');
  static const allProtocolsButtonKey = Key('progress.protocols.all');
  static const emptyKey = Key('progress.protocols.empty');

  static Key rowKey(String compoundId) =>
      Key('progress.protocols.row.$compoundId');

  /// The most Compound rows the card shows before "All protocols".
  static const int maxRows = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(progressProtocolsProvider);
    // Loading renders nothing: the card may turn out absent. An error fails
    // closed, like the lock's own unavailable state.
    final protocols =
        state.hasError ? const ProgressProtocolsUnavailable() : state.value;
    if (protocols == null) {
      return const SizedBox.shrink();
    }
    final title = l10n.progressProtocolsTitle;
    return switch (protocols) {
      ProgressProtocolsLocked() => ProgressCard(
          key: cardKey,
          title: title,
          child: _LockRow(
            message: l10n.protocolsLockedTitle,
            action: ProgressCardAction(
              key: unlockButtonKey,
              label: l10n.progressProtocolsUnlock,
              onPressed: () => _showUnlockSheet(context),
            ),
          ),
        ),
      ProgressProtocolsUnavailable() => ProgressCard(
          key: cardKey,
          title: title,
          child: _LockRow(message: l10n.protocolsLockUnavailableTitle),
        ),
      ProgressProtocolsRows(rows: final rows) when rows.isEmpty =>
        ProgressCard.empty(
          key: cardKey,
          title: title,
          message: l10n.progressProtocolsEmpty,
        ),
      ProgressProtocolsRows(rows: final rows) => ProgressCard(
          key: cardKey,
          title: title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, row) in rows.take(maxRows).indexed) ...[
                if (index > 0) const Divider(),
                _CompoundRow(summary: row),
              ],
              if (rows.length > maxRows)
                Align(
                  alignment: Alignment.centerLeft,
                  child: ProgressTextButton(
                    action: ProgressCardAction(
                      key: allProtocolsButtonKey,
                      label: l10n.progressProtocolsAll,
                      onPressed: () => _openAllProtocols(ref),
                    ),
                  ),
                ),
            ],
          ),
        ),
    };
  }

  /// "All protocols" switches to Today with its Protocols tab selected.
  static void _openAllProtocols(WidgetRef ref) {
    ref.read(selectedHomeDomainProvider.notifier).select(HomeDomain.protocols);
    ref
        .read(selectedHomeDestinationProvider.notifier)
        .select(HomeDestination.today);
  }

  static Future<void> _showUnlockSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          AppDimens.base,
          0,
          AppDimens.base,
          AppDimens.base + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SingleChildScrollView(
          child: ProtocolsUnlockForm(
            onUnlocked: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
  }
}

/// The locked or unavailable stand-in: an icon and one line, plus the
/// Unlock button when unlocking is possible.
class _LockRow extends StatelessWidget {
  const _LockRow({required this.message, this.action});

  final String message;
  final ProgressCardAction? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final action = this.action;
    return ConstrainedBox(
      key: ProtocolsProgressCard.lockedRowKey,
      constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: colors.textSecondary),
          const SizedBox(width: AppDimens.dense),
          Expanded(
            child: Text(
              message,
              style: context.textStyles.body.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          if (action != null) ProgressTextButton(action: action),
        ],
      ),
    );
  }
}

class _CompoundRow extends StatelessWidget {
  const _CompoundRow({required this.summary});

  final CompoundConsistencySummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final counts = <String>[
      if (summary.logged > 0) l10n.progressCountLogged(summary.logged),
      if (summary.partlyLogged > 0)
        l10n.progressCountPartlyLogged(summary.partlyLogged),
      if (summary.notLogged > 0) l10n.progressCountNotLogged(summary.notLogged),
      if (summary.paused > 0) l10n.progressCountPaused(summary.paused),
    ].join(progressSeparator);
    return InkWell(
      key: ProtocolsProgressCard.rowKey(summary.compoundId),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProtocolsLockGate(
              child: ConsistencyScreen.compound(
                compoundId: summary.compoundId,
                compoundName: summary.compoundName,
              ),
            ),
          ),
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.dense / 2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      summary.compoundName,
                      style: context.textStyles.body.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      counts,
                      style: context.textStyles.caption.copyWith(
                        color: colors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
