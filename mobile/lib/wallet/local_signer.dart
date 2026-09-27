import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';

/// Local, self-custodial Ed25519 signer.
///
/// Solana/Phantom addresses and `signMessage` both use standard Ed25519
/// (RFC 8032), so a signature produced here verifies against the backend's
/// existing ed25519 nonce check.
///
/// SAFETY: the seed stays in memory for the lifetime of this object. It is
/// never persisted, logged, or sent to the backend. The backend only receives
/// the derived public key (the wallet address) and the signature.
class LocalSigner {
  LocalSigner._(this._keyPair, this._publicKey);

  final SimpleKeyPair _keyPair;
  final List<int> _publicKey;

  static final Ed25519 _algorithm = Ed25519();

  /// Derives a wallet from a raw 32-byte seed.
  static Future<LocalSigner> fromSeed(Uint8List seed) async {
    if (seed.length != 32) {
      throw const FormatException('Ed25519 seed must be 32 bytes');
    }
    final keyPair = await _algorithm.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    return LocalSigner._(keyPair, publicKey.bytes);
  }

  /// Deterministic dev identity from a 12/24-word recovery phrase.
  ///
  /// V1 stand-in: real Phantom accounts keep their key material in Phantom, and
  /// signing is delegated there. Paper mode never needs real funds.
  static Future<LocalSigner> fromSeedPhrase(String phrase) async {
    final normalised = phrase.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (normalised.split(' ').length < 12) {
      throw const FormatException('Seed phrase needs at least 12 words');
    }
    final digest = await Sha256().hash(utf8.encode(normalised));
    return fromSeed(Uint8List.fromList(digest.bytes));
  }

  /// Base58 Solana address of this key.
  String get address => base58Encode(_publicKey);

  /// Signs the backend nonce. Returns base64, matching the backend payload.
  Future<String> sign(String message) async {
    final signature = await _algorithm.sign(
      utf8.encode(message),
      keyPair: _keyPair,
    );
    return base64Encode(signature.bytes);
  }
}

BigInt _bytesToBigInt(Uint8List bytes) =>
    bytes.fold<BigInt>(BigInt.zero, (acc, b) => (acc << 8) | BigInt.from(b));

/// Solana renders addresses and seeds in base58 (no 0/O/I/l).
String base58Encode(List<int> bytes) {
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  var value = _bytesToBigInt(Uint8List.fromList(bytes));
  if (value == BigInt.zero) return alphabet[0];
  final out = StringBuffer();
  while (value > BigInt.zero) {
    out.write(alphabet[(value % BigInt.from(58)).toInt()]);
    value = value ~/ BigInt.from(58);
  }
  for (final b in bytes) {
    if (b != 0) break;
    out.write(alphabet[0]);
  }
  return out.toString().split('').reversed.join();
}

/// Throwaway devnet key for paper-mode testing. Never use real funds here.
Uint8List generateDevnetSeed() {
  final rng = Random.secure();
  return Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
}

String hexOf(Uint8List bytes) => hex.encode(bytes);
