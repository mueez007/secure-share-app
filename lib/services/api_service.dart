import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

class ApiService {
  static String _baseUrl = Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
  static final Connectivity _connectivity = Connectivity();

  static void setBaseUrl(String url) {
    _baseUrl = url;
  }

  static String get baseUrl => _baseUrl;

  // 1. Connection Test
  static Future<bool> testConnection() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 3));

      return response.statusCode == 200;
    } catch (e) {
      print('Connection Error: $e');
      return false;
    }
  }

  // 2. Upload Content - ZERO-KNOWLEDGE VERSION
  static Future<Map<String, dynamic>> uploadContent({
    required Uint8List encryptedBytes,
    required String iv,
    required String accessMode,
    int? durationMinutes,
    int deviceLimit = 1,
    String contentType = 'text',
    String? fileName,
    int? fileSize,
    String? mimeType,
    bool dynamicPIN = false,
    int? pinRotationMinutes,
    bool autoTerminateOnSuspicion = true,
    bool requireBiometric = false,
    List<String>? trustedDevices,
    // NEW: Zero-knowledge parameters
    required String pin, // 4-digit PIN generated locally
    required String keyHash, // Hash of encryption key
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/content/upload');
      
      var request = http.MultipartRequest('POST', uri);
      
      // Add encrypted file
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        encryptedBytes,
        filename: fileName ?? 'secure_content.dat',
      ));
      
      // Add form fields - ZERO-KNOWLEDGE
      request.fields['iv'] = iv;
      request.fields['access_mode'] = accessMode;
      request.fields['device_limit'] = deviceLimit.toString();
      request.fields['content_type'] = contentType;
      request.fields['auto_terminate'] = autoTerminateOnSuspicion.toString();
      request.fields['require_biometric'] = requireBiometric.toString();
      request.fields['dynamic_pin'] = dynamicPIN.toString();
      
      // ZERO-KNOWLEDGE CRITICAL FIELDS
      request.fields['pin'] = pin; // Client-generated PIN
      request.fields['key_hash'] = keyHash; // Hash of encryption key
      
      // Optional fields
      if (durationMinutes != null) {
        request.fields['duration_minutes'] = durationMinutes.toString();
      }
      if (fileName != null) {
        request.fields['file_name'] = fileName;
      }
      if (fileSize != null) {
        request.fields['file_size'] = fileSize.toString();
      }
      if (mimeType != null) {
        request.fields['mime_type'] = mimeType;
      }
      if (pinRotationMinutes != null) {
        request.fields['pin_rotation_minutes'] = pinRotationMinutes.toString();
      }
      if (trustedDevices != null && trustedDevices.isNotEmpty) {
        request.fields['trusted_devices'] = jsonEncode(trustedDevices);
      }
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Upload failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('❌ Upload error: $e');
      rethrow;
    }
  }

  // 3. Access Content - UPDATED FOR ZERO-KNOWLEDGE
  static Future<Map<String, dynamic>> accessContent(
    String pin, {
    String? deviceId,
    String? deviceFingerprint,
    bool biometricVerified = false,
    String? keyHash, // Optional: for key verification
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/content/access/$pin');
      
      final body = {
        'device_id': deviceId ?? 'unknown_device',
        'device_fingerprint': deviceFingerprint,
        'biometric_verified': biometricVerified,
        'platform': Platform.operatingSystem,
        if (keyHash != null) 'key_hash': keyHash, // Include key hash for verification
      };
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('PIN not found');
      } else if (response.statusCode == 410) {
        throw Exception('Content expired or destroyed');
      } else if (response.statusCode == 401) {
        throw Exception('Invalid PIN or encryption key');
      } else {
        throw Exception('Access failed: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Access error: $e');
      rethrow;
    }
  }

  // 4. Stream Content
  static Future<Uint8List> streamContent(String contentId, String sessionToken) async {
    try {
      final url = Uri.parse('$_baseUrl/content/stream/$contentId?session_token=$sessionToken');
      
      final response = await http.get(
        url,
        headers: {'Accept': 'application/octet-stream'},
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('Stream failed: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Stream error: $e');
      rethrow;
    }
  }

  // 5. Report Suspicious Activity
  static Future<void> reportSuspiciousActivity({
    required String contentId,
    required String activityType,
    required String deviceId,
    String? description,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/security/report');
      
      final body = {
        'content_id': contentId,
        'activity_type': activityType,
        'device_id': deviceId,
        'description': description ?? '',
      };
      
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      print('⚠️ Failed to report suspicious activity: $e');
    }
  }

  // 6. Terminate Content
  static Future<void> terminateContent(String contentId) async {
    try {
      final url = Uri.parse('$_baseUrl/content/$contentId/terminate');
      
      await http.post(url).timeout(const Duration(seconds: 5));
    } catch (e) {
      print('⚠️ Failed to terminate content: $e');
    }
  }

  // 7. Get Content Analytics
  static Future<Map<String, dynamic>> getContentAnalytics(String contentId) async {
    try {
      final url = Uri.parse('$_baseUrl/content/$contentId/analytics');
      
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get analytics: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ Failed to get analytics: $e');
      rethrow;
    }
  }
}