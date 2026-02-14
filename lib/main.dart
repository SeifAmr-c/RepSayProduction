import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

// --- IMPORTS ---
import 'package:flutter_test_1/Screen/landing_page.dart'; 

// --- GLOBAL COLORS ---
class AppColors {
  static const Color volt = Color(0xFFDbf756);
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.grey;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("🚀 App Starting...");

  // 1. Initialize Supabase (Wrapped in Try/Catch)
  try {
    debugPrint("🔌 Connecting to Supabase...");
    await Supabase.initialize(
      url: 'https://uvxuygmivrbxsuxnwjnb.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV2eHV5Z21pdnJieHN1eG53am5iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkxMTQyMjEsImV4cCI6MjA4NDY5MDIyMX0.771uHYP0Vrv4VJAKp0eWuCl3xOfNYRmlLXTp2Djgyz0',
    );
    debugPrint("✅ Supabase Connected!");
  } catch (e) {
    debugPrint("❌ Supabase Failed: $e");
  }

  // 2. Initialize RevenueCat (Wrapped in Try/Catch)
  try {
    debugPrint("💰 Configuring RevenueCat...");
    await Purchases.setLogLevel(LogLevel.debug);
    PurchasesConfiguration configuration;
    configuration = PurchasesConfiguration("test_lioXNrAZuKHicXfBaMTsNbOaNjs");
    await Purchases.configure(configuration);
    debugPrint("✅ RevenueCat Ready!");
  } catch (e) {
    debugPrint("❌ RevenueCat Failed: $e");
  }

  runApp(const RepSayApp());
}

class RepSayApp extends StatelessWidget {
  const RepSayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RepSay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        brightness: Brightness.dark,
        primaryColor: AppColors.volt,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.volt,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          secondary: AppColors.volt,
        ),
        useMaterial3: true,
      ),
      home: const LandingPage(),
    );
  }
}