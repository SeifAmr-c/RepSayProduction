import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import 'landing_page.dart';

/// Screen shown after social sign-up (Apple/Google) to collect
/// role, gender, and DOB before the user can use the app.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _client = Supabase.instance.client;
  bool _isLoading = false;
  bool _isCoach = false;
  String? _selectedGender;
  DateTime? _dob;
  String? _error;
  bool _submitted = false;
  final _fullNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Pre-fill name from Apple/Google if available
    final user = _client.auth.currentUser;
    final metaName =
        user?.userMetadata?['full_name'] as String? ??
        user?.userMetadata?['name'] as String? ??
        '';
    if (metaName.isNotEmpty) {
      _fullNameCtrl.text = metaName;
    }
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
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
      if (date.day != day || date.month != month || date.year != year)
        return null;
      if (date.isAfter(DateTime.now())) return null;
      return date;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _submitted = true);

    if (!_formKey.currentState!.validate()) return;

    if (_selectedGender == null) {
      setState(() => _error = 'Please select your Gender');
      return;
    }

    if (!_isCoach && _dob == null) {
      setState(() => _error = 'Please select your Date of Birth');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      // Determine auth method from provider
      final provider = user.appMetadata['provider'] as String? ?? 'email';
      String authMethod = 'email';
      if (provider == 'apple') {
        authMethod = 'apple';
      } else if (provider == 'google') {
        authMethod = 'google';
      }

      await _client.from('profiles').upsert({
        'id': user.id,
        'email': user.email ?? '',
        'full_name': _fullNameCtrl.text.trim(),
        'role': _isCoach ? 'coach' : 'user',
        'gender': _selectedGender,
        'dob': (!_isCoach && _dob != null) ? _dob!.toIso8601String() : null,
        'plan': 'free',
        'recordings_this_month': 0,
        'recording_month': DateTime.now().month,
        'auth_method': authMethod,
      });

      // Also update user metadata so landing page can read role
      await _client.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': _fullNameCtrl.text.trim(),
            'role': _isCoach ? 'coach' : 'user',
            'gender': _selectedGender,
            if (!_isCoach && _dob != null) 'dob': _dob!.toIso8601String(),
          },
        ),
      );

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LandingPage()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
      debugPrint('❌ Profile save error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                    "Complete Your Profile",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.volt,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Just a few more details to get started",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 32),

                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                  ],

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

                  // Full Name
                  TextFormField(
                    controller: _fullNameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Full Name",
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
                    validator: (v) =>
                        v!.isEmpty ? "Full Name is required" : null,
                  ),
                  const SizedBox(height: 12),

                  // Gender — Apple style (white bg, black text)
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
                      _error = null;
                    }),
                    validator: (v) => v == null ? "Required" : null,
                  ),

                  // DOB (Athletes only) — DD/MM/YYYY text input
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
                        if (v == null || v.trim().isEmpty) {
                          return 'Date of Birth is required';
                        }
                        final parsed = _parseDob(v.trim());
                        if (parsed == null) {
                          return 'Enter a valid date (DD/MM/YYYY)';
                        }
                        _dob = parsed;
                        return null;
                      },
                    ),
                  ],

                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
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
                        : const Text(
                            "GET STARTED",
                            style: TextStyle(fontWeight: FontWeight.bold),
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
