import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/protocols/widgets/purpose_filter_row.dart';
import 'package:perennia/l10n/app_localizations_en.dart';

void main() {
  group('compoundMatchesFilter', () {
    const lowerPurposeNames = <String, String>{
      'sleep': 'sleep',
      'focus': 'focus',
    };

    bool matches({
      String lowerName = 'magnesium',
      List<String> purposeIds = const <String>[],
      String lowerQuery = '',
      String? filterId,
    }) {
      return compoundMatchesFilter(
        lowerName: lowerName,
        purposeIds: purposeIds,
        lowerPurposeNames: lowerPurposeNames,
        lowerQuery: lowerQuery,
        filterId: filterId,
      );
    }

    test('an empty query with no filter matches', () {
      expect(matches(), isTrue);
    });

    test('a filter excludes a Compound without that tag', () {
      expect(matches(filterId: 'sleep'), isFalse);
      expect(
        matches(purposeIds: const <String>['focus'], filterId: 'sleep'),
        isFalse,
      );
    });

    test('a filter keeps a Compound with that tag', () {
      expect(
        matches(purposeIds: const <String>['sleep'], filterId: 'sleep'),
        isTrue,
      );
    });

    test('a query matches the name', () {
      expect(matches(lowerQuery: 'magn'), isTrue);
      expect(matches(lowerQuery: 'zinc'), isFalse);
    });

    test("a query matches an active Purpose's name", () {
      expect(
        matches(purposeIds: const <String>['sleep'], lowerQuery: 'slee'),
        isTrue,
      );
      expect(
        matches(purposeIds: const <String>['focus'], lowerQuery: 'slee'),
        isFalse,
      );
    });

    test('a query and a filter must both match', () {
      expect(
        matches(
          purposeIds: const <String>['sleep'],
          lowerQuery: 'zinc',
          filterId: 'sleep',
        ),
        isFalse,
      );
      expect(
        matches(
          purposeIds: const <String>['focus'],
          lowerQuery: 'magn',
          filterId: 'sleep',
        ),
        isFalse,
      );
    });

    test(
      "a tag missing from the map isn't searched but satisfies a filter on it",
      () {
        // An archived Purpose stays on the Compound with no active name.
        const tags = <String>['archived'];
        expect(
          matches(purposeIds: tags, lowerQuery: 'archived'),
          isFalse,
        );
        expect(matches(purposeIds: tags, filterId: 'archived'), isTrue);
      },
    );
  });

  group('compoundFilterEmptyMessage', () {
    final l10n = AppLocalizationsEn();

    test('a query comes first, with or without a filter', () {
      expect(
        compoundFilterEmptyMessage(l10n, hasQuery: true, hasFilter: true),
        l10n.compoundListNoMatches,
      );
      expect(
        compoundFilterEmptyMessage(l10n, hasQuery: true, hasFilter: false),
        l10n.compoundListNoMatches,
      );
    });

    test('a filter with no query says the filter is empty', () {
      expect(
        compoundFilterEmptyMessage(l10n, hasQuery: false, hasFilter: true),
        l10n.purposeFilterEmpty,
      );
    });

    test('neither says the library is empty', () {
      expect(
        compoundFilterEmptyMessage(l10n, hasQuery: false, hasFilter: false),
        l10n.compoundListEmpty,
      );
    });
  });
}
