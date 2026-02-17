import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import 'pro_screen.dart';

class ExerciseAnalysisScreen extends StatefulWidget {
  final String userPlan;
  const ExerciseAnalysisScreen({super.key, required this.userPlan});

  @override
  State<ExerciseAnalysisScreen> createState() => _ExerciseAnalysisScreenState();
}

class _ExerciseAnalysisScreenState extends State<ExerciseAnalysisScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _loading = true;
  List<MapEntry<String, int>> _exerciseFrequency = [];
  String _currentMonthName = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonthName = _monthName(now.month);
    if (widget.userPlan == 'pro') {
      _fetchExerciseFrequency();
    } else {
      _loading = false;
    }
  }

  Future<void> _fetchExerciseFrequency() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 1);

      // Fetch all workouts for this month with their sets
      final res = await _supabase
          .from('workouts')
          .select('workout_sets(exercise_name)')
          .eq('user_id', user.id)
          .gte('date', start.toIso8601String())
          .lt('date', end.toIso8601String());

      // Count exercise frequency
      final Map<String, int> frequencyMap = {};
      for (final workout in res) {
        final sets = workout['workout_sets'] as List? ?? [];
        for (final set in sets) {
          final exerciseName = (set['exercise_name'] as String?)?.trim() ?? '';
          if (exerciseName.isNotEmpty) {
            // Normalize: capitalize first letter of each word
            final normalized = exerciseName
                .split(' ')
                .map(
                  (w) => w.isNotEmpty
                      ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
                      : '',
                )
                .join(' ');
            frequencyMap[normalized] = (frequencyMap[normalized] ?? 0) + 1;
          }
        }
      }

      // Sort by frequency (descending)
      final sorted = frequencyMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (mounted) {
        setState(() {
          _exerciseFrequency = sorted;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Exercise analysis error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        title: const Text(
          "Exercise Analysis",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: widget.userPlan != 'pro'
          ? _buildProGate()
          : _loading
          ? _buildLoading()
          : _buildContent(),
    );
  }

  // ── PRO GATE: Blurred view with upgrade prompt ──
  Widget _buildProGate() {
    return Stack(
      children: [
        // Blurred placeholder content
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPlaceholderHeader(),
                  const SizedBox(height: 24),
                  _buildPlaceholderItem("Bench Press", 12),
                  _buildPlaceholderItem("Squats", 10),
                  _buildPlaceholderItem("Deadlift", 8),
                  _buildPlaceholderItem("Pull Ups", 6),
                  _buildPlaceholderItem("Shoulder Press", 4),
                ],
              ),
            ),
          ),
        ),

        // Overlay with upgrade prompt
        Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.volt.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.volt.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_outline,
                    color: AppColors.volt,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Pro Feature",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Subscribe to Pro to unlock exercise analysis and track your most frequent exercises.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.volt,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      "Upgrade to Pro",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── LOADING ──
  Widget _buildLoading() {
    return Center(child: CircularProgressIndicator(color: AppColors.volt));
  }

  // ── MAIN CONTENT ──
  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.volt.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.fitness_center, color: AppColors.volt, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      "Most Frequent Exercises",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _currentMonthName,
                  style: TextStyle(
                    color: AppColors.volt,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (_exerciseFrequency.isEmpty)
            _buildEmptyState()
          else
            ..._exerciseFrequency.asMap().entries.map(
              (entry) => _buildExerciseCard(
                rank: entry.key + 1,
                name: entry.value.key,
                count: entry.value.value,
                isTop: entry.key == 0,
              ),
            ),
        ],
      ),
    );
  }

  // ── EMPTY STATE ──
  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              Icons.fitness_center,
              color: Colors.grey.withOpacity(0.3),
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              "No exercises this month",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Start recording workouts to see your exercise frequency here.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── EXERCISE CARD ──
  Widget _buildExerciseCard({
    required int rank,
    required String name,
    required int count,
    bool isTop = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: isTop
            ? Border.all(color: AppColors.volt.withOpacity(0.4), width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isTop ? AppColors.volt : AppColors.volt.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                "$rank",
                style: TextStyle(
                  color: isTop ? Colors.black : AppColors.volt,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Exercise name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "You have played $name $count ${count == 1 ? 'time' : 'times'} this month",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),

          // Count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.volt.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "${count}x",
              style: TextStyle(
                color: AppColors.volt,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PLACEHOLDER ITEMS (for blurred pro gate) ──
  Widget _buildPlaceholderHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 200,
            height: 20,
            color: Colors.grey.withOpacity(0.3),
          ),
          const SizedBox(height: 8),
          Container(
            width: 100,
            height: 14,
            color: Colors.grey.withOpacity(0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderItem(String name, int count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 16,
                  color: Colors.grey.withOpacity(0.3),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 180,
                  height: 12,
                  color: Colors.grey.withOpacity(0.2),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              width: 24,
              height: 14,
              color: Colors.grey.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }
}
