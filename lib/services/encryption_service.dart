import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io'; 
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionService {
  static final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  // 1. Generate master key from passphrase (zero-knowledge)
  static Future<String> generateMasterKey(String passphrase, {String? biometricKey}) async {
    try {
      final combined = biometricKey != null 
          ? '$passphrase:$biometricKey:${DateTime.now().millisecondsSinceEpoch}'
          : '$passphrase:${DateTime.now().millisecondsSinceEpoch}';
      
      final salt = utf8.encode('secure_share_salt_${DateTime.now().millisecondsSinceEpoch}');
      final keyBytes = sha256.convert(utf8.encode(combined)).bytes;
      final derivedKey = pbkdf2(sha256, keyBytes, salt, 100000, 32);
      
      final masterKey = base64Url.encode(derivedKey);
      
      // Store only the hash for verification
      final keyHash = sha256.convert(derivedKey).toString();
      await _secureStorage.write(key: 'master_key_hash', value: keyHash);
      
      return masterKey;
    } catch (e) {
      throw Exception('Key generation failed: $e');
    }
  }

  // 2. Generate Random Key (Helper for simple usage)
  static String generateRandomKey() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }
  
  // 3. Generate content encryption key
  static Map<String, String> generateContentKey(String masterKey) {
    try {
      final masterBytes = base64Url.decode(masterKey);
      final random = Random.secure();
      final randomBytes = List<int>.generate(16, (i) => random.nextInt(256));
      
      final combined = Uint8List.fromList([...masterBytes, ...randomBytes]);
      final contentKeyBytes = sha256.convert(combined).bytes.sublist(0, 32);
      final contentKey = base64Url.encode(contentKeyBytes);
      
      final iv = enc.IV.fromSecureRandom(16);
      
      return {
        'content_key': contentKey,
        'iv': iv.base64,
        'key_id': sha256.convert(contentKeyBytes).toString().substring(0, 16),
      };
    } catch (e) {
      throw Exception('Content key generation failed: $e');
    }
  }
  
  // 4. Encrypt Text (String -> Map<String, String>)
  static Map<String, String> encryptData(String plainText, String contentKey, String iv) {
    try {
      final keyBytes = base64Url.decode(contentKey);
      final key = enc.Key(Uint8List.fromList(keyBytes));
      final ivObj = enc.IV.fromBase64(iv);
      
      // Use AES-CBC (no mode parameter needed in latest version)
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(plainText, iv: ivObj);
      
      return {
        'content': encrypted.base64,
        'iv': iv,
        'auth_tag': '', // CBC doesn't use auth tag
        'encryption_algo': 'AES-256-CBC',
      };
    } catch (e) {
      print('Encryption error: $e');
      throw Exception('Encryption failed: $e');
    }
  }

  // 5. Encrypt Raw Bytes (Uint8List -> Map<String, dynamic>)
  static Map<String, dynamic> encryptBytes(Uint8List fileBytes, String keyString) {
    try {
      final keyBytes = base64Url.decode(keyString);
      final key = enc.Key(Uint8List.fromList(keyBytes));
      final iv = enc.IV.fromSecureRandom(16);

      // Use AES-CBC
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      
      // Encrypt the raw bytes
      final encrypted = encrypter.encryptBytes(fileBytes, iv: iv);

      return {
        'bytes': encrypted.bytes, // Return Uint8List
        'iv': iv.base64,
        'auth_tag': '',
      };
    } catch (e) {
      print('File Encryption Error: $e');
      throw Exception('File Encryption Error: $e');
    }
  }
  
  // 6. Decrypt Data (String -> String) - FIXED SIGNATURE
  static String decryptData(String encryptedContent, String iv, String contentKey) {
    try {
      final keyBytes = base64Url.decode(contentKey);
      final key = enc.Key(Uint8List.fromList(keyBytes));
      final ivObj = enc.IV.fromBase64(iv);
      
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = enc.Encrypted.fromBase64(encryptedContent);
      
      return encrypter.decrypt(encrypted, iv: ivObj);
    } catch (e) {
      print('Decryption error: $e');
      throw Exception('Decryption failed: Invalid key or corrupted data');
    }
  }

  // 7. Decrypt Data with auth_tag parameter (for backward compatibility)
  static String decryptDataWithAuth(String encryptedContent, String iv, String authTag, String contentKey) {
    // Ignore authTag for CBC mode
    return decryptData(encryptedContent, iv, contentKey);
  }

  // 8. Decrypt Raw Bytes (Uint8List -> Uint8List)
  static Uint8List decryptBytes(Uint8List encryptedBytes, String ivString, String keyString) {
    try {
      final keyBytes = base64Url.decode(keyString);
      final key = enc.Key(Uint8List.fromList(keyBytes));
      final iv = enc.IV.fromBase64(ivString);

      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = enc.Encrypted(encryptedBytes);

      // Decrypt to List<int> and convert to Uint8List
      List<int> decrypted = encrypter.decryptBytes(encrypted, iv: iv);
      return Uint8List.fromList(decrypted);
    } catch (e) {
      print('Byte decryption error: $e');
      throw Exception('Byte Decryption Failed: Invalid Key or Corrupt Data');
    }
  }
  
  // 9. Destroy keys (zero-knowledge enforcement)
  static Future<void> destroyKeys(String keyId) async {
    try {
      // Remove from secure storage
      await _secureStorage.delete(key: 'content_key_$keyId');
      await _secureStorage.delete(key: 'iv_$keyId');
      await _secureStorage.delete(key: 'auth_tag_$keyId');
      
      print('✅ Keys destroyed for: $keyId');
    } catch (e) {
      print('⚠️ Key destruction warning: $e');
    }
  }
  
  // 10. Generate proof of destruction
  static Map<String, dynamic> generateDestructionProof(String contentId, String reason) {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final proofData = '$contentId:$reason:$timestamp';
    final proofHash = sha256.convert(utf8.encode(proofData)).toString();
    
    return {
      'content_id': contentId,
      'reason': reason,
      'timestamp': timestamp,
      'proof_hash': proofHash,
      'signed_by': 'SecureShareSystem',
    };
  }
  
  // 11. Helper: Get MIME type from file path
  static String getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'pdf': return 'application/pdf';
      case 'doc':
      case 'docx': return 'application/msword';
      case 'txt': return 'text/plain';
      case 'mp4': return 'video/mp4';
      case 'mp3': return 'audio/mpeg';
      default: return 'application/octet-stream';
    }
  }
  
  // 12. PBKDF2 implementation
  static Uint8List pbkdf2(Hash hash, List<int> password, List<int> salt, int iterations, int keyLength) {
    final hLen = hash.blockSize;
    final l = (keyLength + hLen - 1) ~/ hLen;
    final t = <Uint8List>[];
    final result = BytesBuilder();
    
    for (var i = 1; i <= l; i++) {
      final u = _f(hash, password, salt, iterations, i);
      t.add(u);
    }
    
    for (final block in t) {
      result.add(block);
    }
    
    return result.toBytes().sublist(0, keyLength);
  }
  
  static Uint8List _f(Hash hash, List<int> password, List<int> salt, int iterations, int i) {
    var u = _hmac(hash, password, Uint8List.fromList([...salt, ..._intToBytes(i)]));
    var result = Uint8List.fromList(u);
    
    for (var j = 1; j < iterations; j++) {
      u = _hmac(hash, password, u);
      for (var k = 0; k < u.length; k++) {
        result[k] ^= u[k];
      }
    }
    
    return result;
  }
  
  static Uint8List _hmac(Hash hash, List<int> key, Uint8List data) {
    final blockSize = hash.blockSize;
    final ipad = Uint8List(blockSize);
    final opad = Uint8List(blockSize);
    
    // Prepare key
    List<int> keyBytes;
    if (key.length > blockSize) {
      keyBytes = hash.convert(key).bytes;
    } else {
      keyBytes = List<int>.from(key);
    }
    
    // Pad key
    for (var i = 0; i < blockSize; i++) {
      if (i < keyBytes.length) {
        ipad[i] = keyBytes[i] ^ 0x36;
        opad[i] = keyBytes[i] ^ 0x5C;
      } else {
        ipad[i] = 0x36;
        opad[i] = 0x5C;
      }
    }
    
    // Inner hash
    final inner = hash.convert([...ipad, ...data]).bytes;
    
    // Outer hash
    return Uint8List.fromList(hash.convert([...opad, ...inner]).bytes);
  }
  
  static List<int> _intToBytes(int i) {
    return [
      (i >> 24) & 0xFF,
      (i >> 16) & 0xFF,
      (i >> 8) & 0xFF,
      i & 0xFF,
    ];
  }
}