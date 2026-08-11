import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/features/settings/repositories/integration_consent_repository.dart';

void main() {
  test('Garmin import consent state defensively copies consent rows', () {
    final activitiesRow = _consentRow(ImportDataClass.activities);
    final heartRateRow = _consentRow(ImportDataClass.heartRate);
    final rowsByDataClass = <ImportDataClass, IntegrationDataClassConsentRow>{
      ImportDataClass.activities: activitiesRow,
    };

    final state = GarminImportConsentState(
      credentialId: 'garmin-credential',
      rowsByDataClass: rowsByDataClass,
    );

    rowsByDataClass[ImportDataClass.heartRate] = heartRateRow;

    expect(state.canEdit(ImportDataClass.activities), isTrue);
    expect(state.canEdit(ImportDataClass.heartRate), isFalse);
    expect(
      () => state.rowsByDataClass[ImportDataClass.heartRate] = heartRateRow,
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => state.rowsByDataClass.remove(ImportDataClass.activities),
      throwsA(isA<UnsupportedError>()),
    );
  });
}

IntegrationDataClassConsentRow _consentRow(
  ImportDataClass dataClass, {
  bool enabled = true,
}) {
  return IntegrationDataClassConsentRow(
    id: 'consent-${dataClass.name}',
    credentialId: 'garmin-credential',
    dataClass: dataClass.name,
    enabled: enabled,
    syncPreviouslySynced: false,
    updatedAt: DateTime.utc(2026),
  );
}
