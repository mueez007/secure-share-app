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

  // 1. Connection Test - FIXED SIGNATURE
  static Future<bool> testConnection() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/'), // Your backend root endpoint
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 3));

      return response.statusCode == 200;
    } catch (e) {
      print('Connection Error: $e');
      return false;
    }
  }

  // 2. Upload Content - FIXED to match ShareScreen call
  static Future<Map<String, dynamic>> uploadContent({
    required Uint8List encryptedBytes, // Keep this as Uint8List
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
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/content/upload'); // Fixed endpoint
      
      // Create multipart request
      var request = http.MultipartRequest('POST', uri);
      
      // Add encrypted file
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        encryptedBytes,
        filename: fileName ?? 'secure_content.dat',
      ));
      
      // Add form fields
      request.fields['iv'] = iv;
      request.fields['access_mode'] = accessMode;
      request.fields['device_limit'] = deviceLimit.toString();
      request.fields['content_type'] = contentType;
      request.fields['auto_terminate'] = autoTerminateOnSuspicion.toString();
      request.fields['require_biometric'] = requireBiometric.toString();
      request.fields['dynamic_pin'] = dynamicPIN.toString();
      
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

  // 3. Access Content - FIXED SIGNATURE
  static Future<Map<String, dynamic>> accessContent(
    String pin, {
    String? deviceId,
    String? deviceFingerprint,
    bool biometricVerified = false,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/content/access/$pin');
      
      final body = {
        'device_id': deviceId ?? 'unknown_device',
        'device_fingerprint': deviceFingerprint,
        'biometric_verified': biometricVerified,
        'platform': Platform.operatingSystem,
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
      } else {
        throw Exception('Access failed: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Access error: $e');
      rethrow;
    }
  }

  // 4. Report Suspicious Activity - ADDED
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
}