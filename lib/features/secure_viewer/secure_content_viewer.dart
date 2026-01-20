import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';

class SecureContentViewer extends StatefulWidget {
  final String contentData;
  final String contentType;
  final String contentId;
  final String fileName;
  final int? expiryTime;
  final bool isOneTimeView;
  final VoidCallback onContentClosed;
  final Function(String) onSuspiciousActivity;

  const SecureContentViewer({
    super.key,
    required this.contentData,
    required this.contentType,
    required this.contentId,
    required this.fileName,
    this.expiryTime,
    this.isOneTimeView = false,
    required this.onContentClosed,
    required this.onSuspiciousActivity,
  });

  @override
  State<SecureContentViewer> createState() => _SecureContentViewerState();
}

class _SecureContentViewerState extends State<SecureContentViewer> with WidgetsBindingObserver {
  late final WebViewController _controller;
  late final Connectivity _connectivity;
  StreamSubscription? _connectivitySubscription;
  StreamSubscription? _lifecycleSubscription;
  Timer? _expiryTimer;
  Timer? _inactivityTimer;
  DateTime? _lastInteraction;
  bool _hasInternet = true;
  bool _isContentProtected = true;
  bool _isAppInBackground = false;
  int _failedCaptureAttempts = 0;

  @override
  void initState() {
    super.initState();
    
    // Prevent screenshots
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (Platform.isAndroid) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.dark,
      ));
    }
    
    _connectivity = Connectivity();
    _initializeWebView();
    _startMonitoring();
    _startExpiryTimer();
    _resetInactivityTimer();
    
    WidgetsBinding.instance.addObserver(this);
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          // Block all external navigation
          if (request.url.startsWith('http')) {
            _reportSuspiciousActivity('navigation_attempt', request.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageStarted: (url) {
          print('Page started: $url');
        },
        onPageFinished: (url) {
          print('Page finished: $url');
          _injectProtectionScripts();
        },
      ))
      ..addJavaScriptChannel('SecureShare', onMessageReceived: (message) {
        _handleJavaScriptMessage(message.message);
      });

    // Load content based on type
    _loadContent();
  }

  void _loadContent() {
    String htmlContent;
    
    switch (widget.contentType) {
      case 'text':
        htmlContent = _buildTextHtml();
        break;
      case 'image':
        htmlContent = _buildImageHtml();
        break;
      case 'pdf':
        htmlContent = _buildPdfHtml();
        break;
      case 'video':
        htmlContent = _buildVideoHtml();
        break;
      case 'audio':
        htmlContent = _buildAudioHtml();
        break;
      default:
        htmlContent = _buildGenericHtml();
    }
    
    _controller.loadHtmlString(htmlContent);
  }

  String _buildTextHtml() {
    return '''
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
            color: #fff;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            padding: 20px;
            line-height: 1.6;
            overflow-x: hidden;
            min-height: 100vh;
            position: relative;
          }
          
          .security-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            background: linear-gradient(90deg, #ff0000 0%, #ff4444 100%);
            color: white;
            padding: 12px;
            text-align: center;
            font-size: 14px;
            font-weight: bold;
            z-index: 9999;
            box-shadow: 0 2px 10px rgba(255, 0, 0, 0.3);
          }
          
          .content-container {
            max-width: 800px;
            margin: 60px auto 20px;
            padding: 30px;
            background: rgba(255, 255, 255, 0.05);
            border-radius: 15px;
            border: 1px solid rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
          }
          
          .content {
            font-size: 18px;
            white-space: pre-wrap;
            word-wrap: break-word;
          }
          
          .watermark {
            position: fixed;
            bottom: 20px;
            right: 20px;
            color: rgba(255, 255, 255, 0.1);
            font-size: 12px;
            pointer-events: none;
            user-select: none;
          }
          
          .expiry-timer {
            position: fixed;
            top: 60px;
            right: 20px;
            background: rgba(255, 165, 0, 0.2);
            color: #ffa500;
            padding: 8px 15px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: bold;
            border: 1px solid rgba(255, 165, 0, 0.3);
          }
          
          @media (max-width: 768px) {
            .content-container {
              padding: 20px;
              margin: 50px 10px 10px;
            }
            
            .content {
              font-size: 16px;
            }
          }
        </style>
      </head>
      <body>
        <div class="security-overlay">
          🔒 PROTECTED CONTENT - Screenshots and downloads blocked
        </div>
        
        ${widget.expiryTime != null ? 
          '<div class="expiry-timer" id="expiryTimer">Time remaining: --:--</div>' : 
          '<div class="expiry-timer">🔒 One-Time View</div>'
        }
        
        <div class="content-container">
          <div class="content">${_escapeHtml(widget.contentData)}</div>
        </div>
        
        <div class="watermark" id="watermark">${widget.contentId}</div>
        
        <script>
          // Prevent context menu
          document.addEventListener('contextmenu', function(e) {
            e.preventDefault();
            SecureShare.postMessage('context_menu_blocked');
            return false;
          });
          
          // Prevent text selection
          document.addEventListener('selectstart', function(e) {
            e.preventDefault();
            return false;
          });
          
          // Prevent drag/drop
          document.addEventListener('dragstart', function(e) {
            e.preventDefault();
            return false;
          });
          
          // Prevent copy/paste
          document.addEventListener('copy', function(e) {
            e.preventDefault();
            SecureShare.postMessage('copy_attempt');
            return false;
          });
          
          document.addEventListener('cut', function(e) {
            e.preventDefault();
            SecureShare.postMessage('cut_attempt');
            return false;
          });
          
          document.addEventListener('paste', function(e) {
            e.preventDefault();
            SecureShare.postMessage('paste_attempt');
            return false;
          });
          
          // Detect dev tools
          let devToolsOpen = false;
          const element = new Image();
          Object.defineProperty(element, 'id', {
            get: function() {
              devToolsOpen = true;
              SecureShare.postMessage('devtools_detected');
            }
          });
          
          console.log('%c', element);
          
          // Update expiry timer
          function updateTimer(seconds) {
            const timer = document.getElementById('expiryTimer');
            if (timer) {
              const hours = Math.floor(seconds / 3600);
              const minutes = Math.floor((seconds % 3600) / 60);
              const secs = seconds % 60;
              timer.textContent = \`Time remaining: \${hours.toString().padStart(2, '0')}:\${minutes.toString().padStart(2, '0')}:\${secs.toString().padStart(2, '0')}\`;
            }
          }
          
          // Make timer function available globally
          window.updateExpiryTimer = updateTimer;
        </script>
      </body>
      </html>
    ''';
  }

  String _buildImageHtml() {
    return '''
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
          }
          
          body {
            background: #000;
            margin: 0;
            padding: 0;
            overflow: hidden;
            height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
          }
          
          .image-container {
            position: relative;
            max-width: 100%;
            max-height: 100%;
          }
          
          img {
            max-width: 100%;
            max-height: 100vh;
            object-fit: contain;
            display: block;
          }
          
          .protection-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            background: rgba(255, 0, 0, 0.9);
            color: white;
            padding: 15px;
            text-align: center;
            font-size: 16px;
            font-weight: bold;
            z-index: 9999;
            box-shadow: 0 3px 15px rgba(255, 0, 0, 0.5);
          }
          
          .watermark {
            position: fixed;
            bottom: 20px;
            right: 20px;
            color: rgba(255, 255, 255, 0.1);
            font-size: 10px;
            transform: rotate(-45deg);
            pointer-events: none;
          }
        </style>
      </head>
      <body>
        <div class="protection-overlay">
          🔒 PROTECTED IMAGE - Screenshots blocked • Content will close if app backgrounded
        </div>
        
        <div class="image-container">
          <img src="${widget.contentData}" 
               onerror="SecureShare.postMessage('image_load_error')"
               ondragstart="return false;" />
        </div>
        
        <div class="watermark">${widget.contentId}</div>
        
        <script>
          // Prevent all interactions
          document.addEventListener('contextmenu', e => {
            e.preventDefault();
            SecureShare.postMessage('image_context_menu');
            return false;
          });
          
          // Prevent long press
          let touchStartTime;
          document.addEventListener('touchstart', e => {
            touchStartTime = Date.now();
          });
          
          document.addEventListener('touchend', e => {
            const duration = Date.now() - touchStartTime;
            if (duration > 1000) { // Long press detection
              e.preventDefault();
              SecureShare.postMessage('long_press_detected');
            }
          });
          
          // Add invisible overlay to prevent image saving
          const img = document.querySelector('img');
          if (img) {
            img.style.pointerEvents = 'none';
          }
        </script>
      </body>
      </html>
    ''';
  }

  String _buildPdfHtml() {
    return '''
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
          }
          
          body {
            background: #000;
            margin: 0;
            padding: 0;
            overflow: hidden;
            height: 100vh;
          }
          
          .protection-banner {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            background: linear-gradient(90deg, #ff0000, #ff8800);
            color: white;
            padding: 15px;
            text-align: center;
            font-size: 16px;
            font-weight: bold;
            z-index: 9999;
            box-shadow: 0 3px 15px rgba(255, 0, 0, 0.5);
          }
          
          iframe {
            width: 100%;
            height: 100vh;
            border: none;
            margin-top: 50px;
          }
          
          .watermark {
            position: fixed;
            bottom: 10px;
            right: 10px;
            color: rgba(255, 255, 255, 0.1);
            font-size: 8px;
            pointer-events: none;
          }
        </style>
      </head>
      <body>
        <div class="protection-banner">
          🔒 PROTECTED PDF - Online view only • No printing/downloading
        </div>
        
        <iframe src="${widget.contentData}#toolbar=0&navpanes=0&scrollbar=0&view=FitH"></iframe>
        
        <div class="watermark">${widget.contentId}</div>
        
        <script>
          // Block all iframe interactions
          document.addEventListener('contextmenu', e => {
            e.preventDefault();
            SecureShare.postMessage('pdf_context_menu');
            return false;
          });
          
          // Prevent keyboard shortcuts
          document.addEventListener('keydown', e => {
            // Block print (Ctrl/Cmd + P)
            if ((e.ctrlKey || e.metaKey) && e.key === 'p') {
              e.preventDefault();
              SecureShare.postMessage('print_attempt');
              return false;
            }
            
            // Block save (Ctrl/Cmd + S)
            if ((e.ctrlKey || e.metaKey) && e.key === 's') {
              e.preventDefault();
              SecureShare.postMessage('save_attempt');
              return false;
            }
            
            // Block dev tools (F12, Ctrl+Shift+I)
            if (e.key === 'F12' || ((e.ctrlKey || e.metaKey) && e.shiftKey && (e.key === 'I' || e.key === 'J'))) {
              e.preventDefault();
              SecureShare.postMessage('devtools_shortcut');
              return false;
            }
          });
          
          // Inject protection into iframe
          const iframe = document.querySelector('iframe');
          if (iframe) {
            iframe.addEventListener('load', function() {
              try {
                const iframeDoc = iframe.contentDocument || iframe.contentWindow.document;
                iframeDoc.addEventListener('contextmenu', e => e.preventDefault());
                iframeDoc.addEventListener('selectstart', e => e.preventDefault());
                
                // Remove print button if exists
                const printBtn = iframeDoc.querySelector('[id*="print"], [class*="print"]');
                if (printBtn) printBtn.style.display = 'none';
                
                // Remove download button if exists
                const downloadBtn = iframeDoc.querySelector('[id*="download"], [class*="download"]');
                if (downloadBtn) downloadBtn.style.display = 'none';
              } catch (e) {
                // Cross-origin restriction
              }
            });
          }
        </script>
      </body>
      </html>
    ''';
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
  }

  void _injectProtectionScripts() {
    _controller.runJavaScript('''
      // Add heartbeat monitoring
      let lastHeartbeat = Date.now();
      setInterval(() => {
        const now = Date.now();
        if (now - lastHeartbeat > 10000) { // 10 seconds
          SecureShare.postMessage('heartbeat_missing');
        }
      }, 5000);
      
      // Simulate user activity
      document.addEventListener('mousemove', () => lastHeartbeat = Date.now());
      document.addEventListener('touchstart', () => lastHeartbeat = Date.now());
      document.addEventListener('keydown', () => lastHeartbeat = Date.now());
      
      // Start heartbeat
      setInterval(() => {
        SecureShare.postMessage('heartbeat');
      }, 3000);
    ''');
  }

  void _handleJavaScriptMessage(String message) {
    print('JS Message: $message');
    
    switch (message) {
      case 'heartbeat':
        _resetInactivityTimer();
        break;
      case 'heartbeat_missing':
        _reportSuspiciousActivity('heartbeat_missing', 'No user activity detected');
        break;
      case 'context_menu_blocked':
      case 'copy_attempt':
      case 'cut_attempt':
      case 'paste_attempt':
      case 'print_attempt':
      case 'save_attempt':
      case 'devtools_detected':
      case 'devtools_shortcut':
      case 'image_context_menu':
      case 'long_press_detected':
        _failedCaptureAttempts++;
        _reportSuspiciousActivity('capture_attempt', message);
        
        if (_failedCaptureAttempts >= 3) {
          _forceCloseContent('Multiple capture attempts detected');
        }
        break;
      case 'image_load_error':
        _showError('Failed to load image');
        break;
    }
  }

  void _startMonitoring() {
    // Monitor connectivity
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
      if (result == ConnectivityResult.none) {
        setState(() => _hasInternet = false);
        _showNoInternetWarning();
      } else {
        setState(() => _hasInternet = true);
      }
    });

    // Monitor app lifecycle
    _lifecycleSubscription = WidgetsBinding.instance.lifecycleState.listen((state) {
      if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
        _isAppInBackground = true;
        _reportSuspiciousActivity('app_backgrounded', 'App moved to background');
        
        // If it's a one-time view, close immediately
        if (widget.isOneTimeView) {
          _forceCloseContent('App backgrounded during one-time view');
        }
      } else if (state == AppLifecycleState.resumed) {
        _isAppInBackground = false;
        // Check if content should still be accessible
        _verifyContentAccess();
      }
    });
  }

  void _startExpiryTimer() {
    if (widget.expiryTime != null) {
      int remainingSeconds = widget.expiryTime!;
      
      _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (remainingSeconds <= 0) {
          timer.cancel();
          _forceCloseContent('Content expired');
        } else {
          remainingSeconds--;
          // Update webview timer
          _controller.runJavaScript('''
            if (typeof updateExpiryTimer === 'function') {
              updateExpiryTimer($remainingSeconds);
            }
          ''');
        }
      });
    }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _lastInteraction = DateTime.now();
    
    // Close after 5 minutes of inactivity
    _inactivityTimer = Timer(const Duration(minutes: 5), () {
      _forceCloseContent('Inactivity timeout');
    });
  }

  void _showNoInternetWarning() {
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
        content: const Text(
          'Secure content requires internet connection.\n\n'
          'Content will close in 10 seconds if connection is not restored.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _forceCloseContent('Internet connection lost');
            },
            child: const Text('Close Now'),
          ),
        ],
      ),
    );
    
    // Auto-close after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (!_hasInternet && mounted) {
        _forceCloseContent('Internet connection lost (timeout)');
      }
    });
  }

  void _forceCloseContent(String reason) {
    _reportSuspiciousActivity('forced_close', reason);
    widget.onContentClosed();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _reportSuspiciousActivity(String type, String details) {
    widget.onSuspiciousActivity('$type: $details');
    ApiService.reportSuspiciousActivity(widget.contentId, type, SessionManager.getDeviceFingerprint());
  }

  void _verifyContentAccess() async {
    // Check if content is still accessible
    try {
      // Implement API call to verify content status
      // If not accessible, close immediately
    } catch (e) {
      _forceCloseContent('Content access verification failed');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _isAppInBackground = true;
      // Take additional protection measures
      if (Platform.isAndroid) {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      }
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _inactivityTimer?.cancel();
    _connectivitySubscription?.cancel();
    _lifecycleSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    
    // Restore normal UI mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _forceCloseContent('User attempted to go back');
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            
            // No internet overlay
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
                        'Internet Connection Required',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Secure content cannot be viewed offline.\n\n'
                        'Please restore internet connection to continue.',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        onPressed: widget.onContentClosed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                        ),
                        child: const Text('Close Content'),
                      ),
                    ],
                  ),
                ),
              ),
            
            // Exit button
            Positioned(
              top: Platform.isIOS ? 50 : 30,
              left: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => _forceCloseContent('User closed content'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}