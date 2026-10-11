import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class EncryptionService {
  // Toggle to easily enable/disable encryption for testing/debugging
  static const bool enableEncryption = true;

  // 512-bit safe prime from standard groups
  static final BigInt dhPrime = BigInt.parse(
      '9868840660682972715032898763147877508990680424262914175225102581005705322961817446549077501258105804368564032039281504289812497675718683526839841800041147');
  static final BigInt dhGenerator = BigInt.two;

  EncryptionService._privateConstructor();
  static final EncryptionService instance = EncryptionService._privateConstructor();

  /// Converts a hex string to a Uint8List
  Uint8List _hexToBytes(String hexStr) {
    final bytes = <int>[];
    for (int i = 0; i < hexStr.length; i += 2) {
      bytes.add(int.parse(hexStr.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// Generates a cryptographically secure 256-bit random private key
  BigInt generatePrivateKey() {
    final Random rand = Random.secure();
    final List<int> bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    BigInt result = BigInt.zero;
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  /// Calculates the public key: g^privateKey mod p
  BigInt calculatePublicKey(BigInt privateKey) {
    return dhGenerator.modPow(privateKey, dhPrime);
  }

  /// Computes the shared secret: peerPublicKey^privateKey mod p
  /// Parameters are ordered (peerPublicKey, privateKey) to align with chat_provider.dart usage.
  BigInt calculateSharedSecret(BigInt peerPublicKey, BigInt privateKey) {
    return peerPublicKey.modPow(privateKey, dhPrime);
  }

  /// Derives a 256-bit AES key from the shared secret using SHA-256
  String deriveAESKeyHex(BigInt sharedSecret) {
    final bytes = utf8.encode(sharedSecret.toRadixString(16));
    final digest = sha256.convert(bytes);
    return digest.toString(); // Hex string representing the 32-byte key
  }

  /// Encrypts plaintext using AES-256-CBC with the shared key
  String encryptText(String plaintext, String keyHex) {
    if (!enableEncryption) {
      return plaintext;
    }
    try {
      final key = enc.Key(_hexToBytes(keyHex));
      final iv = enc.IV.fromSecureRandom(16); // Generates a random 16-byte IV
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(plaintext, iv: iv);
      return jsonEncode({
        'iv': iv.base64,
        'ct': encrypted.base64,
      });
    } catch (e) {
      print("EncryptionService Error: Encryption failed: $e");
      return plaintext; // Fallback to plaintext if encryption fails
    }
  }

  /// Decrypts ciphertext using AES-256-CBC with the shared key
  String decryptText(String ciphertextJson, String keyHex) {
    if (!enableEncryption) {
      return ciphertextJson;
    }
    final trimmed = ciphertextJson.trim();
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
      // Plaintext fallback: if it doesn't look like JSON, treat it as plaintext
      return ciphertextJson;
    }
    try {
      final data = jsonDecode(ciphertextJson);
      if (data is! Map || !data.containsKey('iv') || !data.containsKey('ct')) {
        return ciphertextJson; // Plaintext fallback
      }
      final key = enc.Key(_hexToBytes(keyHex));
      final iv = enc.IV.fromBase64(data['iv']);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt64(data['ct'], iv: iv);
    } catch (e) {
      print("EncryptionService Error: Decryption failed: $e");
      return "[Decryption Failed]";
    }
  }

  Uint8List encryptBytes(Uint8List bytes, String password) {
    final keyBytes = sha256.convert(utf8.encode(password)).bytes;
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(bytes, iv: iv);
    
    final combined = Uint8List(16 + encrypted.bytes.length);
    combined.setRange(0, 16, iv.bytes);
    combined.setRange(16, combined.length, encrypted.bytes);
    return combined;
  }

  Uint8List decryptBytes(Uint8List combined, String password) {
    if (combined.length < 16) {
      throw Exception("Invalid ciphertext bytes");
    }
    final keyBytes = sha256.convert(utf8.encode(password)).bytes;
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV(combined.sublist(0, 16));
    final ciphertext = combined.sublist(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final decrypted = encrypter.decryptBytes(enc.Encrypted(ciphertext), iv: iv);
    return Uint8List.fromList(decrypted);
  }
}
