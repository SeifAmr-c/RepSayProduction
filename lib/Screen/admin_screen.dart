import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _emailController = TextEditingController();
  late TabController _tabController;

  // Gift Pro state
  bool _isSearching = false;
  bool _isGifting = false;
  Map<String, dynamic>? _foundProfile;
  String? _errorMessage;
  String? _successMessage;
  List<Map<String, dynamic>> _giftedUsers = [];
  Timer? _errorTimer;

  // Analytics state
  bool _analyticsLoading = true;
  int _totalRecordingsToday = 0;
  int _activeUsersToday = 0;
  double _avgSessionDuration = 0;
  List<Map<String, dynamic>> _topUsers = [];
  List<Map<String, dynamic>> _popularActions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchGiftedUsers();
    _fetchAnalytics();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _errorTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ─────────── GIFT PRO LOGIC ───────────

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
        _fetchGiftedUsers();
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

  void _startErrorTimer() {
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _errorMessage = null);
    });
  }

  // ─────────── ANALYTICS LOGIC ───────────

  Future<void> _fetchAnalytics() async {
    setState(() => _analyticsLoading = true);

    try {
      final now = DateTime.now();
      final todayStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).toUtc().toIso8601String();

      // 1. Total recordings today
      final recordingsRes = await _supabase
          .from('user_analytics')
          .select('id')
          .eq('event_type', 'recording')
          .gte('created_at', todayStart);
      _totalRecordingsToday = (recordingsRes as List).length;

      // 2. Active users today (distinct user_ids with any event)
      final activeRes = await _supabase
          .from('user_analytics')
          .select('user_id')
          .gte('created_at', todayStart);
      final uniqueUsers = <String>{};
      for (final row in (activeRes as List)) {
        uniqueUsers.add(row['user_id'].toString());
      }
      _activeUsersToday = uniqueUsers.length;

      // 3. Top 5 most active users (by recording count, all time)
      final allRecordings = await _supabase
          .from('user_analytics')
          .select('user_id')
          .eq('event_type', 'recording');
      final userCounts = <String, int>{};
      for (final row in (allRecordings as List)) {
        final uid = row['user_id'].toString();
        userCounts[uid] = (userCounts[uid] ?? 0) + 1;
      }
      final sortedUsers = userCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      _topUsers = [];
      for (int i = 0; i < sortedUsers.length && i < 5; i++) {
        final userId = sortedUsers[i].key;
        final count = sortedUsers[i].value;
        // Fetch user name
        final profile = await _supabase
            .from('profiles')
            .select('full_name, email:id')
            .eq('id', userId)
            .maybeSingle();
        _topUsers.add({
          'name': profile?['full_name'] ?? 'Unknown',
          'user_id': userId,
          'count': count,
        });
      }

      // 4. Most popular actions (event_type counts)
      final allEvents = await _supabase
          .from('user_analytics')
          .select('event_type');
      final actionCounts = <String, int>{};
      for (final row in (allEvents as List)) {
        final evt = row['event_type'].toString();
        actionCounts[evt] = (actionCounts[evt] ?? 0) + 1;
      }
      final sortedActions = actionCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _popularActions = sortedActions
          .map((e) => {'action': e.key, 'count': e.value})
          .toList();

      // 5. Average session duration
      final sessions = await _supabase
          .from('user_analytics')
          .select('user_id, event_type, created_at')
          .inFilter('event_type', ['session_start', 'session_end'])
          .order('created_at', ascending: true);

      final sessionStarts = <String, DateTime>{};
      final durations = <double>[];
      for (final row in (sessions as List)) {
        final uid = row['user_id'].toString();
        final type = row['event_type'].toString();
        final time = DateTime.parse(row['created_at']);
        if (type == 'session_start') {
          sessionStarts[uid] = time;
        } else if (type == 'session_end' && sessionStarts.containsKey(uid)) {
          final dur = time.difference(sessionStarts[uid]!).inMinutes.toDouble();
          if (dur > 0 && dur < 480) {
            // Cap at 8 hours to exclude abnormal sessions
            durations.add(dur);
          }
          sessionStarts.remove(uid);
        }
      }
      _avgSessionDuration = durations.isEmpty
          ? 0
          : durations.reduce((a, b) => a + b) / durations.length;

      if (mounted) setState(() => _analyticsLoading = false);
    } catch (e) {
      debugPrint('Error fetching analytics: $e');
      if (mounted) setState(() => _analyticsLoading = false);
    }
  }

  // ─────────── BUILD ───────────

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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.volt,
          labelColor: AppColors.volt,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.card_giftcard), text: "Gift Pro"),
            Tab(icon: Icon(Icons.analytics), text: "Analytics"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildGiftProTab(), _buildAnalyticsTab()],
      ),
    );
  }

  // ─────────── GIFT PRO TAB ───────────

  Widget _buildGiftProTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    );
  }

  // ─────────── ANALYTICS TAB ───────────

  Widget _buildAnalyticsTab() {
    if (_analyticsLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.volt),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchAnalytics,
      color: AppColors.volt,
      backgroundColor: AppColors.surface,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Text(
              "User Analytics",
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Today's overview • Pull to refresh",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // Stat Cards Row
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    Icons.mic,
                    "Recordings\nToday",
                    _totalRecordingsToday.toString(),
                    AppColors.volt,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    Icons.people,
                    "Active Users\nToday",
                    _activeUsersToday.toString(),
                    Colors.blueAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    Icons.timer,
                    "Avg Session\n(min)",
                    _avgSessionDuration.toStringAsFixed(1),
                    Colors.orangeAccent,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // Top Users
            const Text(
              "Top 5 Most Active Users",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_topUsers.isEmpty)
              _buildEmptyState("No recording data yet")
            else
              ..._topUsers.asMap().entries.map((entry) {
                final i = entry.key;
                final user = entry.value;
                return Container(
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
                      // Rank badge
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: i == 0
                              ? AppColors.volt
                              : i == 1
                              ? Colors.grey.shade400
                              : i == 2
                              ? Colors.orange.shade400
                              : Colors.grey.shade700,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '#${i + 1}',
                          style: TextStyle(
                            color: i < 3 ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          user['name'] ?? 'Unknown',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.volt.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${user['count']} recs',
                          style: const TextStyle(
                            color: AppColors.volt,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 28),

            // Popular Actions
            const Text(
              "Most Popular Actions",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_popularActions.isEmpty)
              _buildEmptyState("No event data yet")
            else
              ..._popularActions.map((action) {
                final name = _formatActionName(action['action']);
                final count = action['count'] as int;
                final icon = _actionIcon(action['action']);
                return Container(
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
                      Icon(icon, color: AppColors.volt, size: 22),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        count.toString(),
                        style: const TextStyle(
                          color: AppColors.volt,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ─────────── HELPERS ───────────

  Widget _buildStatCard(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(msg, style: const TextStyle(color: Colors.grey)),
      ),
    );
  }

  String _formatActionName(String raw) {
    switch (raw) {
      case 'recording':
        return 'Voice Recording';
      case 'manual_add':
        return 'Manual Add';
      case 'edit_workout':
        return 'Edit Workout';
      case 'delete_workout':
        return 'Delete Workout';
      case 'calorie_calc':
        return 'Calorie Calculator';
      case 'exercise_analysis':
        return 'Exercise Analysis';
      case 'session_start':
        return 'App Opened';
      case 'session_end':
        return 'App Closed';
      default:
        return raw.replaceAll('_', ' ');
    }
  }

  IconData _actionIcon(String raw) {
    switch (raw) {
      case 'recording':
        return Icons.mic;
      case 'manual_add':
        return Icons.add_circle;
      case 'edit_workout':
        return Icons.edit;
      case 'delete_workout':
        return Icons.delete;
      case 'calorie_calc':
        return Icons.calculate;
      case 'exercise_analysis':
        return Icons.fitness_center;
      case 'session_start':
        return Icons.login;
      case 'session_end':
        return Icons.logout;
      default:
        return Icons.touch_app;
    }
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
