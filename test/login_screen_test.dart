import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:secure_share/main.dart';
import 'package:secure_share/theme/theme_provider.dart';

void main() {
  testWidgets('Login screen shows correct elements', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (context) => ThemeProvider(),
        child: const MyApp(),
      ),
    );

    // Verify app title
    expect(find.text('SecureShare'), findsOneWidget);
    
    // Verify tagline
    expect(find.text('Zero-Knowledge Secure Sharing'), findsOneWidget);
    
    // Verify PIN input field
    expect(find.byType(TextField), findsOneWidget);
    
    // Verify login button
    expect(find.text('Access Secure Content'), findsOneWidget);
  });
}