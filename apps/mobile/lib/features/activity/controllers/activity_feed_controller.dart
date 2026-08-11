import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../repositories/activity_feed_repository.dart';

final activityFeedControllerProvider = StreamNotifierProvider.autoDispose<
    ActivityFeedController, ActivityFeedState>(
  ActivityFeedController.new,
);

class ActivityFeedController extends StreamNotifier<ActivityFeedState> {
  @override
  Stream<ActivityFeedState> build() {
    return ref.watch(activityFeedRepositoryProvider).watchRecentBatches().map(
          (batches) => ActivityFeedState(batches: batches),
        );
  }

  Future<ActivityLogUndoResult> undoBatch(String batchId) {
    return ref.read(activityFeedRepositoryProvider).undoBatch(batchId);
  }
}

final class ActivityFeedState {
  ActivityFeedState({
    List<ActivityFeedBatch> batches = const <ActivityFeedBatch>[],
  }) : batches = List<ActivityFeedBatch>.unmodifiable(batches);

  final List<ActivityFeedBatch> batches;
}
