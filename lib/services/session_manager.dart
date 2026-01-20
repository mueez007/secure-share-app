import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SessionManager {
  static final FlutterSecureStorage _storage = FlutterSecureStorage();
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      Map<String, dynamic> deviceData;
      
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceData = {
          'platform': 'android',
          'device_id': androidInfo.id,
          'model': androidInfo.model,
          'brand': androidInfo.brand,
          'device': androidInfo.device,
          'product': androidInfo.product,
          'version': androidInfo.version.release,
          'fingerprint': androidInfo.fingerprint,
          'is_physical_device': androidInfo.isPhysicalDevice,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceData = {
          'platform': 'ios',
          'device_id': iosInfo.identifierForVendor,
          'model': iosInfo.model,
          'name': iosInfo.name,
          'system_name': iosInfo.systemName,
          'system_version': iosInfo.systemVersion,
          'is_physical_device': iosInfo.isPhysicalDevice,
        };
      } else {
        deviceData = {
          'platform': Platform.operatingSystem,
          'device_id': 'unknown',
        };
      }
      
      // Add app info
      final packageInfo = await PackageInfo.fromPlatform();
      deviceData['app_version'] = packageInfo.version;
      deviceData['app_build'] = packageInfo.buildNumber;
      
      // Generate session ID
      final sessionId = '${deviceData['device_id']}_${DateTime.now().millisecondsSinceEpoch}';
      deviceData['session_id'] = sessionId;
      
      // Store session info
      await _storage.write(key: 'current_session', value: jsonEncode(deviceData));
      
      return deviceData;
    } catch (e) {
      print('Device info error: $e');
      return {
        'platform': Platform.operatingSystem,
        'device_id': 'unknown_${DateTime.now().millisecondsSinceEpoch}',
        'session_id': 'session_${DateTime.now().millisecondsSinceEpoch}',
      };
    }
  }
  
  static Future<String> getDeviceFingerprint() async {
    try {
      final deviceInfo = await getDeviceInfo();
      final fingerprintData = {
        'device_id': deviceInfo['device_id'],
        'model': deviceInfo['model'],
        'platform': deviceInfo['platform'],
        'app_version': deviceInfo['app_version'],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      return sha256.convert(utf8.encode(jsonEncode(fingerprintData))).toString();
    } catch (e) {
      return 'fingerprint_error_${DateTime.now().millisecondsSinceEpoch}';
    }
  }
  
  static Future<void> storeAccessToken(String contentId, String token) async {
    await _storage.write(key: 'access_token_$contentId', value: token);
  }
  
  static Future<String?> getAccessToken(String contentId) async {
    return await _storage.read(key: 'access_token_$contentId');
  }
  
  static Future<void> clearSession() async {
    await _storage.deleteAll();
  }
  
  static Future<bool> isTrustedDevice(String contentId) async {
    final trustedDevices = await _storage.read(key: 'trusted_devices_$contentId');
    if (trustedDevices == null) return false;
    
    final currentDevice = await getDeviceFingerprint();
    final devices = jsonDecode(trustedDevices) as List;
    
    return devices.contains(currentDevice);
  }
  
  static Future<void> addTrustedDevice(String contentId, String deviceFingerprint) async {
    final current = await _storage.read(key: 'trusted_devices_$contentId');
    List devices = current != null ? jsonDecode(current) as List : [];
    
    if (!devices.contains(deviceFingerprint)) {
      devices.add(deviceFingerprint);
      await _storage.write(
        key: 'trusted_devices_$contentId',
        value: jsonEncode(devices),
      );
    }
  }
}