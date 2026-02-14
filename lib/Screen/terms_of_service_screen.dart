import 'package:flutter/material.dart';
import '../main.dart'; // Import to access AppColors
import 'auth_screen.dart';

class TermsOfServiceScreen extends StatefulWidget {
  const TermsOfServiceScreen({super.key});

  @override
  State<TermsOfServiceScreen> createState() => _TermsOfServiceScreenState();
}

class _TermsOfServiceScreenState extends State<TermsOfServiceScreen> {
  bool _accepted = false;
  String? _error;

  void _continue() {
    if (!_accepted) {
      setState(() {
        _error =
            'You must accept the Terms of Service in order to use the app.';
      });
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          "Terms of Service",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Introduction
                    const Text(
                      "Welcome to RepSay",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Please read and accept our Terms of Service before using the app.",
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    const SizedBox(height: 24),

                    // Terms Content
                    _buildSection(
                      "1. Acceptance of Terms",
                      "By using RepSay, you agree to comply with these Terms of Service. If you do not agree, you may not use the app.",
                    ),
                    _buildSection(
                      "2. AI Voice Recording",
                      "RepSay uses AI to process your voice recordings and log workouts. The AI is designed to understand workout-related speech only.",
                    ),

                    // AI Misuse Warning - Highlighted
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent, width: 1),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.redAccent,
                              ),
                              SizedBox(width: 8),
                              Text(
                                "Important: AI Usage Policy",
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Text(
                            "• Misuse of the AI voice feature is strictly prohibited.\n"
                            "• This includes making random noises, speaking gibberish, or intentionally providing invalid input.\n"
                            "• After 3 failed attempts, you will receive a warning.\n"
                            "• After 4 failed attempts, your account will be permanently blocked and all data will be deleted.\n"
                            "• Blocked accounts cannot be recovered, and the associated email cannot be used to register again.",
                            style: TextStyle(color: Colors.grey, height: 1.6),
                          ),
                        ],
                      ),
                    ),

                    _buildSection(
                      "3. Account Termination",
                      "We reserve the right to terminate accounts that violate these terms, including but not limited to AI misuse, fraudulent activity, or any behavior that disrupts the service.",
                    ),
                    _buildSection(
                      "4. Data Privacy",
                      "Your workout data is stored securely. We do not share your personal information with third parties. Voice recordings are processed and not stored permanently.",
                    ),
                    _buildSection(
                      "5. Disclaimer",
                      "RepSay is a fitness tracking tool, not medical advice. Consult a professional before starting any fitness program.",
                    ),
                    _buildSection(
                      "6. Changes to Terms",
                      "We may update these terms from time to time. Continued use of the app after changes constitutes acceptance.",
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Bottom Section: Checkbox + Button
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Checkbox
                  GestureDetector(
                    onTap: () => setState(() {
                      _accepted = !_accepted;
                      _error = null;
                    }),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _accepted
                                ? AppColors.volt
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _accepted ? AppColors.volt : Colors.grey,
                              width: 2,
                            ),
                          ),
                          child: _accepted
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.black,
                                  size: 18,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            "I have read and accept the Terms of Service",
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Error Message
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Continue Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _continue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.volt,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        "CONTINUE",
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(color: Colors.grey, height: 1.5),
          ),
        ],
      ),
    );
  }
}
