import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/activity_feed_controller.dart';
import '../repositories/activity_feed_repository.dart';

class ActivityFeedScreen extends ConsumerWidget {
  const ActivityFeedScreen({super.key});

  static const String routeName = '/activity';
  static const emptyStateKey = Key('activityFeed.empty');
  static Key undoButtonKey(String batchId) => Key('activityFeed.undo.$batchId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activityFeedControllerProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navRecentActivity)),
      body: SafeArea(
        child: state.when(
          data: (feedState) => _ActivityFeedContent(
            batches: feedState.batches,
            now: DateTime.now(),
            onUndoBatch: (batch) async {
              final messenger = ScaffoldMessenger.of(context);
              final result = await ref
                  .read(activityFeedControllerProvider.notifier)
                  .undoBatch(batch.batchId);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    result.hasConflicts
                        ? _undoConflictMessage(l10n, result)
                        : l10n.activityUndoSuccess,
                  ),
                ),
              );
            },
          ),
          loading: () => const SizedBox.expand(),
          error: (_, __) => Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              l10n.activityUnavailable,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityFeedContent extends StatelessWidget {
  const _ActivityFeedContent({
    required this.batches,
    required this.now,
    required this.onUndoBatch,
  });

  final List<ActivityFeedBatch> batches;
  final DateTime now;
  final Future<void> Function(ActivityFeedBatch batch) onUndoBatch;

  @override
  Widget build(BuildContext context) {
    if (batches.isEmpty) {
      return Center(
        key: ActivityFeedScreen.emptyStateKey,
        child: Text(
          context.l10n.activityEmpty,
          style: context.textStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
      itemCount: batches.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: context.colors.divider,
      ),
      itemBuilder: (context, index) {
        final batch = batches[index];
        return _ActivityFeedTile(
          batch: batch,
          now: now,
          onUndo: () => onUndoBatch(batch),
        );
      },
    );
  }
}

class _ActivityFeedTile extends StatelessWidget {
  const _ActivityFeedTile({
    required this.batch,
    required this.now,
    required this.onUndo,
  });

  final ActivityFeedBatch batch;
  final DateTime now;
  final Future<void> Function() onUndo;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final timestamp = formatActivityRelativeTimestamp(
      context,
      occurredAt: batch.occurredAt,
      now: now,
    );
    final changes = l10n.activityChangeCount(batch.entries.length);
    final actorLabel = _activityActorLabel(l10n, batch.actor);

    final semanticLabel = l10n.activityFeedSemanticLabel(
      batch.affectedEntitySummary,
      actorLabel,
      changes,
      timestamp,
    );

    return ListTile(
      leading: const ExcludeSemantics(child: Icon(Icons.history_outlined)),
      title: Semantics(
        label: semanticLabel,
        child: ExcludeSemantics(child: Text(batch.affectedEntitySummary)),
      ),
      subtitle: ExcludeSemantics(
        child: Text(l10n.activityFeedSubtitle(actorLabel, changes)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Text(
              timestamp,
              style: context.textStyles.label.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
          IconButton(
            key: ActivityFeedScreen.undoButtonKey(batch.batchId),
            tooltip: l10n.activityUndoTooltip,
            icon: const Icon(Icons.undo_outlined),
            onPressed: onUndo,
          ),
        ],
      ),
    );
  }
}

String _activityActorLabel(AppLocalizations l10n, String actor) {
  const agentPrefix = 'agent:';
  if (actor == 'agent') {
    return l10n.activityAgentActor;
  }
  if (actor.startsWith(agentPrefix) && actor.length > agentPrefix.length) {
    return l10n.activityAgentActorWithKey(
      actor.substring(agentPrefix.length),
    );
  }
  return actor;
}

String _undoConflictMessage(
  AppLocalizations l10n,
  ActivityLogUndoResult result,
) {
  final count = result.conflicts.length;
  if (result.conflicts.isEmpty) {
    return l10n.activityUndoGenericConflict;
  }
  final first = result.conflicts.first;
  return l10n.activityUndoConflict(count, first.entityTable, first.entityId);
}

String formatActivityRelativeTimestamp(
  BuildContext context, {
  required DateTime occurredAt,
  required DateTime now,
}) {
  final localOccurredAt = occurredAt.toLocal();
  final localNow = now.toLocal();
  final elapsed = localNow.difference(localOccurredAt);
  final l10n = context.l10n;
  if (elapsed.isNegative) {
    return l10n.activityRelativeLessThanOneMinuteAgo;
  }
  if (elapsed.inMinutes < 1) {
    return l10n.activityRelativeLessThanOneMinuteAgo;
  }
  if (elapsed.inHours < 1) {
    return l10n.activityRelativeMinutesAgo(elapsed.inMinutes);
  }
  if (elapsed.inDays < 1) {
    return l10n.activityRelativeHoursAgo(elapsed.inHours);
  }
  if (elapsed.inDays < 7) {
    return l10n.activityRelativeDaysAgo(elapsed.inDays);
  }
  return MaterialLocalizations.of(context).formatShortDate(localOccurredAt);
}
