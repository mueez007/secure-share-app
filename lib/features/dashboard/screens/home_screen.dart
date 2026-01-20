import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:secure_share/theme/theme_provider.dart';
import 'package:secure_share/features/share/screens/share_screen.dart';
import 'package:secure_share/features/receive/screens/receive_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Dashboard'),
        actions: [
          IconButton(
            icon: Icon(
              themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: () {
              themeProvider.toggleTheme();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome to SecureShare',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: themeProvider.isDarkMode 
                            ? Colors.white 
                            : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Share sensitive content with military-grade encryption',
                      style: TextStyle(
                        color: themeProvider.isDarkMode 
                            ? Colors.grey[400] 
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Quick Actions
            Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: themeProvider.isDarkMode 
                    ? Colors.white 
                    : Colors.black,
              ),
            ),
            const SizedBox(height: 15),

            // Action Cards Grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              children: [
                _buildActionCard(
                  context,
                  icon: Icons.upload,
                  title: 'Share',
                  subtitle: 'Send secure content',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ShareScreen(sharedText: '')),
                    );
                  },
                ),
                _buildActionCard(
                  context,
                  icon: Icons.download,
                  title: 'Receive',
                  subtitle: 'Access shared content',
                  color: Colors.green,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ReceiveScreen()),
                    );
                  },
                ),
                _buildActionCard(
                  context,
                  icon: Icons.history,
                  title: 'History',
                  subtitle: 'View past shares',
                  color: Colors.orange,
                  onTap: () {
                    // TODO: Navigate to History
                  },
                ),
                _buildActionCard(
                  context,
                  icon: Icons.settings,
                  title: 'Settings',
                  subtitle: 'App configuration',
                  color: Colors.purple,
                  onTap: () {
                    // TODO: Navigate to Settings
                  },
                ),
              ],
            ),

            const SizedBox(height: 30),

            // Security Status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.security,
                      color: Colors.green,
                      size: 40,
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Security Status: ACTIVE',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: themeProvider.isDarkMode 
                                  ? Colors.white 
                                  : Colors.black,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Zero-knowledge encryption enabled',
                            style: TextStyle(
                              color: themeProvider.isDarkMode 
                                  ? Colors.grey[400] 
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return GestureDetector(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(15.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 30,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: themeProvider.isDarkMode 
                      ? Colors.white 
                      : Colors.black,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: themeProvider.isDarkMode 
                      ? Colors.grey[400] 
                      : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}