import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/sync/repositories/sync_repository.dart';

void main() {
  test('sync reuses the app TrainingRepositories instead of building its own',
      () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);

    final syncRepository = container.read(syncRepositoryProvider);

    expect(
      syncRepository.trainingRepositories,
      same(container.read(trainingRepositoriesProvider)),
    );
  });
}
