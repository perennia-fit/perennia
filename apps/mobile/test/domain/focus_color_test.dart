import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/focus_color.dart';

void main() {
  test('each starter Focus has its fixed default token', () {
    expect(focusDefaultColorToken(starterFocusWeightsId), 'back');
    expect(focusDefaultColorToken(starterFocusEnduranceId), 'cardio');
    expect(focusDefaultColorToken(starterFocusFunctionalId), 'shoulders');
    expect(focusDefaultColorToken(starterFocusCalisthenicsId), 'arms');
    expect(focusDefaultColorToken(starterFocusMobilityId), 'core');
  });

  test('fnv1a32 matches the published FNV-1a test vectors', () {
    expect(fnv1a32(''), 0x811C9DC5);
    expect(fnv1a32('a'), 0xE40C292C);
    expect(fnv1a32('foobar'), 0xBF9CF968);
  });

  test("a user Focus's default comes from its id's hash", () {
    // fnv1a32 is 0x6467CCBE; mod 7 is 3, the fourth token.
    expect(
      focusDefaultColorToken('01a16cdc-0000-7000-8000-000000000001'),
      'shoulders',
    );
  });

  test('the default depends only on the id, never on order', () {
    const ids = <String>[
      '01a16cdc-0000-7000-8000-000000000002',
      '01a16cdc-0000-7000-8000-000000000001',
      starterFocusWeightsId,
    ];
    final before = {for (final id in ids) id: focusDefaultColorToken(id)};
    final reordered = {
      for (final id in ids.reversed) id: focusDefaultColorToken(id),
    };

    expect(reordered, before);
  });

  test('no Focus defaults to other, which marks No Focus', () {
    expect(focusColorTokens, isNot(contains('other')));
    for (var index = 0; index < 200; index += 1) {
      expect(focusDefaultColorToken('focus-$index'), isNot('other'));
    }
  });
}
