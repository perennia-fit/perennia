import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/protocols/services/protocols_pin_hasher.dart';

void main() {
  const hasher = ProtocolsPinHasher(iterations: 10);

  group('isValidPin', () {
    test('accepts 4-8 digit PINs', () {
      expect(hasher.isValidPin('1234'), isTrue);
      expect(hasher.isValidPin('12345678'), isTrue);
    });

    test('rejects too-short, too-long, or non-numeric input', () {
      expect(hasher.isValidPin('123'), isFalse);
      expect(hasher.isValidPin('123456789'), isFalse);
      expect(hasher.isValidPin('12a4'), isFalse);
      expect(hasher.isValidPin(''), isFalse);
    });
  });

  group('hash/verify', () {
    test('a hashed PIN never contains the plaintext PIN', () async {
      final hashed = await hasher.hash('1234');
      expect(hashed, isNot(contains('1234')));
    });

    test('verify succeeds for the exact PIN that was hashed', () async {
      final hashed = await hasher.hash('9876');
      expect(await hasher.verify('9876', hashed), isTrue);
    });

    test('verify fails for a different PIN', () async {
      final hashed = await hasher.hash('9876');
      expect(await hasher.verify('0000', hashed), isFalse);
    });

    test('two hashes of the same PIN differ (random salt)', () async {
      final first = await hasher.hash('1234');
      final second = await hasher.hash('1234');
      expect(first, isNot(second));
      expect(await hasher.verify('1234', first), isTrue);
      expect(await hasher.verify('1234', second), isTrue);
    });

    test('verify fails safely on a malformed stored hash', () async {
      expect(await hasher.verify('1234', 'not-a-real-hash'), isFalse);
      expect(await hasher.verify('1234', ''), isFalse);
    });
  });
}
