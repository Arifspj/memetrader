import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memetrader_app/wallet/local_signer.dart';

void main() {
  group('LocalSigner', () {
    test('derives a base58 address from a 32-byte seed', () async {
      final signer = await LocalSigner.fromSeed(Uint8List(32));
      expect(signer.address.length, greaterThan(30));
      expect(signer.address.length, lessThan(50));
      // Base58 alphabet excludes 0, O, I and l.
      expect(signer.address, isNot(contains('0')));
      expect(signer.address, isNot(contains('O')));
      expect(signer.address, isNot(contains('I')));
      expect(signer.address, isNot(contains('l')));
    });

    test('the same seed always derives the same address', () async {
      Uint8List seed() => Uint8List.fromList(List<int>.generate(32, (i) => i));
      expect((await LocalSigner.fromSeed(seed())).address,
          (await LocalSigner.fromSeed(seed())).address);
    });

    test('different seeds derive different addresses', () async {
      final a = await LocalSigner.fromSeed(Uint8List.fromList(List<int>.filled(32, 1)));
      final b = await LocalSigner.fromSeed(Uint8List.fromList(List<int>.filled(32, 2)));
      expect(a.address, isNot(b.address));
    });

    test('rejects a seed that is not 32 bytes', () async {
      await expectLater(LocalSigner.fromSeed(Uint8List(16)), throwsFormatException);
    });

    test('a signature is base64 for 64 raw bytes (RFC 8032)', () async {
      final signer = await LocalSigner.fromSeed(Uint8List(32));
      final signature = await signer.sign('nonce-123');
      expect(signature, isNotEmpty);
      expect(base64Decode(signature), hasLength(64));
    });

    test('signing is deterministic for the same message', () async {
      final signer = await LocalSigner.fromSeed(Uint8List.fromList(List<int>.filled(32, 7)));
      expect(await signer.sign('hello'), await signer.sign('hello'));
    });

    test('different messages produce different signatures', () async {
      final signer = await LocalSigner.fromSeed(Uint8List.fromList(List<int>.filled(32, 7)));
      expect(await signer.sign('a'), isNot(await signer.sign('b')));
    });

    test('fromSeedPhrase needs at least 12 words', () async {
      await expectLater(
        LocalSigner.fromSeedPhrase('one two three'),
        throwsFormatException,
      );
    });

    test('fromSeedPhrase is deterministic and whitespace tolerant', () async {
      const words = 'alpha bravo charlie delta echo foxtrot golf hotel india '
          'juliet kilo lima';
      final a = await LocalSigner.fromSeedPhrase(words);
      final b = await LocalSigner.fromSeedPhrase('  $words  ');
      expect(a.address, b.address);
    });
  });

  group('base58Encode', () {
    test('pads leading zero bytes with "1"', () {
      expect(base58Encode([0, 0, 1]), '112');
    });

    test('encodes zero as "1"', () {
      expect(base58Encode([0]), '1');
    });

    test('round-trips known small values', () {
      expect(base58Encode([57]), 'z');
      expect(base58Encode([58]), '21');
    });
  });

  test('generateDevnetSeed returns a fresh 32-byte seed', () {
    final a = generateDevnetSeed();
    final b = generateDevnetSeed();
    expect(a, hasLength(32));
    expect(a, isNot(b));
  });
}
