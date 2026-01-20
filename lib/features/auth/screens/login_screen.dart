import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:secure_share/theme/theme_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;

  void _login() {
    if (_pinController.text.length != 4) return;
    
    setState(() => _isLoading = true);
    
    Future.delayed(const Duration(seconds: 1), () {
      setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: themeProvider.isDarkMode 
                    ? const Color(0xFF10B981) 
                    : const Color(0xFF059669),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline,
                size: 50,
                color: Colors.white,
              ),
            ),
            
            const SizedBox(height: 32),
            
            Text(
              'SecureShare',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: themeProvider.isDarkMode 
                    ? Colors.white 
                    : Colors.black,
              ),
            ),
            
            const SizedBox(height: 8),
            
            Text(
              'Zero-Knowledge Secure Sharing',
              style: TextStyle(
                fontSize: 16,
                color: themeProvider.isDarkMode 
                    ? Colors.grey[400] 
                    : Colors.grey[600],
              ),
            ),
            
            const SizedBox(height: 48),
            
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: 10,
              ),
              decoration: InputDecoration(
                hintText: '1234',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                counterText: '',
                contentPadding: const EdgeInsets.all(20),
              ),
              onChanged: (value) {
                if (value.length == 4) {
                  _login();
                }
              },
            ),
            
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _login,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Access Secure Content',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.light_mode,
                  color: themeProvider.isDarkMode 
                      ? Colors.grey 
                      : Colors.amber,
                ),
                const SizedBox(width: 12),
                Switch(
                  value: themeProvider.isDarkMode,
                  onChanged: (value) {
                    themeProvider.toggleTheme();
                  },
                  activeThumbColor: const Color(0xFF6366F1),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.dark_mode,
                  color: themeProvider.isDarkMode 
                      ? Colors.indigo 
                      : Colors.grey,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}