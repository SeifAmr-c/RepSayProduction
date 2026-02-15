import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'Coach/coach_layout.dart';
import 'main_layout.dart';
import 'onboarding_screen.dart';
import 'complete_profile_screen.dart';

class _Colors {
  static const Color volt = Color(0xFFDbf756);
  static const Color background = Color(0xFF121212);
}

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    await Future.delayed(Duration.zero);

    final session = Supabase.instance.client.auth.currentSession;

    // 1. If no session, go to Onboarding
    if (session == null) {
      _go(const OnboardingScreen());
      return;
    }

    // 2. Check ROLE
    try {
      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) {
        _go(const OnboardingScreen());
        return;
      }

      // Try to get role and check profile completeness
      final data = await Supabase.instance.client
          .from('profiles')
          .select('role, gender')
          .eq('id', user.id)
          .maybeSingle();

      // If no profile exists OR profile is incomplete (missing gender), redirect to profile completion
      if (data == null || data['gender'] == null) {
        if (mounted) _go(const CompleteProfileScreen());
        return;
      }

      // Fallback to user metadata if role is null
      String role = data['role'] as String? ?? '';
      if (role.isEmpty) {
        // Read from user metadata (set during signup)
        role = user.userMetadata?['role'] as String? ?? 'user';
        debugPrint('📱 Role from metadata: $role');
      } else {
        debugPrint('📱 Role from profile: $role');
      }

      if (mounted) {
        if (role == 'coach') {
          debugPrint('🏋️ Navigating to Coach Layout');
          _go(const CoachLayout());
        } else {
          debugPrint('👤 Navigating to User Layout');
          _go(const MainLayout());
        }
      }
    } catch (e) {
      debugPrint('❌ Redirect error: $e');
      // Default to User Dashboard on error
      if (mounted) _go(const MainLayout());
    }
  }

  void _go(Widget screen) {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _Colors.background,
      body: Center(child: CircularProgressIndicator(color: _Colors.volt)),
    );
  }
}
