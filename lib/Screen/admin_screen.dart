import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _supabase = Supabase.instance.client;
  final _emailController = TextEditingController();

  bool _isSearching = false;
  bool _isGifting = false;
  Map<String, dynamic>? _foundProfile;
  String? _errorMessage;
  String? _successMessage;
  List<Map<String, dynamic>> _giftedUsers = [];
  Timer? _errorTimer;

  @override
  void initState() {
    super.initState();
    _fetchGiftedUsers();
  }

  Future<void> _fetchGiftedUsers() async {
    try {
      final response = await _supabase.functions.invoke(
        'gift-pro',
        body: {'action': 'list'},
      );

      final data = response.data;
      if (data['users'] != null && mounted) {
        setState(() {
          _giftedUsers = List<Map<String, dynamic>>.from(data['users']);
        });
      }
    } catch (e) {
      debugPrint('Error fetching gifted users: $e');
    }
  }

  Future<void> _searchUser() async {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter an email address');
      return;
    }

    setState(() {
      _isSearching = true;
      _foundProfile = null;
      _errorMessage = null;
      _successMessage = null;
      _errorTimer?.cancel();
    });

    try {
      final response = await _supabase.functions.invoke(
        'gift-pro',
        body: {'email': email, 'action': 'search'},
      );

      final data = response.data;

      if (data['found'] == true) {
        setState(() {
          _foundProfile = data['profile'];
        });
      } else {
        setState(() {
          _errorMessage =
              'Sorry, could not find this email. The user may not be registered.';
        });
        _startErrorTimer();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Search failed: ${e.toString()}';
      });
      _startErrorTimer();
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _giftPro() async {
    final email = _foundProfile?['email'];
    if (email == null) return;

    setState(() {
      _isGifting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final response = await _supabase.functions.invoke(
        'gift-pro',
        body: {'email': email, 'action': 'gift'},
      );

      final data = response.data;

      if (data['already_pro'] == true) {
        setState(() {
          _errorMessage = data['error'];
          _foundProfile = null;
        });
        _startErrorTimer();
      } else if (data['success'] == true) {
        setState(() {
          _successMessage = 'Pro plan gifted to $email successfully! 🎉';
          _foundProfile = null;
        });
        _emailController.clear();
        _fetchGiftedUsers(); // Refresh the gifted list
      } else {
        setState(() {
          _errorMessage = data['error'] ?? 'Failed to gift pro plan';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Gift failed: ${e.toString()}';
      });
      _startErrorTimer();
    } finally {
      setState(() => _isGifting = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _errorTimer?.cancel();
    super.dispose();
  }

  void _startErrorTimer() {
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _errorMessage = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          "Admin Panel",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            const Text(
              "Gift Pro Plan",
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Search for a user by email and gift them a 1-month Pro plan.",
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 24),

            const SizedBox(height: 24),

            // Search Row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: "Enter user email...",
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSearching ? null : _searchUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.volt,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSearching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text(
                            "Search",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Loading state
            if (_isSearching)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.volt),
                    SizedBox(height: 12),
                    Text("Searching...", style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),

            // Found User Card
            if (_foundProfile != null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.volt.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: AppColors.volt,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        const Flexible(
                          child: Text(
                            "Email found!",
                            style: TextStyle(
                              color: AppColors.volt,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow("Name", _foundProfile!['name'] ?? 'N/A'),
                    _buildInfoRow("Email", _foundProfile!['email'] ?? 'N/A'),
                    _buildInfoRow(
                      "Current Plan",
                      _foundProfile!['plan'] ?? 'free',
                    ),
                    if (_foundProfile!['pro_expires_at'] != null)
                      _buildInfoRow(
                        "Pro Expires",
                        _foundProfile!['pro_expires_at'].toString().substring(
                          0,
                          10,
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isGifting ? null : _giftPro,
                        icon: _isGifting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.card_giftcard),
                        label: Text(
                          _isGifting ? "Gifting..." : "Gift 1 Month Pro",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.volt,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Error Message
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              ),

            // Success Message
            if (_successMessage != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.volt.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.volt.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.celebration, color: AppColors.volt),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: const TextStyle(color: AppColors.volt),
                      ),
                    ),
                  ],
                ),
              ),

            // Gifted Users List
            if (_giftedUsers.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                "Pro plan was gifted to",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ..._giftedUsers.map(
                (user) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: AppColors.volt, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user['full_name'] ?? 'Unknown',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              user['email'] ?? '',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            user['plan'] == 'pro' ? 'Active' : 'Expired',
                            style: TextStyle(
                              color: user['plan'] == 'pro'
                                  ? AppColors.volt
                                  : Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'Exp: ${user['pro_expires_at']?.toString().substring(0, 10) ?? 'N/A'}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            "$label: ",
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
