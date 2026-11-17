import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:exambroku_android/domain/models/exam_config.dart';

class PinHashPair {
  const PinHashPair({required this.hashBase64, required this.saltBase64});

  final String hashBase64;
  final String saltBase64;
}

class PinHasher {
  static const int _iterations = 20000;
  static const int _saltBytes = 16;
  static const int _keyLength = 32;

  static PinHashPair hashPin(String rawPin) {
    final rng = Random.secure();
    final salt = Uint8List(_saltBytes);
    for (var i = 0; i < _saltBytes; i++) {
      salt[i] = rng.nextInt(256);
    }
    final derived = _pbkdf2Sha256(utf8.encode(rawPin), salt, _iterations);
    return PinHashPair(
      hashBase64: base64Encode(derived),
      saltBase64: base64Encode(salt),
    );
  }

  static bool verifyPin(ExamConfig config, String candidatePin) {
    if (candidatePin.isEmpty ||
        config.adminPinHash.isEmpty ||
        config.adminPinSalt.isEmpty) {
      return false;
    }

    try {
      final salt = base64Decode(config.adminPinSalt);
      final expected = base64Decode(config.adminPinHash);
      final iter = config.pinIterations > 0 ? config.pinIterations : _iterations;
      final actual = _pbkdf2Sha256(utf8.encode(candidatePin), salt, iter);
      return _constantTimeEquals(expected, actual);
    } catch (_) {
      return false;
    }
  }

  static Uint8List _pbkdf2Sha256(
    List<int> password,
    List<int> salt,
    int iterations,
  ) {
    final hmac = Hmac(sha256, password);
    const hashLen = 32;
    final blockCount = (_keyLength / hashLen).ceil();
    final output = BytesBuilder();

    for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
      final blockHeader = Uint8List(salt.length + 4)
        ..setRange(0, salt.length, salt)
        ..[salt.length] = (blockIndex >> 24) & 0xff
        ..[salt.length + 1] = (blockIndex >> 16) & 0xff
        ..[salt.length + 2] = (blockIndex >> 8) & 0xff
        ..[salt.length + 3] = blockIndex & 0xff;

      var u = Uint8List.fromList(hmac.convert(blockHeader).bytes);
      final t = Uint8List.fromList(u);

      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      output.add(t);
    }

    final bytes = output.toBytes();
    return Uint8List.sublistView(bytes, 0, _keyLength);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class PinAttemptGuard {
  int _failedAttempts = 0;
  DateTime _lockedUntilUtc = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  int get failedAttempts => _failedAttempts;

  int remainingCooldownSeconds() {
    final now = DateTime.now().toUtc();
    if (now.isBefore(_lockedUntilUtc)) {
      return _lockedUntilUtc.difference(now).inSeconds + 1;
    }
    return 0;
  }

  void recordSuccess() {
    _failedAttempts = 0;
    _lockedUntilUtc = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  int recordFailure() {
    _failedAttempts++;
    if (_failedAttempts >= 10) {
      _lockedUntilUtc = DateTime.now().toUtc().add(const Duration(seconds: 60));
      return 60;
    }
    if (_failedAttempts >= 5) {
      _lockedUntilUtc = DateTime.now().toUtc().add(const Duration(seconds: 15));
      return 15;
    }
    return 0;
  }
}
