import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _dobCtrl = TextEditingController();

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
    final otpCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    // States: 'idle', 'sending', 'otp', 'verifying', 'new_password', 'updating', 'success', 'error'
    String dialogState = 'idle';
    String errorMessage = '';
    String userEmail = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          String titleText() {
            switch (dialogState) {
              case 'otp':
                return 'Enter Code';
              case 'new_password':
              case 'updating':
                return 'New Password';
              case 'success':
                return 'Password Updated!';
              default:
                return 'Reset Password';
            }
          }

          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            actionsAlignment: MainAxisAlignment.center,
            title: Text(
              titleText(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── IDLE: Enter email ──
                if (dialogState == 'idle') ...[
                  const Text(
                    "Enter your email address and we'll send you a code to reset your password.",
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
                ]
                // ── SENDING: Loading spinner ──
                else if (dialogState == 'sending' ||
                    dialogState == 'verifying' ||
                    dialogState == 'updating') ...[
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(color: AppColors.volt),
                  const SizedBox(height: 20),
                  Text(
                    dialogState == 'sending'
                        ? "Sending code..."
                        : dialogState == 'verifying'
                        ? "Verifying code..."
                        : "Updating password...",
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                ]
                // ── OTP: Enter 6-digit code ──
                else if (dialogState == 'otp') ...[
                  Text(
                    "We sent a code to\n$userEmail",
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      letterSpacing: 6,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLength: 8,
                    decoration: InputDecoration(
                      hintText: "00000000",
                      hintStyle: TextStyle(
                        color: Colors.grey.withOpacity(0.3),
                        fontSize: 22,
                        letterSpacing: 6,
                      ),
                      counterText: "",
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
                  if (errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMessage,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ]
                // ── NEW PASSWORD: Enter new password ──
                else if (dialogState == 'new_password') ...[
                  const Text(
                    "Enter your new password.",
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newPasswordCtrl,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "New Password",
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordCtrl,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Confirm Password",
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
                  if (errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMessage,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ]
                // ── SUCCESS ──
                else if (dialogState == 'success') ...[
                  const SizedBox(height: 10),
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.volt,
                    size: 50,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Your password has been updated successfully!",
                    style: TextStyle(color: Colors.white, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "You can now log in with your new password.",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ]
                // ── ERROR ──
                else if (dialogState == 'error') ...[
                  const SizedBox(height: 10),
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 50,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    errorMessage.isNotEmpty
                        ? errorMessage
                        : "Something went wrong.\nPlease try again.",
                    style: const TextStyle(color: Colors.orange, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
            actions: [
              // ── IDLE actions ──
              if (dialogState == 'idle') ...[
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final email = resetEmailCtrl.text.trim();
                    if (email.isEmpty) return;
                    FocusScope.of(context).unfocus();
                    userEmail = email;
                    setDialogState(() {
                      dialogState = 'sending';
                      errorMessage = '';
                    });
                    try {
                      await Supabase.instance.client.auth.resetPasswordForEmail(
                        email,
                      );
                      setDialogState(() => dialogState = 'otp');
                    } catch (e) {
                      debugPrint('❌ Reset email error: $e');
                      setDialogState(() {
                        dialogState = 'error';
                        errorMessage = 'Failed to send code. Please try again.';
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.volt,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Send Code",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ]
              // ── OTP actions ──
              else if (dialogState == 'otp') ...[
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final code = otpCtrl.text.trim();
                    if (code.length < 6) {
                      setDialogState(
                        () => errorMessage =
                            'Please enter the code from your email.',
                      );
                      return;
                    }
                    FocusScope.of(context).unfocus();
                    setDialogState(() {
                      dialogState = 'verifying';
                      errorMessage = '';
                    });
                    try {
                      await Supabase.instance.client.auth.verifyOTP(
                        email: userEmail,
                        token: code,
                        type: OtpType.recovery,
                      );
                      setDialogState(() => dialogState = 'new_password');
                    } catch (e) {
                      debugPrint('❌ OTP verify error: $e');
                      setDialogState(() {
                        dialogState = 'otp';
                        errorMessage =
                            'Invalid or expired code. Please try again.';
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.volt,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Verify Code",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ]
              // ── NEW PASSWORD actions ──
              else if (dialogState == 'new_password') ...[
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newPwd = newPasswordCtrl.text;
                    final confirmPwd = confirmPasswordCtrl.text;
                    if (newPwd.length < 6) {
                      setDialogState(
                        () => errorMessage =
                            'Password must be at least 6 characters.',
                      );
                      return;
                    }
                    if (newPwd != confirmPwd) {
                      setDialogState(
                        () => errorMessage = 'Passwords do not match.',
                      );
                      return;
                    }
                    FocusScope.of(context).unfocus();
                    setDialogState(() {
                      dialogState = 'updating';
                      errorMessage = '';
                    });
                    try {
                      await Supabase.instance.client.auth.updateUser(
                        UserAttributes(password: newPwd),
                      );
                      setDialogState(() => dialogState = 'success');
                    } catch (e) {
                      debugPrint('❌ Password update error: $e');
                      setDialogState(() {
                        dialogState = 'new_password';
                        errorMessage =
                            'Failed to update password. Please try again.';
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.volt,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Update Password",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ]
              // ── SUCCESS / ERROR actions ──
              else if (dialogState == 'success' || dialogState == 'error') ...[
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.volt,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "OK",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              // No buttons during loading states
            ],
          );
        },
      ),
    );
  }

  /// Parse DD/MM/YYYY string and validate
  DateTime? _parseDob(String text) {
    if (text.isEmpty) return null;
    final parts = text.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (year < 1900 || year > DateTime.now().year) return null;
    try {
      final date = DateTime(year, month, day);
      // Verify the date is valid (e.g. not Feb 30)
      if (date.day != day || date.month != month || date.year != year)
        return null;
      if (date.isAfter(DateTime.now())) return null;
      return date;
    } catch (_) {
      return null;
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

                    // --- GENDER FIELD (FOR EVERYONE) — Apple style ---
                    DropdownButtonFormField<String>(
                      value: _selectedGender,
                      dropdownColor: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(16),
                      menuMaxHeight: 200,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Gender",
                        filled: true,
                        fillColor: AppColors.surface,
                        labelStyle: const TextStyle(color: Colors.grey),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.volt),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      icon: const Icon(Icons.chevron_right, color: Colors.grey),
                      selectedItemBuilder: (context) => const [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Male",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Female",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                      items: const [
                        DropdownMenuItem(
                          value: "Male",
                          child: Text(
                            "Male",
                            style: TextStyle(color: Colors.black87),
                          ),
                        ),
                        DropdownMenuItem(
                          value: "Female",
                          child: Text(
                            "Female",
                            style: TextStyle(color: Colors.black87),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _selectedGender = v;
                        _authError = null;
                      }),
                      validator: (v) => v == null ? "Required" : null,
                    ),

                    // --- DATE OF BIRTH (USER ONLY) — DD/MM/YYYY text input ---
                    if (!_isCoach) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _dobCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d/]')),
                          LengthLimitingTextInputFormatter(10),
                          _DateInputFormatter(),
                        ],
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: "Date of Birth",
                          hintText: "DD/MM/YYYY",
                          filled: true,
                          fillColor: AppColors.surface,
                          labelStyle: const TextStyle(color: Colors.grey),
                          hintStyle: TextStyle(
                            color: Colors.grey.withOpacity(0.5),
                          ),
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
                        validator: (v) {
                          if (v == null || v.trim().isEmpty)
                            return 'Date of Birth is required';
                          final parsed = _parseDob(v.trim());
                          if (parsed == null)
                            return 'Enter a valid date (DD/MM/YYYY)';
                          _dob = parsed;
                          return null;
                        },
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
      validator: (v) {
        if (v == null || v.isEmpty) return "$label is required";
        if (isEmail) {
          final emailRegex = RegExp(r'^[\w\.\-\+]+@[\w\.\-]+\.\w{2,}$');
          if (!emailRegex.hasMatch(v.trim())) {
            return "Please enter a valid email address";
          }
        }
        return null;
      },
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

/// Auto-formats date input as DD/MM/YYYY by inserting slashes
class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll('/', '');
    final buffer = StringBuffer();

    for (int i = 0; i < text.length && i < 8; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(text[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
