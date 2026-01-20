import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

class ApiService {
  static String _baseUrl = Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
  static final Connectivity _connectivity = Connectivity();
  
  // Set custom base URL
  static void setBaseUrl(String url) {
    _baseUrl = url;
  }
  
  // Enhanced connection test
  static Future<Map<String, dynamic>> testConnection() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        throw Exception('No internet connection');
      }
      
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'connected': true,
          'message': data['message'],
          'version': data['version'],
          'uptime': data['uptime'],
        };
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Connection failed: $e');
    }
  }
  
  // Upload content with all features
  static Future<Map<String, dynamic>> uploadContent({
    required Map<String, dynamic> encryptedData,
    required String accessMode,
    int? durationMinutes,
    int deviceLimit = 1,
    String contentType = 'text',
    String? fileName,
    int? fileSize,
    String? mimeType,
    bool dynamicPIN = false,
    int? pinRotationMinutes,
    bool autoTerminateOnSuspicion = false,
    bool requireBiometric = false,
    List<String>? trustedDevices,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/content/upload');
      
      print('📤 Uploading $contentType content...');
      
      final body = {
        'encrypted_content': encryptedData['content'],
        'iv': encryptedData['iv'],
        'auth_tag': encryptedData['auth_tag'],
        'access_mode': accessMode,
        'duration_minutes': durationMinutes,
        'device_limit': deviceLimit,
        'content_type': contentType,
        'file_name': fileName,
        'file_size': fileSize,
        'mime_type': mimeType,
        'security_options': {
          'dynamic_pin': dynamicPIN,
          'pin_rotation_minutes': pinRotationMinutes,
          'auto_terminate_on_suspicion': autoTerminateOnSuspicion,
          'require_biometric': requireBiometric,
          'trusted_devices': trustedDevices,
        },
        'encryption_algo': encryptedData['encryption_algo'] ?? 'AES-256-GCM',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Request-ID': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('✅ Upload successful! PIN: ${data['pin']}');
        return data;
      } else {
        throw Exception('Upload failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('❌ Upload error: $e');
      rethrow;
    }
  }
  
  // Access content with device tracking
  static Future<Map<String, dynamic>> accessContent(
    String pin, {
    String? deviceId,
    String? deviceFingerprint,
    bool biometricVerified = false,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/content/access/$pin');
      
      print('🔑 Accessing content with PIN: $pin');
      
      final body = {
        'device_id': deviceId ?? 'unknown_device',
        'device_fingerprint': deviceFingerprint,
        'biometric_verified': biometricVerified,
        'access_time': DateTime.now().toUtc().toIso8601String(),
        'client_version': '1.0.0',
        'platform': Platform.operatingSystem,
      };
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Invalid PIN or access denied');
      } else if (response.statusCode == 403) {
        throw Exception('Device limit reached or unauthorized device');
      } else if (response.statusCode == 410) {
        throw Exception('Content expired or already viewed');
      } else if (response.statusCode == 423) {
        throw Exception('Content is paused by sender');
      } else if (response.statusCode == 429) {
        throw Exception('Too many failed attempts. Try again later');
      } else {
        throw Exception('Access failed: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Access error: $e');
      rethrow;
    }
  }
  
  // Sender: Get content status
  static Future<Map<String, dynamic>> getContentStatus(String contentId, String authToken) async {
    final url = Uri.parse('$_baseUrl/content/status/$contentId');
    
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $authToken',
        'Accept': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to get status: ${response.statusCode}');
  }
  
  // Sender: Get analytics
  static Future<Map<String, dynamic>> getContentAnalytics(String contentId, String authToken) async {
    final url = Uri.parse('$_baseUrl/content/analytics/$contentId');
    
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $authToken',
        'Accept': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to get analytics: ${response.statusCode}');
  }
  
  // Sender: Pause content
  static Future<void> pauseContent(String contentId, String authToken) async {
    final url = Uri.parse('$_baseUrl/content/pause/$contentId');
    
    final response = await http.post(
      url,
      headers: {'Authorization': 'Bearer $authToken'},
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to pause content: ${response.statusCode}');
    }
  }
  
  // Sender: Resume content
  static Future<void> resumeContent(String contentId, String authToken) async {
    final url = Uri.parse('$_baseUrl/content/resume/$contentId');
    
    final response = await http.post(
      url,
      headers: {'Authorization': 'Bearer $authToken'},
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to resume content: ${response.statusCode}');
    }
  }
  
  // Sender: Extend content
  static Future<void> extendContent(
    String contentId,
    String authToken, {
    int? additionalMinutes,
    int? additionalDevices,
  }) async {
    final url = Uri.parse('$_baseUrl/content/extend/$contentId');
    
    final body = {
      'additional_minutes': additionalMinutes,
      'additional_devices': additionalDevices,
    };
    
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to extend content: ${response.statusCode}');
    }
  }
  
  // Sender: Terminate content (instant destruction)
  static Future<Map<String, dynamic>> terminateContent(
    String contentId,
    String authToken, {
    String reason = 'manual_termination',
  }) async {
    final url = Uri.parse('$_baseUrl/content/terminate/$contentId');
    
    final body = {'reason': reason};
    
    final response = await http.delete(
      url,
      headers: {
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to terminate content: ${response.statusCode}');
  }
  
  // Sender: Get history
  static Future<List<dynamic>> getSenderHistory(String authToken) async {
    final url = Uri.parse('$_baseUrl/sender/history');
    
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $authToken'},
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to get history: ${response.statusCode}');
  }
  
  // Receiver: Stream content (for large files)
  static Future<http.StreamedResponse> streamContent(
    String contentId,
    String accessToken,
  ) async {
    final url = Uri.parse('$_baseUrl/content/stream/$contentId');
    
    final request = http.Request('GET', url);
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.headers['Accept'] = 'application/octet-stream';
    
    return await request.send();
  }
  
  // Report suspicious activity
  static Future<void> reportSuspiciousActivity(
    String contentId,
    String activityType,
    String deviceId,
  ) async {
    final url = Uri.parse('$_baseUrl/security/report');
    
    final body = {
      'content_id': contentId,
      'activity_type': activityType,
      'device_id': deviceId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    
    await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }
}