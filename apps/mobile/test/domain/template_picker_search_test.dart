import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/template_picker_search.dart';

void main() {
  group('filterAndSortTemplatesForPicker', () {
    test('with no query, sorts by recency descending (recency fallback)', () {
      final templates = <TemplatePickerTemplateEntry>[
        TemplatePickerTemplateEntry(
          id: 'a',
          name: 'Push A',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        TemplatePickerTemplateEntry(
          id: 'b',
          name: 'Pull A',
          updatedAt: DateTime.utc(2026, 6, 1),
        ),
        TemplatePickerTemplateEntry(
          id: 'c',
          name: 'Legs A',
          updatedAt: DateTime.utc(2026, 3, 1),
        ),
      ];

      final result = filterAndSortTemplatesForPicker(
        templates: templates,
        query: '',
      );

      expect(result.map((e) => e.id), <String>['b', 'c', 'a']);
    });

    test('filters case-insensitively by substring match on name', () {
      final templates = <TemplatePickerTemplateEntry>[
        TemplatePickerTemplateEntry(
          id: 'a',
          name: 'Push A',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        TemplatePickerTemplateEntry(
          id: 'b',
          name: 'Pull A',
          updatedAt: DateTime.utc(2026, 6, 1),
        ),
        TemplatePickerTemplateEntry(
          id: 'c',
          name: 'Sauna + Plunge',
          updatedAt: DateTime.utc(2026, 3, 1),
        ),
      ];

      final result = filterAndSortTemplatesForPicker(
        templates: templates,
        query: 'pu',
      );

      expect(result.map((e) => e.id), <String>['b', 'a']);
    });

    test('within a filtered result, recency ordering still applies', () {
      final templates = <TemplatePickerTemplateEntry>[
        TemplatePickerTemplateEntry(
          id: 'old',
          name: 'Tempo Run',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        TemplatePickerTemplateEntry(
          id: 'new',
          name: 'Tempo Run 8k',
          updatedAt: DateTime.utc(2026, 6, 1),
        ),
      ];

      final result = filterAndSortTemplatesForPicker(
        templates: templates,
        query: 'tempo',
      );

      expect(result.map((e) => e.id), <String>['new', 'old']);
    });

    test('an empty template list returns an empty result', () {
      final result = filterAndSortTemplatesForPicker(
        templates: const <TemplatePickerTemplateEntry>[],
        query: 'anything',
      );

      expect(result, isEmpty);
    });

    test('a query matching nothing returns an empty result', () {
      final templates = <TemplatePickerTemplateEntry>[
        TemplatePickerTemplateEntry(
          id: 'a',
          name: 'Push A',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ];

      final result = filterAndSortTemplatesForPicker(
        templates: templates,
        query: 'zzz',
      );

      expect(result, isEmpty);
    });

    test('ties in recency break by name then id, deterministically', () {
      final tied = DateTime.utc(2026, 1, 1);
      final templates = <TemplatePickerTemplateEntry>[
        TemplatePickerTemplateEntry(id: 'z', name: 'Alpha', updatedAt: tied),
        TemplatePickerTemplateEntry(id: 'y', name: 'Alpha', updatedAt: tied),
        TemplatePickerTemplateEntry(id: 'x', name: 'Beta', updatedAt: tied),
      ];

      final result = filterAndSortTemplatesForPicker(
        templates: templates,
        query: '',
      );

      expect(result.map((e) => e.id), <String>['y', 'z', 'x']);
    });

    test('the result list is unmodifiable', () {
      final result = filterAndSortTemplatesForPicker(
        templates: const <TemplatePickerTemplateEntry>[],
        query: '',
      );

      expect(
          () => result.add(
                TemplatePickerTemplateEntry(
                  id: 'a',
                  name: 'a',
                  updatedAt: DateTime.utc(2026),
                ),
              ),
          throwsUnsupportedError);
    });
  });
}
