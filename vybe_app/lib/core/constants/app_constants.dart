import 'package:flutter/foundation.dart';

class AppConstants {
  static const String appName = 'VYBE';
  static const String appTagline = 'Voice-First Social Discovery';

  // Production Render Cloud Server
  static const String _cloudBaseUrl = 'https://dateingapp.onrender.com';

  // Set to true if you want to test against local machine
  static const bool useLocalhost = false;

  static String get apiBaseUrl {
    if (useLocalhost) {
      if (kIsWeb) return 'http://localhost:5000/api/v1';
      if (defaultTargetPlatform == TargetPlatform.android) {
        return 'http://10.0.2.2:5000/api/v1';
      }
      return 'http://localhost:5000/api/v1';
    }
    return '$_cloudBaseUrl/api/v1';
  }

  static String get socketUrl {
    if (useLocalhost) {
      if (kIsWeb) return 'http://localhost:5000';
      if (defaultTargetPlatform == TargetPlatform.android) {
        return 'http://10.0.2.2:5000';
      }
      return 'http://localhost:5000';
    }
    return _cloudBaseUrl;
  }

  // Agora App ID fallback
  static const String defaultAgoraAppId = 'test_agora_app_id_vybe';

  // Storage keys
  static const String tokenKey = 'vybe_auth_token';
  static const String userIdKey = 'vybe_user_id';
  static const String hasCompletedOnboardingKey = 'vybe_completed_onboarding';
}
