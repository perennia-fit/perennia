import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';

const _creatineId = '019200ff-0000-7000-8000-000000000001';

/// Who runs the seed tag backfill (docs/designs/compound-purposes.md, D3): the
/// controller on a device with no sync account, and `SyncRepository` on one
/// with an account. [ProtocolsRepository] has no auth, so this rule lives in
/// the controller.
void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.inMemory();
    // The six rows as a schema-65 device left them: untagged, each with only
    // its `otc_seed` entry.
    await TrainingRepositories(database).protocols.ensureOtcLibrarySeeded();
    await database.customStatement(
      "UPDATE compounds SET purpose_ids = '[]', updated_at = 1000",
    );
  });

  tearDown(() async {
    await database.close();
  });

  ProviderContainer containerWith(AuthController Function() auth) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        authControllerProvider.overrideWith(auth),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<String> creatinePurposeIds() async {
    final row = await (database.select(database.compounds)
          ..where((row) => row.id.equals(_creatineId)))
        .getSingle();
    return row.purposeIds;
  }

  test('a device with no sync account backfills after seeding', () async {
    final container = containerWith(
      () => _FakeAuthController(() async => AuthState.defaults),
    );

    await container
        .read(protocolDayControllerProvider.notifier)
        .ensureOtcLibrarySeeded();

    expect(await creatinePurposeIds(), isNot('[]'));
    // Just past the row's own stamp: another device's edit may be waiting on
    // the server, and this write must not beat it on first sign-in.
    final creatine = await (database.select(database.compounds)
          ..where((row) => row.id.equals(_creatineId)))
        .getSingle();
    expect(creatine.updatedAt.millisecondsSinceEpoch, 1001 * 1000);
  });

  test(
      'a signed-out device leaves rows it synced to the next signed-in Sync '
      'Run, and still tags the rows that never synced', () async {
    // It signed out, which keeps its rows, and an edit made elsewhere may be
    // waiting on the server. A fresh stamp now would beat that edit on sign-in,
    // because a Sync Run pushes before it pulls.
    final repositories = TrainingRepositories(database);
    await database.customStatement(
      'UPDATE compounds SET sync_previously_synced = 1, '
      "sync_device_id = 'device-a' WHERE id = '$_creatineId'",
    );
    final container = containerWith(
      () => _FakeAuthController(() async => AuthState.defaults),
    );

    await container
        .read(protocolDayControllerProvider.notifier)
        .ensureOtcLibrarySeeded();

    expect(await creatinePurposeIds(), '[]');
    final untagged = await (database.select(database.compounds)
          ..where((row) => row.purposeIds.equals('[]')))
        .get();
    expect(untagged.map((row) => row.id), <String>[_creatineId]);

    // What the signed-in Sync Run calls, after its pull.
    await repositories.protocols.backfillSeedPurposes();

    expect(await creatinePurposeIds(), isNot('[]'));
  });

  test('a signed-in device leaves the backfill to the Sync Run', () async {
    final container = containerWith(
      () => _FakeAuthController(
        () async => AuthState(
          serverUrl: Uri.parse('https://sync.example/'),
          session: AuthSession(
            provider: AuthSessionProvider.email,
            serverUrl: Uri.parse('https://sync.example/'),
            token: 'session-token',
            userEmail: 'user@example.com',
            userId: 'user-1',
            userName: 'Sync User',
          ),
        ),
      ),
    );

    await container
        .read(protocolDayControllerProvider.notifier)
        .ensureOtcLibrarySeeded();

    expect(await creatinePurposeIds(), '[]');
    // The seed itself still ran.
    expect(await database.select(database.purposes).get(), hasLength(6));
  });

  test('a failed auth read skips the backfill, and the next open retries',
      () async {
    var fail = true;
    final container = containerWith(
      () => _FakeAuthController(() async {
        if (fail) {
          throw StateError('secure storage is unavailable');
        }
        return AuthState.defaults;
      }),
    );
    final controller = container.read(protocolDayControllerProvider.notifier);

    await controller.ensureOtcLibrarySeeded();

    expect(await creatinePurposeIds(), '[]');
    expect(await database.select(database.purposes).get(), hasLength(6));

    fail = false;
    container.invalidate(authControllerProvider);
    await controller.ensureOtcLibrarySeeded();

    expect(await creatinePurposeIds(), isNot('[]'));
  });
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._load);

  final Future<AuthState> Function() _load;

  @override
  Future<AuthState> build() => _load();
}
