import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';

void main() {
  group('ActivityLogEntry', () {
    test('defensively copies and freezes image snapshots', () {
      final beforeImage = <String, Object?>{
        'id': 'set-1',
        'nested': <String, Object?>{'value': 'before'},
        'items': <Object?>[
          <String, Object?>{'value': 'first'},
        ],
      };

      final entry = _entry(beforeImage: beforeImage);
      beforeImage['id'] = 'changed';
      (beforeImage['nested']! as Map<String, Object?>)['value'] = 'changed';
      ((beforeImage['items']! as List<Object?>).single!
          as Map<String, Object?>)['value'] = 'changed';

      expect(entry.beforeImage!['id'], 'set-1');
      final nested = entry.beforeImage!['nested']! as Map<String, Object?>;
      expect(nested['value'], 'before');
      final items = entry.beforeImage!['items']! as List<Object?>;
      final firstItem = items.single! as Map<String, Object?>;
      expect(firstItem['value'], 'first');

      expect(
        () => entry.beforeImage!['id'] = 'changed again',
        throwsUnsupportedError,
      );
      expect(() => nested['value'] = 'again', throwsUnsupportedError);
      expect(() => items.add('another'), throwsUnsupportedError);
      expect(() => firstItem['value'] = 'again', throwsUnsupportedError);
    });
  });
}

ActivityLogEntry _entry({
  Map<String, Object?>? beforeImage,
  Map<String, Object?>? afterImage,
}) {
  return ActivityLogEntry(
    id: 'activity-1',
    actor: 'app',
    batchId: 'batch-1',
    entityTable: AppDatabase.loggedSetsTable,
    entityId: 'set-1',
    occurredAt: DateTime.utc(2026, 7, 9, 4),
    updatedAt: DateTime.utc(2026, 7, 9, 4),
    beforeImage: beforeImage,
    afterImage: afterImage,
  );
}
