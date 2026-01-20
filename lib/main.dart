import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:secure_share/theme/app_theme.dart';
import 'package:secure_share/theme/theme_provider.dart';
import 'package:secure_share/features/dashboard/screens/home_screen.dart';
import 'package:secure_share/features/share/screens/share_screen.dart';
import 'package:secure_share/features/receive/screens/receive_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Secure Share',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
      routes: {
        '/home': (context) => const HomeScreen(),
        '/share': (context) => const ShareScreen(),
        '/receive': (context) => const ReceiveScreen(),
      },
    );
  }
}