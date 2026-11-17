import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/protocols/protocol_validation.dart';
import 'package:perennia/domain/protocols/protocols.dart';

void main() {
  final rejects = throwsA(isA<ArgumentError>());

  group('validateProtocolName', () {
    test('returns the trimmed name', () {
      expect(validateProtocolName('  Creatine stack '), 'Creatine stack');
    });

    test('rejects an empty or blank name', () {
      expect(() => validateProtocolName(''), rejects);
      expect(() => validateProtocolName('   '), rejects);
    });
  });

  group('validateProtocolMembership', () {
    test('returns the ids unchanged, in order', () {
      final ids = <String>['b', 'a'];
      expect(validateProtocolMembership(ids), same(ids));
    });

    test('rejects an empty list and a repeated Compound', () {
      expect(() => validateProtocolMembership(const <String>[]), rejects);
      expect(
        () => validateProtocolMembership(const <String>['a', 'b', 'a']),
        rejects,
      );
    });
  });

  group('validateProtocolTargetOutcomes', () {
    test('accepts an empty list and distinct outcomes', () {
      expect(
        validateProtocolTargetOutcomes(const <ProtocolTargetOutcomeDraft>[]),
        isEmpty,
      );
      final outcomes = <ProtocolTargetOutcomeDraft>[
        ProtocolTargetOutcomeDraft.metric('weight'),
        ProtocolTargetOutcomeDraft.metric('sleep'),
        ProtocolTargetOutcomeDraft.performance,
      ];
      expect(validateProtocolTargetOutcomes(outcomes), same(outcomes));
    });

    test('rejects a metric outcome without a Metric id', () {
      expect(
        () => validateProtocolTargetOutcomes(const <ProtocolTargetOutcomeDraft>[
          ProtocolTargetOutcomeDraft(kind: ProtocolOutcomeKind.metric),
        ]),
        rejects,
      );
      expect(
        () => validateProtocolTargetOutcomes(<ProtocolTargetOutcomeDraft>[
          ProtocolTargetOutcomeDraft.metric('  '),
        ]),
        rejects,
      );
    });

    test('rejects the same Metric or performance twice', () {
      expect(
        () => validateProtocolTargetOutcomes(<ProtocolTargetOutcomeDraft>[
          ProtocolTargetOutcomeDraft.metric('weight'),
          ProtocolTargetOutcomeDraft.metric('weight'),
        ]),
        rejects,
      );
      expect(
        () => validateProtocolTargetOutcomes(const <ProtocolTargetOutcomeDraft>[
          ProtocolTargetOutcomeDraft.performance,
          ProtocolTargetOutcomeDraft.performance,
        ]),
        rejects,
      );
    });

    test('compares Metric ids untrimmed', () {
      final outcomes = <ProtocolTargetOutcomeDraft>[
        ProtocolTargetOutcomeDraft.metric('weight'),
        ProtocolTargetOutcomeDraft.metric(' weight'),
      ];
      expect(validateProtocolTargetOutcomes(outcomes), same(outcomes));
    });
  });

  test('protocolTargetOutcomeKey joins kind and Metric id', () {
    expect(protocolTargetOutcomeKey('metric', 'weight'), 'metric|weight');
    expect(protocolTargetOutcomeKey('performance', null), 'performance|');
  });
}
