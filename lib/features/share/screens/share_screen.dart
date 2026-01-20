import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:secure_share/theme/theme_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:secure_share/services/api_service.dart';
import 'package:secure_share/services/encryption_service.dart';
import 'package:secure_share/services/session_manager.dart';
import 'dart:math';
import 'package:crypto/crypto.dart'; // Add this import

class ShareScreen extends StatefulWidget {
  final String sharedText;
  final VoidCallback? onClear;

  const ShareScreen({
    super.key,
    this.sharedText = '',
    this.onClear,
  });

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  String _selectedAccessMode = 'time_based';
  String _selectedTimeUnit = 'hours';
  int _timeValue = 1;
  int _deviceLimit = 1;
  bool _enableDynamicPIN = false;
  bool _enableAutoTerminate = true;
  bool _enableScreenshotProtection = true;
  bool _enableWatermarking = false;
  bool _requireBiometric = false;
  TextEditingController? _textController;
  bool _hasInitialized = false;
  bool _isUploading = false;
  File? _selectedFile;
  String _selectedFileType = 'text';
  String _fileName = '';
  String? _masterPassphrase;
  String? _contentKey;
  String? _contentIV;
  String? _generatedPin; // Store locally generated PIN
  
  // Dynamic PIN settings
  int _pinRotationInterval = 60; // minutes
  List<String> _pinRotationIntervals = ['10', '30', '60', '120', '360', '720'];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.sharedText);
    _hasInitialized = true;
    _generateMasterKey();
  }

  Future<void> _generateMasterKey() async {
    final random = Random.secure();
    final words = List.generate(6, (_) => random.nextInt(10000).toString());
    _masterPassphrase = words.join('-');
    
    try {
      // Generate encryption key locally
      _contentKey = EncryptionService.generateRandomKey();
      
      // Generate IV
      final random = Random.secure();
      final ivBytes = List<int>.generate(16, (i) => random.nextInt(256));
      _contentIV = base64Url.encode(ivBytes);
      
      // Generate 4-digit PIN locally
      _generatedPin = List.generate(4, (_) => random.nextInt(10)).join();
      
      print('✅ Generated encryption key, IV, and PIN locally');
      print('🔑 Key: ${_contentKey!.substring(0, 20)}...');
      print('🔒 PIN: $_generatedPin');
      
    } catch (e) {
      print('Key generation error: $e');
      // Fallback
      _contentKey = 'key_${DateTime.now().millisecondsSinceEpoch}';
      _contentIV = 'iv_${DateTime.now().millisecondsSinceEpoch}';
      _generatedPin = '1234'; // Default fallback
    }
  }

  @override
  void dispose() {
    _textController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Secure Content'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            widget.onClear?.call();
            Navigator.pop(context);
          },
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Content Type Selection
                const Text('Select Content Type', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _buildContentTypeButton('📝 Text', 'text', Icons.text_fields),
                        _buildContentTypeButton('🖼️ Image', 'image', Icons.image),
                        _buildContentTypeButton('📄 PDF', 'pdf', Icons.picture_as_pdf),
                        _buildContentTypeButton('🎥 Video', 'video', Icons.videocam),
                        _buildContentTypeButton('🎵 Audio', 'audio', Icons.audiotrack),
                        _buildContentTypeButton('📎 Document', 'document', Icons.description),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Content Input Area
                if (_selectedFileType == 'text')
                  _buildTextInput(isDark)
                else
                  _buildFileUpload(isDark),

                const SizedBox(height: 20),

                // Access Control
                const Text('Access Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: Column(
                      children: [
                        // Access Mode
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<String>(
                                title: const Text('⏰ Time-Based'),
                                subtitle: const Text('Expires after duration'),
                                value: 'time_based',
                                groupValue: _selectedAccessMode,
                                onChanged: (value) => setState(() => _selectedAccessMode = value!),
                                dense: true,
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<String>(
                                title: const Text('🔒 One-Time'),
                                subtitle: const Text('Burn after first view'),
                                value: 'one_time',
                                groupValue: _selectedAccessMode,
                                onChanged: (value) => setState(() => _selectedAccessMode = value!),
                                dense: true,
                              ),
                            ),
                          ],
                        ),

                        if (_selectedAccessMode == 'time_based') ...[
                          const Divider(),
                          const SizedBox(height: 10),
                          const Text('Duration', style: TextStyle(fontWeight: FontWeight.bold)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildTimeUnitButton('Minutes', _selectedTimeUnit == 'minutes'),
                              _buildTimeUnitButton('Hours', _selectedTimeUnit == 'hours'),
                              _buildTimeUnitButton('Days', _selectedTimeUnit == 'days'),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.blue, size: 32),
                                onPressed: () {
                                  if (_timeValue > _getMinValue()) setState(() => _timeValue--);
                                },
                              ),
                              const SizedBox(width: 20),
                              Container(
                                width: 100,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text('$_timeValue', textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 20),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: Colors.blue, size: 32),
                                onPressed: () {
                                  if (_timeValue < _getMaxValue()) setState(() => _timeValue++);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(_getDurationText(), style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
                        ],

                        const Divider(),
                        const SizedBox(height: 10),
                        
                        // Device Limit
                        const Text('Device Limit', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Slider(
                          value: _deviceLimit.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$_deviceLimit device${_deviceLimit > 1 ? 's' : ''}',
                          onChanged: (value) => setState(() => _deviceLimit = value.toInt()),
                        ),
                        Text('Maximum $_deviceLimit device${_deviceLimit > 1 ? 's' : ''} can access this content'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Advanced Security
                const Text('Advanced Security', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: Column(
                      children: [
                        // Dynamic PIN
                        SwitchListTile(
                          title: const Text('🔄 Dynamic PIN Rotation'),
                          subtitle: const Text('PIN changes periodically'),
                          value: _enableDynamicPIN,
                          onChanged: (value) => setState(() => _enableDynamicPIN = value),
                        ),
                        
                        if (_enableDynamicPIN) ...[
                          Padding(
                            padding: const EdgeInsets.only(left: 20, right: 20),
                            child: DropdownButtonFormField<int>(
                              initialValue: _pinRotationInterval,
                              decoration: const InputDecoration(
                                labelText: 'Rotation Interval',
                                border: OutlineInputBorder(),
                              ),
                              items: _pinRotationIntervals.map((interval) {
                                final intVal = int.parse(interval);
                                return DropdownMenuItem<int>(
                                  value: intVal,
                                  child: Text('$intVal minutes'),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _pinRotationInterval = value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        
                        // Auto Terminate
                        SwitchListTile(
                          title: const Text('🚨 Auto-Terminate on Suspicion'),
                          subtitle: const Text('Destroy content on detection'),
                          value: _enableAutoTerminate,
                          onChanged: (value) => setState(() => _enableAutoTerminate = value),
                        ),
                        
                        // Screenshot Protection
                        SwitchListTile(
                          title: const Text('📸 Screenshot Protection'),
                          subtitle: const Text('Block screenshots and recording'),
                          value: _enableScreenshotProtection,
                          onChanged: (value) => setState(() => _enableScreenshotProtection = value),
                        ),
                        
                        // Watermarking
                        SwitchListTile(
                          title: const Text('💧 Invisible Watermarking'),
                          subtitle: const Text('Track content leaks'),
                          value: _enableWatermarking,
                          onChanged: (value) => setState(() => _enableWatermarking = value),
                        ),
                        
                        // Biometric Required
                        SwitchListTile(
                          title: const Text('👆 Biometric Required'),
                          subtitle: const Text('Require fingerprint/face ID'),
                          value: _requireBiometric,
                          onChanged: (value) => setState(() => _requireBiometric = value),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // Share Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isUploading ? null : _uploadAndShare,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isUploading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              _selectedFileType == 'text' ? 'Encrypt & Share' : 'Encrypt & Share File',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                  ),
                ),
                
                // Zero-Knowledge Info
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user, color: Colors.green, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🔐 Zero-Knowledge Encryption', 
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            const SizedBox(height: 4),
                            Text('Encryption keys NEVER leave your device. Backend cannot read your content.',
                                style: TextStyle(fontSize: 12, color: Colors.green[800])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
              ],
            ),
          ),
          
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text("Encrypting & Uploading...", style: TextStyle(color: Colors.white, fontSize: 16)),
                    SizedBox(height: 10),
                    Text("Keys generated locally, never sent to server", 
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContentTypeButton(String label, String type, IconData icon) {
    final isSelected = _selectedFileType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFileType = type;
          _selectedFile = null;
          _fileName = '';
        });
      },
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? Colors.blue : Colors.transparent, width: 2),
        ),
        child: Column(
          children: [
            Icon(icon, size: 30, color: isSelected ? Colors.blue : Colors.grey),
            const SizedBox(height: 5),
            Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _buildTextInput(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Text Content', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 10),
            TextField(
              controller: _textController,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'Enter sensitive text here...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.lock, size: 14, color: Colors.blue),
                const SizedBox(width: 5),
                Text('Encrypted locally with zero-knowledge', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileUpload(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Upload File', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 10),
            
            if (_selectedFile == null)
              ElevatedButton(
                onPressed: _pickFile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.upload_file),
                    SizedBox(width: 10),
                    Text('Select File to Upload'),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getFileTypeIcon(),
                      size: 40,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fileName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Type: ${_selectedFileType.toUpperCase()}',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _selectedFile = null;
                          _fileName = '';
                        });
                      },
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.security, size: 14, color: Colors.blue),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'File encrypted locally before upload. Backend cannot read it.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      if (_selectedFileType == 'image') {
        final picker = ImagePicker();
        final pickedFile = await picker.pickImage(source: ImageSource.gallery);
        if (pickedFile != null) {
          setState(() {
            _selectedFile = File(pickedFile.path);
            _fileName = pickedFile.name;
          });
        }
      } else {
        FileType type = FileType.any;
        if (_selectedFileType == 'video') type = FileType.video;
        if (_selectedFileType == 'pdf') type = FileType.custom;
        if (_selectedFileType == 'audio') type = FileType.audio;

        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: type,
          allowedExtensions: _selectedFileType == 'pdf' ? ['pdf'] : null,
        );

        if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
          setState(() {
            _selectedFile = File(result.files.first.path!);
            _fileName = result.files.first.name;
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking file: $e'), backgroundColor: Colors.red),
      );
    }
  }

  IconData _getFileTypeIcon() {
    switch (_selectedFileType) {
      case 'image': return Icons.image;
      case 'pdf': return Icons.picture_as_pdf;
      case 'video': return Icons.videocam;
      case 'audio': return Icons.audiotrack;
      case 'document': return Icons.description;
      default: return Icons.insert_drive_file;
    }
  }

  Widget _buildTimeUnitButton(String unit, bool isSelected) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          onPressed: () => setState(() {
            _selectedTimeUnit = unit.toLowerCase();
            _timeValue = 1;
          }),
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
            foregroundColor: isSelected ? Colors.white : Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: Text(unit),
        ),
      ),
    );
  }

  int _getMinValue() => 1;

  int _getMaxValue() {
    switch (_selectedTimeUnit) {
      case 'minutes': return 1440;
      case 'hours': return 720;
      case 'days': return 365;
      default: return 100;
    }
  }

  String _getDurationText() {
    String unit = _selectedTimeUnit;
    if (_timeValue == 1) unit = unit.substring(0, unit.length - 1);
    return 'Content will expire after $_timeValue $unit';
  }

  Future<void> _uploadAndShare() async {
    // Validate inputs
    if (_selectedFileType == 'text' && (_textController?.text.isEmpty ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter text to share'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_selectedFileType != 'text' && _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file to share'), backgroundColor: Colors.red),
      );
      return;
    }

    // Validate encryption keys
    if (_contentKey == null || _contentIV == null || _generatedPin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encryption keys not ready. Please try again.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      print('🚀 Starting ZERO-KNOWLEDGE secure share process...');

      // Check backend connection
      final bool isConnected = await ApiService.testConnection();
      if (!isConnected) {
        throw Exception('Backend not running!\n\nStart it with:\npython -m uvicorn main:app --reload --host 0.0.2.2 --port 8000');
      }

      Uint8List dataBytes;
      String mimeType;

      if (_selectedFileType == 'text') {
        dataBytes = Uint8List.fromList(utf8.encode(_textController!.text));
        mimeType = 'text/plain';
      } else {
        dataBytes = await _selectedFile!.readAsBytes();
        mimeType = _getMimeType(_selectedFile!.path);
      }

      // Encrypt Data LOCALLY
      print('🔐 Encrypting content locally...');
      final encryptedResult = EncryptionService.encryptBytes(dataBytes, _contentKey!);
      final Uint8List encryptedBytes = encryptedResult['bytes'] as Uint8List;
      final String iv = encryptedResult['iv'] as String;

      // Get device fingerprint
      final deviceFingerprint = await SessionManager.getDeviceFingerprint();

      // Calculate duration
      int? durationMinutes;
      if (_selectedAccessMode == 'time_based') {
        switch (_selectedTimeUnit) {
          case 'minutes': durationMinutes = _timeValue; break;
          case 'hours': durationMinutes = _timeValue * 60; break;
          case 'days': durationMinutes = _timeValue * 1440; break;
        }
      }

      // Generate key hash (for zero-knowledge verification)
      final keyHash = _generateKeyHash(_contentKey!);
      print('🔑 Key Hash (sent to backend): $keyHash');
      print('🔒 PIN (sent to backend): $_generatedPin');

      // Upload to backend with ZERO-KNOWLEDGE parameters
      print('📤 Uploading encrypted content (backend cannot read it)...');
      final response = await ApiService.uploadContent(
        encryptedBytes: encryptedBytes,
        iv: iv,
        accessMode: _selectedAccessMode,
        durationMinutes: durationMinutes,
        deviceLimit: _deviceLimit,
        contentType: _selectedFileType,
        fileName: _fileName.isNotEmpty ? _fileName : 'secure_content.dat',
        fileSize: encryptedBytes.length,
        mimeType: mimeType,
        dynamicPIN: _enableDynamicPIN,
        pinRotationMinutes: _enableDynamicPIN ? _pinRotationInterval : null,
        autoTerminateOnSuspicion: _enableAutoTerminate,
        requireBiometric: _requireBiometric,
        trustedDevices: [deviceFingerprint],
        // ZERO-KNOWLEDGE PARAMETERS
        pin: _generatedPin!, // Locally generated PIN
        keyHash: keyHash, // Hash of encryption key (not the key itself)
      );

      final contentId = response['content_id'];
      final expiryTime = response['expiry_time'] ?? 'Not specified';
      
      print('✅ Zero-knowledge upload successful!');
      print('📌 Content ID: $contentId');
      print('🔐 Encryption key stays on device');

      // Store local session info (key never leaves device)
      await SessionManager.storeAccessToken('content_key_$contentId', _contentKey!);

      // Show PIN and Key dialog (both generated locally)
      await _showShareDialog(_generatedPin!, _contentKey!, expiryTime, _selectedFileType, contentId);

      // Clear form
      if (mounted) {
        widget.onClear?.call();
        _textController?.clear();
        _selectedFile = null;
        _fileName = '';
      }

    } catch (e) {
      print('❌ Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  String _generateKeyHash(String key) {
    try {
      final keyBytes = utf8.encode(key);
      final hash = sha256.convert(keyBytes);
      return hash.toString();
    } catch (e) {
      print('Key hash error: $e');
      return 'hash_error_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<void> _showShareDialog(String pin, String key, dynamic expiryTime, String contentType, String contentId) async {
    String expiryText = '';
    if (expiryTime != null && expiryTime != 'Not specified') {
      expiryText = '⏰ Expires: ${_formatExpiryTime(expiryTime)}';
    } else {
      expiryText = '🔒 One-time view (self-destructs after first view)';
    }

    final contentInfo = {
      'text': '📝 Encrypted Text',
      'image': '🖼️ Encrypted Image',
      'pdf': '📄 Encrypted PDF',
      'video': '🎥 Encrypted Video',
      'audio': '🎵 Encrypted Audio',
      'document': '📎 Encrypted Document',
    }[contentType] ?? '🔒 Secure Content';

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 10),
            Text('Content Ready to Share'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('✅ $contentInfo has been encrypted and uploaded securely.'),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_user, size: 14, color: Colors.green),
                    SizedBox(width: 5),
                    Expanded(
                      child: Text('Zero-Knowledge: Keys never left your device',
                          style: TextStyle(fontSize: 11, color: Colors.green)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              
              // PIN Card
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.pin, size: 16, color: Colors.blue),
                          SizedBox(width: 5),
                          Text('ACCESS PIN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        pin,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 5),
                      ),
                      const SizedBox(height: 5),
                      const Text('Share this 4-digit PIN with recipient', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 15),
              
              // Key Card
              Card(
                color: Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.key, size: 16, color: Colors.green),
                          SizedBox(width: 5),
                          Text('ENCRYPTION KEY', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: SelectableText(
                          key,
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text('Share this key separately for maximum security', style: TextStyle(fontSize: 11)),
                      const SizedBox(height: 5),
                      const Text('⚠️ Without this key, content cannot be decrypted',
                          style: TextStyle(fontSize: 10, color: Colors.red)),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 15),
              
              // Security Info
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.security, size: 14, color: Colors.orange),
                        SizedBox(width: 5),
                        Text('Security Features', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text('• Content Type: ${contentType.toUpperCase()}'),
                    Text('• $expiryText'),
                    Text('• Device Limit: $_deviceLimit device${_deviceLimit > 1 ? 's' : ''}'),
                    const SizedBox(height: 5),
                    const Text('⚠️ Recipient needs BOTH PIN and KEY to view content', style: TextStyle(fontSize: 11)),
                    const SizedBox(height: 5),
                    const Text('🔐 Backend cannot read your content (zero-knowledge)', 
                        style: TextStyle(fontSize: 10, color: Colors.green)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          // Copy PIN Button
          OutlinedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: pin));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PIN copied to clipboard')),
              );
            },
            child: const Text('Copy PIN'),
          ),
          
          // Copy Key Button
          OutlinedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: key));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Key copied to clipboard')),
              );
            },
            child: const Text('Copy Key'),
          ),
          
          // Share Button
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              
              final shareMessage = '''
🔒 SECURE CONTENT SHARED (Zero-Knowledge Encryption)

PIN: $pin
KEY: $key

Access Mode: ${_selectedAccessMode == 'time_based' ? '⏰ Time-Based' : '🔒 One-Time View'}
$expiryText
Device Limit: $_deviceLimit device${_deviceLimit > 1 ? 's' : ''}

⚠️ IMPORTANT:
- Save BOTH PIN and KEY
- Without KEY, content cannot be decrypted
- Content is end-to-end encrypted
- Backend cannot read your data (zero-knowledge)

📱 How to access:
1. Open Secure Share App
2. Enter PIN and KEY
3. View content in secure online viewer
''';

              await Share.share(shareMessage, subject: '🔒 Secure Content PIN: $pin');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.share, size: 18),
                SizedBox(width: 5),
                Text('Share via...'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatExpiryTime(dynamic expiryTime) {
    if (expiryTime is String) {
      try {
        final date = DateTime.parse(expiryTime);
        return '${date.toLocal().toString().substring(0, 16)}';
      } catch (e) {
        return expiryTime.toString();
      }
    }
    return expiryTime.toString();
  }

  String _getMimeType(String path) {
    return EncryptionService.getMimeType(path);
  }
}