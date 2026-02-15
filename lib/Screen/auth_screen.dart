import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
import '../main.dart'; // Import to access AppColors
import 'landing_page.dart'; // To handle User vs Coach redirection
import 'complete_profile_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _client = Supabase.instance.client;
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isCoach = false; // Toggle for User/Coach role
  String? _authError;
  bool _submitted = false;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();

  DateTime? _dob; // User Only
  String? _selectedGender; // Everyone (User & Coach)

  final _formKey = GlobalKey<FormState>();

  Future<void> _handleAuth() async {
    setState(() => _submitted = true);

    // 1. Validate Basic Form (Email, Pass, Name)
    if (!_formKey.currentState!.validate()) return;

    // 2. Validate Custom Fields
    if (!_isLogin) {
      // Rule 1: EVERYONE must select a Gender
      if (_selectedGender == null) {
        setState(() => _authError = 'Please select your Gender');
        return;
      }

      // Rule 2: ONLY Users (Athletes) must select Date of Birth
      if (!_isCoach && _dob == null) {
        setState(() => _authError = 'Please select your Date of Birth');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _authError = null;
    });

    try {
      // Check if email is blocked
      final email = _emailCtrl.text.trim().toLowerCase();
      final blocked = await _client
          .from('blocked_emails')
          .select('email')
          .eq('email', email)
          .maybeSingle();

      if (blocked != null) {
        setState(() {
          _isLoading = false;
          _authError =
              'This account has been blocked due to violation of our terms of service.';
        });
        return;
      }

      if (_isLogin) {
        await _client.auth.signInWithPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );
      } else {
        // Sign up the user
        final response = await _client.auth.signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
          data: {
            'full_name': _fullNameCtrl.text.trim(),
            'role': _isCoach ? 'coach' : 'user',
            'gender': _selectedGender,
            if (!_isCoach && _dob != null) 'dob': _dob!.toIso8601String(),
          },
        );

        // Directly create/update profile to ensure data is saved (backup for trigger)
        // This is non-blocking - if it fails, landing page will read from user metadata
        if (response.user != null) {
          try {
            await _client.from('profiles').upsert({
              'id': response.user!.id,
              'email': _emailCtrl.text.trim(),
              'full_name': _fullNameCtrl.text.trim(),
              'role': _isCoach ? 'coach' : 'user',
              'gender': _selectedGender,
              'dob': (!_isCoach && _dob != null)
                  ? _dob!.toIso8601String()
                  : null,
              'plan': 'free',
              'recordings_this_month': 0,
              'recording_month': DateTime.now().month,
              'auth_method': 'email',
            });
          } catch (profileError) {
            // Non-critical - landing page will use metadata fallback
            debugPrint('⚠️ Profile upsert failed: $profileError');
          }
        }
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LandingPage()),
          (route) => false,
        );
      }
    } on AuthException catch (e) {
      // Provide user-friendly error messages
      String errorMessage;
      if (e.message.contains('Invalid login credentials')) {
        errorMessage =
            'Invalid email or password. Please check your credentials and try again.';
      } else if (e.message.contains('Email not confirmed')) {
        errorMessage = 'Please verify your email before logging in.';
      } else if (e.message.contains('User already registered')) {
        errorMessage =
            'An account with this email already exists. Please login instead.';
      } else {
        errorMessage = e.message;
      }
      setState(() => _authError = errorMessage);
    } catch (e) {
      setState(
        () => _authError = 'An unexpected error occurred. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Generates a random nonce string for Apple Sign-In security.
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  /// Returns sha256 hash of the input string.
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _isLoading = true;
      _authError = null;
    });

    try {
      // Generate nonce for security
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256ofString(rawNonce);

      // Request Apple Sign-In (native iOS dialog)
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        setState(() => _authError = 'Apple Sign-In failed. Please try again.');
        return;
      }

      // Sign in to Supabase with the Apple ID token
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      if (response.user == null) {
        setState(() => _authError = 'Apple Sign-In failed. Please try again.');
        return;
      }

      // Check if profile exists AND has required fields filled
      final profile = await _client
          .from('profiles')
          .select('id, gender, role')
          .eq('id', response.user!.id)
          .maybeSingle();

      if (mounted) {
        if (profile == null || profile['gender'] == null) {
          // New user or incomplete profile — go to complete profile screen
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const CompleteProfileScreen()),
            (route) => false,
          );
        } else {
          // Existing user with complete profile — go to main app
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LandingPage()),
            (route) => false,
          );
        }
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        // User cancelled — do nothing
      } else {
        setState(() => _authError = 'Apple Sign-In failed. Please try again.');
      }
    } on AuthException catch (e) {
      debugPrint('❌ Apple auth error: ${e.message}');
      setState(() => _authError = 'Apple Sign-In failed. Please try again.');
    } catch (e) {
      debugPrint('❌ Apple sign-in error: $e');
      setState(() => _authError = 'Apple Sign-In failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog() {
    final resetEmailCtrl = TextEditingController();
    bool isResetting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "Reset Password",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Enter your email address and we'll send you a link to reset your password.",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: resetEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Email",
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.volt),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: isResetting
                  ? null
                  : () async {
                      final email = resetEmailCtrl.text.trim();
                      if (email.isEmpty) return;

                      setDialogState(() => isResetting = true);

                      try {
                        await Supabase.instance.client.auth
                            .resetPasswordForEmail(email);

                        if (ctx.mounted) Navigator.pop(ctx);

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                "Password reset link sent! Check your email.",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: AppColors.surface,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              margin: const EdgeInsets.all(16),
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isResetting = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                "Failed to send reset email. Please try again.",
                                style: TextStyle(color: Colors.white),
                              ),
                              backgroundColor: AppColors.surface,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              margin: const EdgeInsets.all(16),
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.volt,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isResetting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      "Send Reset Link",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18),
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.volt,
            onPrimary: Colors.black,
            surface: AppColors.surface,
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: AppColors.surface,
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _authError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              autovalidateMode: _submitted
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "REPSAY",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: AppColors.volt,
                    ),
                  ),
                  const SizedBox(height: 40),

                  if (_authError != null) ...[
                    Text(
                      _authError!,
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (!_isLogin) ...[
                    // Role Toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _roleButton("Athlete", false),
                        const SizedBox(width: 16),
                        _roleButton("Coach", true),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildField("Full Name", _fullNameCtrl),
                    const SizedBox(height: 12),
                  ],

                  _buildField("Email", _emailCtrl, isEmail: true),
                  const SizedBox(height: 12),
                  _buildPasswordField(),

                  // Forgot Password link (only on login)
                  if (_isLogin) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _showForgotPasswordDialog,
                        child: const Text(
                          "Forgot Password?",
                          style: TextStyle(color: AppColors.volt, fontSize: 13),
                        ),
                      ),
                    ),
                  ],

                  if (!_isLogin) ...[
                    const SizedBox(height: 12),

                    // --- GENDER FIELD (FOR EVERYONE) ---
                    DropdownButtonFormField<String>(
                      value: _selectedGender,
                      dropdownColor: AppColors.surface,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Gender",
                        filled: true,
                        fillColor: AppColors.surface,
                        labelStyle: const TextStyle(color: Colors.grey),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.volt),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: "Male", child: Text("Male")),
                        DropdownMenuItem(
                          value: "Female",
                          child: Text("Female"),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _selectedGender = v;
                        _authError = null;
                      }),
                      validator: (v) => v == null ? "Required" : null,
                    ),

                    // --- DATE OF BIRTH (USER ONLY) ---
                    if (!_isCoach) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _pickDob,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _dob == null
                                ? "Date of Birth"
                                : "${_dob!.day}/${_dob!.month}/${_dob!.year}",
                            style: TextStyle(
                              color: _dob == null ? Colors.grey : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleAuth,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.volt,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _isLogin ? "LOGIN" : "CREATE ACCOUNT",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),

                  const SizedBox(height: 30),

                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade800)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          "OR",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade800)),
                    ],
                  ),
                  const SizedBox(height: 30),

                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _signInWithApple,
                    icon: const Icon(Icons.apple, color: Colors.white),
                    label: const Text(
                      "Continue with Apple",
                      style: TextStyle(color: Colors.white),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.white),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() {
                      _isLogin = !_isLogin;
                      _authError = null;
                      _formKey.currentState?.reset();
                    }),
                    child: Text(
                      _isLogin
                          ? "Create an account"
                          : "I already have an account",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    bool isEmail = false,
  }) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: const TextStyle(color: Colors.grey),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.volt),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      validator: (v) => v!.isEmpty ? "$label is required" : null,
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordCtrl,
      obscureText: _obscurePassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: "Password",
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: const TextStyle(color: Colors.grey),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.volt),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (v) => v!.length < 6 ? "Password too short" : null,
    );
  }

  Widget _roleButton(String text, bool targetState) {
    final isSelected = _isCoach == targetState;
    return GestureDetector(
      onTap: () => setState(() => _isCoach = targetState),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.volt : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.volt),
        ),
        child: Row(
          children: [
            Icon(
              targetState ? Icons.sports : Icons.person,
              color: isSelected ? Colors.black : Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
