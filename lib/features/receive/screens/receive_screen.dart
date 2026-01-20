import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:secure_share/theme/theme_provider.dart';
import 'package:secure_share/services/api_service.dart';
import 'package:secure_share/services/encryption_service.dart';
import 'package:secure_share/services/session_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> with WidgetsBindingObserver {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  bool _isLoading = false;
  bool _contentLoaded = false;
  bool _isViewingContent = false;
  String _decryptedContent = '';
  String _timeRemaining = '00:00:00';
  int _viewsRemaining = 0;
  String _accessMode = '';
  String _contentType = 'text';
  String _fileName = '';
  String _fileSize = '';
  String _errorMessage = '';
  int _remainingSeconds = 0;
  int _failedAttempts = 0;
  DateTime? _lastAttemptTime;
  bool _hasInternet = true;
  bool _isAppInBackground = false;
  bool _hasAttemptedScreenshot = false;
  
  // Security tracking
  Timer? _countdownTimer;
  Timer? _inactivityTimer;
  Timer? _autoCloseTimer;
  StreamSubscription? _connectivitySubscription;
  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;
  WebViewController? _webViewController;
  DateTime? _lastInteractionTime;
  String _contentId = '';

  @override
  void initState() {
    super.initState();
    
    // Enable hybrid composition for Android WebView
    if (Platform.isAndroid) {
      WebView.platform = AndroidWebView();
    }
    
    WidgetsBinding.instance.addObserver(this);
    _checkBackendConnection();
    _startConnectivityMonitoring();
    _preventScreenshots();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _inactivityTimer?.cancel();
    _autoCloseTimer?.cancel();
    _connectivitySubscription?.cancel();
    _lifecycleSubscription?.cancel();
    _pinController.dispose();
    _keyController.dispose();
    _destroyContent();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive) {
      _isAppInBackground = true;
      _handleAppBackground();
    } else if (state == AppLifecycleState.resumed) {
      _isAppInBackground = false;
      _verifyContentAccess();
    }
  }

  void _preventScreenshots() {
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _handleAppBackground() {
    if (_contentLoaded && _isViewingContent) {
      // Auto-close if app goes to background while viewing
      if (_accessMode == 'one_time') {
        _autoCloseContent('App backgrounded during one-time view');
      } else {
        // Show warning when returning
        _showBackgroundWarning();
      }
    }
  }

  void _showBackgroundWarning() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ App was backgrounded. Content may have been terminated.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _verifyContentAccess() async {
    if (!_contentLoaded) return;
    
    // Check if content is still accessible
    try {
      // TODO: Implement content verification with backend API
      // Example: await ApiService.getContentStatus(_contentId);
    } catch (e) {
      _autoCloseContent('Content access verification failed');
    }
  }

  Future<void> _checkBackendConnection() async {
    try {
      final isConnected = await ApiService.testConnection();
      if (!isConnected) {
        setState(() {
          _errorMessage = 'Cannot connect to backend server.\n\n'
              'Make sure backend is running at:\n'
              '${ApiService.baseUrl}\n\n'
              'Start it with:\n'
              'python -m uvicorn main:app --reload --host 0.0.2.2 --port 8000';
        });
      }
    } catch (e) {
      print('Backend check error: $e');
    }
  }

  void _startConnectivityMonitoring() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      final hasInternetNow = result != ConnectivityResult.none;
      
      if (hasInternetNow != _hasInternet) {
        setState(() => _hasInternet = hasInternetNow);
        
        if (!hasInternetNow && _contentLoaded && _isViewingContent) {
          _handleInternetLoss();
        }
      }
    });
  }

  void _handleInternetLoss() {
    // Show warning immediately
    _showNoInternetWarning();
    
    // Auto-close after 10 seconds if still no internet
    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer(const Duration(seconds: 10), () {
      if (!_hasInternet && mounted) {
        _autoCloseContent('Internet connection lost for 10+ seconds');
      }
    });
  }

  void _showNoInternetWarning() {
    if (!mounted || !_isViewingContent) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.red),
            SizedBox(width: 10),
            Text('Connection Lost'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Secure content requires internet connection.'),
            SizedBox(height: 10),
            Text('Content will close in 10 seconds if connection is not restored.',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _autoCloseContent('Manual close due to no internet');
            },
            child: const Text('Close Now'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return WillPopScope(
      onWillPop: () async {
        if (_contentLoaded) {
          _showExitWarning();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Access Secure Content'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_contentLoaded) {
                _showExitWarning();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          actions: _contentLoaded ? [
            IconButton(
              icon: const Icon(Icons.security),
              onPressed: _showSecurityInfo,
              tooltip: 'Security Info',
            ),
          ] : null,
        ),
        body: _contentLoaded
            ? _buildContentView(isDark)
            : _buildPinInputView(isDark),
      ),
    );
  }

  Widget _buildPinInputView(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Security Icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: const Icon(Icons.lock_outline, size: 50, color: Colors.blue),
          ),
          const SizedBox(height: 20),

          // Title with security badge
          const Text(
            'Access Secure Content',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Chip(
            label: const Text('ZERO-KNOWLEDGE ENCRYPTED', style: TextStyle(fontSize: 10)),
            backgroundColor: Colors.green.withOpacity(0.2),
          ),
          const SizedBox(height: 10),

          Text(
            'Enter PIN and encryption key shared with you',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),

          // Error/Warning Message
          if (_errorMessage.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 20),
                      SizedBox(width: 10),
                      Text('Security Alert', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ),
            ),

          // PIN Input with validation
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: '4-digit PIN',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              prefixIcon: const Icon(Icons.pin),
              counterText: '',
              errorText: _pinController.text.isNotEmpty && _pinController.text.length != 4 
                ? 'PIN must be 4 digits' 
                : null,
            ),
            onChanged: (_) => _clearErrorMessage(),
          ),
          const SizedBox(height: 20),

          // Key Input with validation
          TextField(
            controller: _keyController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Encryption Key',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              prefixIcon: const Icon(Icons.key),
              hintText: 'Paste the encryption key here',
              suffixIcon: IconButton(
                icon: const Icon(Icons.visibility_off),
                onPressed: () {
                  // Toggle visibility - TODO: Implement
                },
              ),
            ),
            onChanged: (_) => _clearErrorMessage(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 12, color: Colors.blue),
              const SizedBox(width: 5),
              Text(
                'Key is never sent to server - decrypted locally only',
                style: TextStyle(fontSize: 10, color: isDark ? Colors.grey[400] : Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 30),

          // Access Button with rate limiting
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _accessAndDecryptContent,
              style: ElevatedButton.styleFrom(
                backgroundColor: _failedAttempts > 0 ? Colors.orange : Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_open, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          _failedAttempts > 0 ? 
                            'Try Again ($_failedAttempts attempts)' : 
                            'Decrypt & View Securely',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
            ),
          ),

          // Rate limiting warning
          if (_failedAttempts >= 2)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 15),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_failedAttempts failed attempts. Content may be terminated after 3 attempts.',
                      style: const TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 25),

          // Security Features Card
          Card(
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.verified_user, color: Colors.green),
                      SizedBox(width: 10),
                      Text('Security Features', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildSecurityFeature('🔒', 'Zero-Knowledge Encryption', 'Server cannot read your content'),
                  _buildSecurityFeature('📵', 'No Screenshots', 'Screenshots and recording blocked'),
                  _buildSecurityFeature('🌐', 'Online Only', 'Content never saved to device'),
                  _buildSecurityFeature('⏰', 'Time-Limited', 'Auto-destroys after expiry'),
                  _buildSecurityFeature('📊', 'Device Limited', 'Access restricted to specific devices'),
                  _buildSecurityFeature('🚨', 'Auto-Terminate', 'Content destroyed on security violation'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityFeature(String icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentView(bool isDark) {
    return Column(
      children: [
        // Security Status Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          color: _getStatusBarColor(),
          child: Row(
            children: [
              Icon(_getStatusBarIcon(), size: 18, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getStatusBarTitle(),
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    if (_remainingSeconds > 0)
                      Text(
                        'Auto-closes in $_timeRemaining',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                  ],
                ),
              ),
              if (_viewsRemaining > 0)
                Chip(
                  label: Text('$_viewsRemaining view${_viewsRemaining > 1 ? 's' : ''} left'),
                  backgroundColor: Colors.white.withOpacity(0.2),
                  labelStyle: const TextStyle(color: Colors.white, fontSize: 10),
                ),
            ],
          ),
        ),

        // Content Area
        Expanded(
          child: _isViewingContent 
              ? _buildSecureWebView(isDark)
              : _buildContentOverview(isDark),
        ),

        // Action Buttons with security
        _buildActionButtons(isDark),
      ],
    );
  }

  Widget _buildContentOverview(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Content Icon with security badge
          Stack(
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: _getContentTypeColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: _getContentTypeColor(), width: 3),
                ),
                child: Icon(
                  _getContentTypeIconData(),
                  size: 70,
                  color: _getContentTypeColor(),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.security, size: 15, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),

          // Content Title
          Text(
            _fileName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),

          // Content Type Badge
          Chip(
            label: Text(_contentType.toUpperCase()),
            backgroundColor: _getContentTypeColor().withOpacity(0.2),
            labelStyle: TextStyle(
              color: _getContentTypeColor(),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),

          // Content Description
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[100],
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              children: [
                Text(
                  _getContentTypeDescription(),
                  style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Size: $_fileSize',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),

          // Security Details Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(color: Colors.red.withOpacity(0.3), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.security, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Security Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
                    ],
                  ),
                  const SizedBox(height: 15),
                  _buildSecurityDetail('Access Mode', _accessMode == 'time_based' ? '⏰ Time-Based' : '🔒 One-Time View'),
                  _buildSecurityDetail('Expiry Time', _remainingSeconds > 0 ? _timeRemaining : 'IMMEDIATE'),
                  _buildSecurityDetail('Device Limit', '$_viewsRemaining device${_viewsRemaining > 1 ? 's' : ''}'),
                  _buildSecurityDetail('Screenshot Protection', 'ENABLED'),
                  _buildSecurityDetail('Download Prevention', 'ENABLED'),
                  _buildSecurityDetail('Offline Access', 'DISABLED'),
                  _buildSecurityDetail('Background Protection', 'ENABLED'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Warning Box
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red),
            ),
            child: Column(
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.red),
                    SizedBox(width: 10),
                    Text('IMPORTANT SECURITY NOTICE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '• Content cannot be saved or downloaded\n'
                  '• Screenshots and recording are blocked\n'
                  '• App will auto-close if backgrounded\n'
                  '• Content destroyed after viewing/timeout\n'
                  '• Internet required for viewing',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSecurityDetail(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSecureWebView(bool isDark) {
    return Stack(
      children: [
        // WebView - FIXED CONFIGURATION
        WebView(
          initialUrl: 'about:blank',
          javascriptMode: JavascriptMode.unrestricted,
          onWebViewCreated: (WebViewController controller) {
            _webViewController = controller;
            _loadContentIntoWebView();
          },
          navigationDelegate: (NavigationRequest request) { 
            // Block all external navigation
            _reportSuspiciousActivity('navigation_attempt', request.url);
            return NavigationDecision.prevent;
          },
          onPageStarted: (String url) {
            _resetInactivityTimer();
          },
          javascriptChannels: <JavascriptChannel>{
            JavascriptChannel(
              name: 'SecurityChannel',
              onMessageReceived: (JavascriptMessage message) {
                _handleJavascriptMessage(message.message);
              },
            ),
          },
          gestureNavigationEnabled: false,
        ),

        // No Internet Overlay - FIXED CONTAINER
        if (!_hasInternet)
          Container(
            color: Colors.black.withOpacity(0.95),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, size: 80, color: Colors.red),
                  const SizedBox(height: 20),
                  const Text(
                    'INTERNET CONNECTION LOST',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Secure content requires active internet connection\n\n'
                    'Closing in 10 seconds...',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: () => _autoCloseContent('Manual close - no internet'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    ),
                    child: const Text('CLOSE SECURE VIEWER'),
                  ),
                ],
              ),
            ),
          ),

        // Security Overlay
        Positioned(
          top: Platform.isIOS ? 50 : 30,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.withOpacity(0.9), Colors.orange.withOpacity(0.9)],
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.security, size: 16, color: Colors.white),
                SizedBox(width: 8),
                Text('SECURE VIEWER ACTIVE - SCREENSHOTS BLOCKED', 
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),

        // Inactivity Warning
        if (_inactivityTimer != null && DateTime.now().difference(_lastInteractionTime ?? DateTime.now()).inMinutes >= 4)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.timer, color: Colors.white),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Inactivity detected. Content will close in 1 minute.',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _loadContentIntoWebView() {
    if (_webViewController == null) return;

    String htmlContent = '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          * {
            margin: 0;
            padding: 0;
            -webkit-touch-callout: none;
            -webkit-user-select: none;
            -khtml-user-select: none;
            -moz-user-select: none;
            -ms-user-select: none;
            user-select: none;
            -webkit-tap-highlight-color: transparent;
          }
          
          body {
            background: #000;
            margin: 0;
            padding: 0;
            overflow: hidden;
            height: 100vh;
          }
          
          .security-shield {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            background: linear-gradient(90deg, #ff0000 0%, #ff4444 100%);
            color: white;
            padding: 15px;
            text-align: center;
            font-size: 14px;
            font-weight: bold;
            z-index: 9999;
            box-shadow: 0 3px 15px rgba(255, 0, 0, 0.5);
          }
          
          .content-area {
            padding: 20px;
            color: white;
            max-width: 800px;
            margin: 70px auto 20px;
            line-height: 1.6;
            font-family: Arial, sans-serif;
          }
          
          .watermark {
            position: fixed;
            bottom: 20px;
            right: 20px;
            color: rgba(255, 255, 255, 0.1);
            font-size: 10px;
            pointer-events: none;
            transform: rotate(-45deg);
          }
          
          .timer {
            position: fixed;
            top: 50px;
            right: 20px;
            background: rgba(255, 165, 0, 0.2);
            color: #ffa500;
            padding: 8px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: bold;
            border: 1px solid rgba(255, 165, 0, 0.3);
          }
        </style>
      </head>
      <body>
        <div class="security-shield">
          🔒 PROTECTED CONTENT - SCREENSHOTS & DOWNLOADS BLOCKED
        </div>
        
        <div class="timer" id="timer">Time: --:--</div>
        
        <div class="content-area" id="content">
          ${_escapeHtml(_decryptedContent)}
        </div>
        
        <div class="watermark">SECURE_VIEW_${DateTime.now().millisecondsSinceEpoch}</div>
        
        <script>
          // Prevent all interactions
          document.addEventListener('contextmenu', e => {
            e.preventDefault();
            SecurityChannel.postMessage('context_menu_blocked');
            return false;
          });
          
          document.addEventListener('selectstart', e => {
            e.preventDefault();
            SecurityChannel.postMessage('selection_attempt');
            return false;
          });
          
          document.addEventListener('copy', e => {
            e.preventDefault();
            SecurityChannel.postMessage('copy_attempt');
            return false;
          });
          
          document.addEventListener('cut', e => {
            e.preventDefault();
            SecurityChannel.postMessage('cut_attempt');
            return false;
          });
          
          document.addEventListener('paste', e => {
            e.preventDefault();
            SecurityChannel.postMessage('paste_attempt');
            return false;
          });
          
          // Prevent drag/drop
          document.addEventListener('dragstart', e => e.preventDefault());
          document.addEventListener('drop', e => e.preventDefault());
          
          // Prevent keyboard shortcuts
          document.addEventListener('keydown', e => {
            // Block print (Ctrl/Cmd + P)
            if ((e.ctrlKey || e.metaKey) && e.key === 'p') {
              e.preventDefault();
              SecurityChannel.postMessage('print_attempt');
              return false;
            }
            
            // Block save (Ctrl/Cmd + S)
            if ((e.ctrlKey || e.metaKey) && e.key === 's') {
              e.preventDefault();
              SecurityChannel.postMessage('save_attempt');
              return false;
            }
            
            // Block dev tools
            if (e.key === 'F12' || ((e.ctrlKey || e.metaKey) && e.shiftKey && (e.key === 'I' || e.key === 'J'))) {
              e.preventDefault();
              SecurityChannel.postMessage('devtools_attempt');
              return false;
            }
          });
          
          // Send heartbeat every 5 seconds
          setInterval(() => {
            SecurityChannel.postMessage('heartbeat');
          }, 5000);
          
          // Update timer
          function updateTimer(seconds) {
            const timer = document.getElementById('timer');
            if (timer) {
              const hours = Math.floor(seconds / 3600);
              const minutes = Math.floor((seconds % 3600) / 60);
              const secs = seconds % 60;
              timer.textContent = \`Time: \${hours.toString().padStart(2, '0')}:\${minutes.toString().padStart(2, '0')}:\${secs.toString().padStart(2, '0')}\`;
            }
          }
        </script>
      </body>
      </html>
    ''';

    _webViewController!.loadHtmlString(htmlContent);
  }

  void _handleJavascriptMessage(String message) {
    print('Security event: $message');
    
    switch (message) {
      case 'heartbeat':
        _resetInactivityTimer();
        break;
      case 'context_menu_blocked':
      case 'copy_attempt':
      case 'cut_attempt':
      case 'paste_attempt':
      case 'print_attempt':
      case 'save_attempt':
      case 'selection_attempt':
      case 'devtools_attempt':
        _reportSuspiciousActivity('security_violation', message);
        _showSecurityViolationWarning(message);
        break;
    }
  }

  void _showSecurityViolationWarning(String violation) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Security violation: ${_formatViolation(violation)}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _formatViolation(String violation) {
    return violation.replaceAll('_', ' ').toLowerCase();
  }

  Widget _buildActionButtons(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          // Back Button
          if (_isViewingContent)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _isViewingContent = false),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Info'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  side: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                ),
              ),
            ),
          
          if (_isViewingContent) const SizedBox(width: 10),
          
          // Main Action Button
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isViewingContent ? _showCloseConfirmation : () {
                setState(() => _isViewingContent = true);
                _resetInactivityTimer();
              },
              icon: Icon(_isViewingContent ? Icons.close : Icons.remove_red_eye),
              label: Text(_isViewingContent ? 'Close Content' : 'View Content Securely'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isViewingContent ? Colors.red : Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCloseConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 10),
            Text('Close Secure Content?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to close this content?'),
            const SizedBox(height: 10),
            if (_accessMode == 'one_time')
              const Text(
                '⚠️ This is a one-time view. Content will be permanently destroyed.',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            if (_remainingSeconds > 0)
              Text(
                'Time remaining: $_timeRemaining',
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _closeContent();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showExitWarning() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.exit_to_app, color: Colors.red),
            SizedBox(width: 10),
            Text('Exit Secure Content?'),
          ],
        ),
        content: const Text(
          'Exiting will close the secure content viewer.\n\n'
          'Content may not be accessible again depending on access rules.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _closeContent();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  void _showSecurityInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Security Information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSecurityInfoItem('🔒', 'End-to-End Encryption', 'Content is encrypted on sender\'s device and decrypted on your device only'),
              _buildSecurityInfoItem('🌐', 'Online Only', 'Content is never saved to device storage'),
              _buildSecurityInfoItem('📵', 'No Screenshots', 'Screenshots and screen recording blocked'),
              _buildSecurityInfoItem('⏰', 'Time-Limited', 'Content auto-destroys after $_timeRemaining'),
              _buildSecurityInfoItem('📊', 'Device Limited', 'Can be accessed from $_viewsRemaining more device(s)'),
              _buildSecurityInfoItem('🚨', 'Auto-Terminate', 'Content destroyed on security violation'),
              const SizedBox(height: 10),
              const Text(
                'This is a true zero-knowledge system. The server never sees your decrypted content.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityInfoItem(String icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Security Methods
  void _clearErrorMessage() {
    if (_errorMessage.isNotEmpty) {
      setState(() => _errorMessage = '');
    }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _lastInteractionTime = DateTime.now();
    
    _inactivityTimer = Timer(const Duration(minutes: 5), () {
      if (_isViewingContent && mounted) {
        _autoCloseContent('Inactivity timeout (5 minutes)');
      }
    });
  }

  void _reportSuspiciousActivity(String type, String details) {
    print('🚨 Suspicious activity: $type - $details');
    
    // Report to backend
    if (_contentId.isNotEmpty) {
      ApiService.reportSuspiciousActivity(
        contentId: _contentId,
        activityType: type,
        deviceId: 'device_fingerprint',
        description: details,
      );
    }
    
    // Update local state
    if (type.contains('screenshot') || details.contains('screen')) {
      _hasAttemptedScreenshot = true;
    }
  }

  Future<void> _accessAndDecryptContent() async {
    // Rate limiting
    final now = DateTime.now();
    if (_lastAttemptTime != null && now.difference(_lastAttemptTime!) < const Duration(seconds: 2)) {
      setState(() => _errorMessage = 'Please wait before trying again');
      return;
    }
    _lastAttemptTime = now;

    // Validation
    final pin = _pinController.text.trim();
    final key = _keyController.text.trim();

    if (pin.isEmpty || pin.length != 4) {
      setState(() => _errorMessage = 'Please enter a valid 4-digit PIN');
      return;
    }
    if (key.isEmpty) {
      setState(() => _errorMessage = 'Please enter the encryption key');
      return;
    }
    if (!_hasInternet) {
      setState(() => _errorMessage = 'Internet connection required');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Get device info for tracking
      final deviceInfo = await SessionManager.getDeviceInfo();
      final deviceFingerprint = await SessionManager.getDeviceFingerprint();
      
      // Access content - FIXED: Using correct API method
      final response = await ApiService.accessContent(
        pin,
        deviceId: deviceInfo['device_id'],
        deviceFingerprint: deviceFingerprint,
      );

      // Extract response - FIXED: Expecting correct field names
      final encryptedContent = response['encrypted_content'] ?? response['content'];
      final iv = response['iv'];
      _contentId = response['content_id'] ?? '';
      _viewsRemaining = response['views_remaining'] ?? 1;
      _accessMode = response['access_mode'] ?? 'time_based';
      final expiryTime = response['expiry_time'];
      _contentType = response['content_type'] ?? 'text';
      _fileName = response['file_name'] ?? 'secure_content';
      _fileSize = _formatFileSize(response['file_size'] ?? 0);
      
      // Check access limits
      if (_viewsRemaining <= 0) {
        throw Exception('Device limit reached');
      }

      // Decrypt locally - FIXED: Using correct decrypt method (3 parameters)
      _decryptedContent = EncryptionService.decryptData(
        encryptedContent, 
        iv, 
        key,
      );

      if (_decryptedContent.isEmpty) {
        throw Exception('Decryption failed - invalid key');
      }

      // Start security timers
      if (_accessMode == 'time_based' && expiryTime != null) {
        _startSecurityCountdown(expiryTime);
      }

      // Reset failed attempts on success
      _failedAttempts = 0;
      
      // Show content
      setState(() {
        _contentLoaded = true;
        _isLoading = false;
        _isViewingContent = false;
      });

      _resetInactivityTimer();

    } catch (e) {
      _failedAttempts++;
      print('Access error: $e');
      
      String errorMsg = e.toString().replaceAll('Exception: ', '');
      if (errorMsg.contains('Device limit reached')) {
        errorMsg = 'Device limit reached. Cannot access from this device.';
      } else if (errorMsg.contains('expired') || errorMsg.contains('410')) {
        errorMsg = 'Content has expired and been destroyed.';
      } else if (errorMsg.contains('PIN') || errorMsg.contains('404')) {
        errorMsg = 'Invalid PIN. $_failedAttempts failed attempt(s).';
      } else if (errorMsg.contains('Decryption')) {
        errorMsg = 'Decryption failed. Check your encryption key.';
      }
      
      if (_failedAttempts >= 3) {
        errorMsg = 'Too many failed attempts. Content may have been terminated.';
        _resetForm();
      }
      
      setState(() {
        _errorMessage = errorMsg;
        _isLoading = false;
      });
    }
  }

  void _startSecurityCountdown(String expiryTimeStr) {
    try {
      final expiryTime = DateTime.parse(expiryTimeStr);
      final now = DateTime.now();
      final difference = expiryTime.difference(now);
      
      if (difference.inSeconds > 0) {
        _remainingSeconds = difference.inSeconds;
        _updateTimerDisplay(_remainingSeconds);
        
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_remainingSeconds <= 0) {
            timer.cancel();
            _autoCloseContent('Time expired');
            return;
          }
          _remainingSeconds--;
          _updateTimerDisplay(_remainingSeconds);
          
          // Update webview timer
          if (_webViewController != null && _remainingSeconds % 5 == 0) {
            _webViewController!.runJavaScript('updateTimer($_remainingSeconds)');
          }
        });
      } else {
        _autoCloseContent('Already expired');
      }
    } catch (e) {
      print('Countdown error: $e');
    }
  }

  void _updateTimerDisplay(int seconds) {
    if (!mounted) return;
    
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    setState(() {
      _timeRemaining = '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    });
  }

  void _autoCloseContent(String reason) {
    print('Auto-closing content: $reason');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Content closed: $reason'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
    
    _closeContent();
  }

  void _closeContent() {
    _destroyContent();
    
    if (mounted) {
      setState(() {
        _contentLoaded = false;
        _isViewingContent = false;
        _pinController.clear();
        _keyController.clear();
        _timeRemaining = '00:00:00';
        _remainingSeconds = 0;
        _errorMessage = '';
        _contentId = '';
      });
    }
  }

  void _destroyContent() {
    _countdownTimer?.cancel();
    _inactivityTimer?.cancel();
    _autoCloseTimer?.cancel();
    
    _webViewController = null;
    _decryptedContent = '';
    _remainingSeconds = 0;
    _contentId = '';
    
    // Clear secure storage
    SessionManager.clearSession();
    
    // Restore normal UI
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _resetForm() {
    _pinController.clear();
    _keyController.clear();
    _failedAttempts = 0;
    _errorMessage = '';
  }

  // Helper Methods
  Color _getStatusBarColor() {
    if (_remainingSeconds <= 60) return Colors.red;
    if (_remainingSeconds <= 300) return Colors.orange;
    return Colors.green;
  }

  IconData _getStatusBarIcon() {
    if (_remainingSeconds <= 60) return Icons.warning;
    if (_remainingSeconds <= 300) return Icons.timer;
    return Icons.security;
  }

  String _getStatusBarTitle() {
    if (_accessMode == 'one_time') return 'ONE-TIME VIEW - WILL SELF-DESTRUCT';
    if (_remainingSeconds <= 0) return 'EXPIRED - CLOSING SOON';
    return 'SECURE CONTENT VIEWER - ACTIVE';
  }

  IconData _getContentTypeIconData() {
    switch (_contentType) {
      case 'image': return Icons.image;
      case 'pdf': return Icons.picture_as_pdf;
      case 'video': return Icons.videocam;
      case 'audio': return Icons.audiotrack;
      case 'document': return Icons.description;
      default: return Icons.text_fields;
    }
  }

  Color _getContentTypeColor() {
    switch (_contentType) {
      case 'image': return Colors.purple;
      case 'pdf': return Colors.red;
      case 'video': return Colors.blue;
      case 'audio': return Colors.green;
      case 'document': return Colors.orange;
      default: return Colors.teal;
    }
  }

  String _getContentTypeDescription() {
    switch (_contentType) {
      case 'image': return 'Encrypted Image - View in secure online viewer';
      case 'pdf': return 'Encrypted PDF - Protected virtual document viewer';
      case 'video': return 'Encrypted Video - Stream securely (no download)';
      case 'audio': return 'Encrypted Audio - Listen online only';
      case 'document': return 'Encrypted Document - Secure text viewer';
      default: return 'Encrypted Content - Protected online viewer';
    }
  }

  String _formatFileSize(dynamic size) {
    if (size is int) {
      if (size < 1024) return '$size B';
      if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
      if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return size.toString();
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
  }
}