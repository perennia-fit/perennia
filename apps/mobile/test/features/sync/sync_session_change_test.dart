import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/api/perennia_api_client.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/sync/models/sync_status.dart';
import 'package:perennia/features/sync/repositories/sync_repository.dart';
import 'package:perennia/features/sync/services/sync_providers.dart';

void main() {
  test(
      'loading the stored session keeps its authExpired verdict; signing out '
      'drops it', () async {
    final warnAboutMultipleDatabases =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          warnAboutMultipleDatabases,
    );
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final serverUrl = Uri.parse('https://sync.example/');
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        authRepositoryProvider.overrideWith(
          (ref) => InMemoryAuthRepository(
            AuthState(
              serverUrl: serverUrl,
              session: AuthSession(
                provider: AuthSessionProvider.email,
                serverUrl: serverUrl,
                token: 'expired-token',
                userEmail: 'sync@example.com',
                userId: 'user-1',
                userName: 'Sync User',
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final status = container.read(syncRepositoryProvider).statusRepository;
    await status.recordAuthExpired(
      const ApiException(statusCode: 401, body: 'unauthorized'),
    );

    // The coordinator starts listening before the stored session has loaded,
    // as it does at app launch.
    container.read(syncCoordinatorProvider);
    await container.read(authControllerProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((await status.loadStatus()).kind, SyncStatusKind.authExpired);

    await container.read(authControllerProvider.notifier).signOut();
    await _waitFor(
      () async => (await status.loadStatus()).kind == SyncStatusKind.idle,
    );
  });
}

Future<void> _waitFor(Future<bool> Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for condition.');
}
