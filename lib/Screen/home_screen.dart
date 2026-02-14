import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart'; // Imports AppColors
import 'manual_workout_screen.dart';
import 'pro_screen.dart';
import 'auth_screen.dart';
import '../helpers/review_helper.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Recorder
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;
  int _secondsLeft = 30;
  DateTime? _recordingStartTime;

  // Timers
  Timer? _countdownTimer;
  Timer? _amplitudeTimer;
  final List<double> _bars = List<double>.filled(10, 0.1);

  // Data
  bool _loading = true;
  String _firstName = "";
  List<Map<String, dynamic>> _workouts = [];

  // Plan Logic
  String _userPlan = 'free';
  int _monthlyCount = 0;
  final int _freeLimit = 2; // Free tier limit
  int _failedAttempts = 0; // Track failed voice recording attempts

  // Realtime
  RealtimeChannel? _profileChannel;

  static const List<String> _months = [
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
  late int _selectedMonthIndex;

  @override
  void initState() {
    super.initState();
    _selectedMonthIndex = DateTime.now().month - 1;
    _loadAllData();
    _setupProGiftListener();
    ReviewHelper.checkAndRequestReview();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _amplitudeTimer?.cancel();
    _recorder.dispose();
    if (_profileChannel != null) _supabase.removeChannel(_profileChannel!);
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    await _fetchUserProfile();
    await _fetchWorkouts();
  }

  Future<void> _fetchUserProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      debugPrint('❌ No user logged in');
      return;
    }
    debugPrint('📱 Fetching profile for user: ${user.id}');
    try {
      final profile = await _supabase
          .from('profiles')
          .select(
            'full_name, plan, recordings_this_month, recording_month, failed_voice_attempts, pro_expires_at, pro_gift_message',
          )
          .eq('id', user.id)
          .maybeSingle();

      debugPrint('📊 Profile result: $profile');

      if (profile != null) {
        final fullName = profile['full_name'] as String? ?? 'User';
        debugPrint('👤 Full name from DB: "$fullName"');
        final currentMonth = DateTime.now().month;
        int recordingsUsed = profile['recordings_this_month'] ?? 0;
        int savedMonth = profile['recording_month'] ?? currentMonth;

        // Reset counter if month changed
        if (savedMonth != currentMonth) {
          recordingsUsed = 0;
          await _supabase
              .from('profiles')
              .update({
                'recordings_this_month': 0,
                'recording_month': currentMonth,
              })
              .eq('id', user.id);
        }

        setState(() {
          _firstName = fullName.split(' ')[0];
          _userPlan = profile['plan'] ?? 'free';
          _monthlyCount = recordingsUsed;
          _failedAttempts = profile['failed_voice_attempts'] ?? 0;
        });

        // Check pro expiry
        await _checkProExpiry(profile, user.id);

        // Check for pending gift message
        final giftMsg = profile['pro_gift_message'] as String?;
        if (giftMsg != null && giftMsg.isNotEmpty) {
          _showProGiftDialog(giftMsg);
          // Clear the message so it doesn't show again
          await _supabase
              .from('profiles')
              .update({'pro_gift_message': null})
              .eq('id', user.id);
        }

        debugPrint(
          '✅ _firstName set to: "$_firstName", failed attempts: $_failedAttempts',
        );
      } else {
        debugPrint('⚠️ Profile returned null - using metadata fallback');
        // Fallback to user metadata
        final metaName = user.userMetadata?['full_name'] as String? ?? 'User';
        setState(() {
          _firstName = metaName.split(' ')[0];
        });
        debugPrint('✅ _firstName set from metadata: "$_firstName"');
      }
    } catch (e) {
      debugPrint("❌ Profile Error: $e");
    }
  }

  void _setupProGiftListener() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _profileChannel = _supabase
        .channel('profile-gift-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: user.id,
          ),
          callback: (payload) {
            final newData = payload.newRecord;
            final giftMsg = newData['pro_gift_message'] as String?;
            if (giftMsg != null && giftMsg.isNotEmpty && mounted) {
              // Update plan state
              setState(() {
                _userPlan = newData['plan'] ?? _userPlan;
              });
              _showProGiftDialog(giftMsg);
              // Clear the message
              _supabase
                  .from('profiles')
                  .update({'pro_gift_message': null})
                  .eq('id', user.id)
                  .then((_) {});
            }
          },
        )
        .subscribe();
  }

  Future<void> _checkProExpiry(
    Map<String, dynamic> profile,
    String userId,
  ) async {
    final proExpiresAt = profile['pro_expires_at'] as String?;
    if (proExpiresAt != null && profile['plan'] == 'pro') {
      final expiryDate = DateTime.parse(proExpiresAt);
      if (DateTime.now().isAfter(expiryDate)) {
        // Pro has expired - revert to free
        await _supabase
            .from('profiles')
            .update({'plan': 'free', 'pro_expires_at': null})
            .eq('id', userId);
        setState(() => _userPlan = 'free');
        debugPrint('⏰ Pro plan expired, reverted to free');
      }
    }
  }

  void _showProGiftDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.card_giftcard, color: AppColors.volt, size: 28),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                "Congratulations! 🎉",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.grey, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.volt,
              foregroundColor: Colors.black,
            ),
            child: const Text("Awesome!"),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchWorkouts() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final start = DateTime(DateTime.now().year, _selectedMonthIndex + 1, 1);
      final end = DateTime(DateTime.now().year, _selectedMonthIndex + 2, 1);

      final res = await _supabase
          .from('workouts')
          .select('*, workout_sets(*)')
          .eq('user_id', user.id)
          .gte('date', start.toIso8601String())
          .lt('date', end.toIso8601String())
          .order('date', ascending: false)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _workouts = List<Map<String, dynamic>>.from(res);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteWorkout(dynamic id, int index) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          color: AppColors.surface,
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.volt),
                SizedBox(height: 16),
                Text("Deleting...", style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // 1. Delete workout_sets first (foreign key constraint)
      await _supabase.from('workout_sets').delete().eq('workout_id', id);

      // 2. Delete the workout
      await _supabase.from('workouts').delete().eq('id', id);

      // 3. Close loading dialog and update UI
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {
          _workouts.removeAt(index);
        });
      }
    } catch (e) {
      debugPrint('Delete error: $e');
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to delete: $e")));
      }
    }
  }

  void _showEditWorkoutDialog(Map<String, dynamic> workout, int index) {
    final nameCtrl = TextEditingController(text: workout['name'] ?? '');

    // Create editable copies of workout_sets
    final sets = List<Map<String, dynamic>>.from(
      (workout['workout_sets'] as List).map(
        (s) => Map<String, dynamic>.from(s),
      ),
    );

    // Create controllers for each exercise
    final exerciseControllers = sets
        .map(
          (s) => {
            'name': TextEditingController(text: s['exercise_name'] ?? ''),
            'sets': TextEditingController(text: (s['sets'] ?? 0).toString()),
            'reps': TextEditingController(text: (s['reps'] ?? 0).toString()),
            'weight': TextEditingController(
              text: (s['weight'] ?? 0).toString(),
            ),
          },
        )
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            "Edit Workout",
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Workout Name
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Workout Name",
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "EXERCISES",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Exercise List
                  ...List.generate(sets.length, (i) {
                    final ctrl = exerciseControllers[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Exercise Name
                          TextField(
                            controller: ctrl['name'],
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: "Exercise ${i + 1}",
                              labelStyle: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                              filled: true,
                              fillColor: AppColors.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Sets, Reps, Weight Row
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: ctrl['sets'],
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: "Sets",
                                    labelStyle: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10,
                                    ),
                                    filled: true,
                                    fillColor: AppColors.surface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: ctrl['reps'],
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: "Reps",
                                    labelStyle: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10,
                                    ),
                                    filled: true,
                                    fillColor: AppColors.surface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: ctrl['weight'],
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: "KG",
                                    labelStyle: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10,
                                    ),
                                    filled: true,
                                    fillColor: AppColors.surface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.white),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);

                // Prepare updated sets data
                final updatedSets = List.generate(
                  sets.length,
                  (i) => {
                    'id': sets[i]['id'],
                    'exercise_name': exerciseControllers[i]['name']!.text,
                    'sets':
                        int.tryParse(exerciseControllers[i]['sets']!.text) ?? 0,
                    'reps':
                        int.tryParse(exerciseControllers[i]['reps']!.text) ?? 0,
                    'weight':
                        double.tryParse(
                          exerciseControllers[i]['weight']!.text,
                        ) ??
                        0,
                  },
                );

                await _updateWorkoutWithExercises(
                  workout['id'],
                  nameCtrl.text,
                  updatedSets,
                  index,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.volt,
                foregroundColor: Colors.black,
              ),
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateWorkoutWithExercises(
    dynamic id,
    String newName,
    List<Map<String, dynamic>> updatedSets,
    int index,
  ) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          color: AppColors.surface,
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.volt),
                SizedBox(height: 16),
                Text(
                  "Saving changes...",
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // 1. Update workout name
      await _supabase.from('workouts').update({'name': newName}).eq('id', id);

      // 2. Update each exercise in workout_sets
      for (final set in updatedSets) {
        await _supabase
            .from('workout_sets')
            .update({
              'exercise_name': set['exercise_name'],
              'sets': set['sets'],
              'reps': set['reps'],
              'weight': set['weight'],
            })
            .eq('id', set['id']);
      }

      // 3. Refresh workouts from database
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop(); // Close loading dialog
        await _fetchWorkouts();
      }
    } catch (e) {
      debugPrint('Update error: $e');
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop(); // Close loading dialog
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to update: $e")));
      }
    }
  }

  Future<void> _startRecording() async {
    if (_userPlan == 'free' && _monthlyCount >= _freeLimit) {
      _showLimitDialog();
      return;
    }

    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/loggy_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordingPath = path;
      _secondsLeft = 30;
      _recordingStartTime = DateTime.now();
    });

    _startCountdown();
    _startAmplitudeListener();
  }

  void _showLimitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          "Limit Reached",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "You have used your 3 free voice logs for this month. Upgrade to Pro for unlimited recording.",
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.volt,
              foregroundColor: Colors.black,
            ),
            child: const Text("Go Pro"),
          ),
        ],
      ),
    );
  }

  Future<void> _stopRecording() async {
    final int durationSec = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!).inSeconds
        : 0;

    _countdownTimer?.cancel();
    _amplitudeTimer?.cancel();
    setState(() => _bars.fillRange(0, _bars.length, 0.1));

    final path = await _recorder.stop();
    setState(() => _isRecording = false);

    final finalPath = path ?? _recordingPath;
    if (finalPath == null) return;

    // Show processing dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          color: AppColors.surface,
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.volt),
                SizedBox(height: 16),
                Text("Processing...", style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not logged in.');

      final storagePath =
          '${user.id}/${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _supabase.storage
          .from('workouts-audio')
          .upload(storagePath, File(finalPath));

      // Call edge function and check response
      final response = await _supabase.functions.invoke(
        'process-workout',
        body: {'storage_path': storagePath, 'duration': durationSec},
      );

      // Close processing dialog
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      // Check for errors in response
      final data = response.data;
      if (data != null && data['error'] != null) {
        // Show error dialog - DO NOT increment recording count on error
        if (mounted) {
          await _handleFailedAttempt();
        }
        return;
      }

      // SUCCESS: Only increment recordings counter on successful processing
      // Direct update instead of RPC (more reliable)
      await _supabase
          .from('profiles')
          .update({
            'recordings_this_month': _monthlyCount + 1,
            'recording_month': DateTime.now().month,
          })
          .eq('id', _supabase.auth.currentUser!.id);

      // Refresh data including the updated counter
      await _loadAllData();
    } catch (e) {
      // Close processing dialog if still open
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (mounted) {
        await _handleFailedAttempt();
      }
    }
  }

  Future<void> _handleFailedAttempt() async {
    _failedAttempts++;

    // Sync to database
    final user = _supabase.auth.currentUser;
    if (user != null) {
      await _supabase
          .from('profiles')
          .update({'failed_voice_attempts': _failedAttempts})
          .eq('id', user.id);
    }

    // Check if should block account (4 or more failures)
    if (_failedAttempts >= 4) {
      await _blockAccount();
    } else {
      _showVoiceErrorDialog();
    }
  }

  Future<void> _blockAccount() async {
    // Show blocking dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          color: AppColors.surface,
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.redAccent),
                SizedBox(height: 16),
                Text(
                  "Blocking account...",
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Call edge function to block account
      await _supabase.functions.invoke('block-account');

      // Close loading dialog
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      // Show blocked message
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, color: Colors.redAccent, size: 28),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    "Account Blocked",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            content: const Text(
              "Your account has been blocked due to breach of our privacy policy and misuse of the AI voice feature.\n\nAll your data has been permanently deleted.",
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                    (r) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      debugPrint('❌ Block account error: $e');
    }
  }

  void _showVoiceErrorDialog() {
    final bool showWarning = _failedAttempts >= 3;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              showWarning ? Icons.error_outline : Icons.warning_amber_rounded,
              color: showWarning ? Colors.redAccent : Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              showWarning ? "Warning" : "Recording Issue",
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Text(
          showWarning
              ? "You have made multiple unsuccessful recording attempts. Continued misuse of the AI voice feature may result in your account being suspended."
              : "The AI could not understand what you said. Please speak clearly about your workout exercises.",
          style: const TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.volt,
              foregroundColor: Colors.black,
            ),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1)
        _stopRecording();
      else
        setState(() => _secondsLeft--);
    });
  }

  void _startAmplitudeListener() {
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      final amp = await _recorder.getAmplitude();
      double normalized = (amp.current + 50) / 50;
      if (normalized < 0) normalized = 0;
      if (normalized > 1) normalized = 1;
      if (mounted)
        setState(() {
          for (int i = 0; i < _bars.length - 1; i++) _bars[i] = _bars[i + 1];
          _bars.last = normalized;
        });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // LEFT: Month Dropdown
            _monthDropdown(),

            // RIGHT: Add Manual Workout Button
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.add, color: AppColors.volt),
                onPressed: () async {
                  // Navigate to Manual Screen
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ManualWorkoutScreen(),
                    ),
                  );
                  // If saved (returned true), refresh list
                  if (result == true) _loadAllData();
                },
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.volt),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_firstName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: Text(
                          "Hello, $_firstName",
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 5, 20, 10),
                      child: Text(
                        "Latest Workouts",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        itemCount: _workouts.length,
                        itemBuilder: (ctx, i) {
                          final workout = _workouts[i];
                          return Slidable(
                            key: Key(workout['id'].toString()),
                            endActionPane: ActionPane(
                              motion: const DrawerMotion(),
                              extentRatio: 0.4,
                              children: [
                                // Edit Action
                                SlidableAction(
                                  onPressed: (_) =>
                                      _showEditWorkoutDialog(workout, i),
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  icon: Icons.edit,
                                  label: 'Edit',
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    bottomLeft: Radius.circular(16),
                                  ),
                                ),
                                // Delete Action
                                SlidableAction(
                                  onPressed: (_) =>
                                      _deleteWorkout(workout['id'], i),
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  icon: Icons.delete,
                                  label: 'Delete',
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(16),
                                    bottomRight: Radius.circular(16),
                                  ),
                                ),
                              ],
                            ),
                            child: _WorkoutCard(data: workout),
                          );
                        },
                      ),
                    ),
                  ],
                ),

          if (_isRecording) _buildSmallRecordingOverlay(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: _MicButton(
          isRecording: _isRecording,
          onTap: _isRecording ? _stopRecording : _startRecording,
        ),
      ),
    );
  }

  Widget _buildSmallRecordingOverlay() {
    return Positioned(
      bottom: 90,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: 160,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.9),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppColors.volt, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: _bars
                    .map(
                      (h) => AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        width: 3,
                        height: 8 + (h * 20),
                        decoration: BoxDecoration(
                          color: AppColors.volt,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(width: 10),
              Text(
                "00:${_secondsLeft.toString().padLeft(2, '0')}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.surface),
        borderRadius: BorderRadius.circular(20),
        color: AppColors.surface,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedMonthIndex,
          icon: const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.keyboard_arrow_down, color: AppColors.volt),
          ),
          isDense: true,
          dropdownColor: AppColors.surface,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
          items: List.generate(
            12,
            (i) => DropdownMenuItem(value: i, child: Text(_months[i])),
          ),
          onChanged: (v) {
            setState(() => _selectedMonthIndex = v!);
            _fetchWorkouts();
          },
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onTap;
  const _MicButton({required this.isRecording, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRecording ? Colors.red : AppColors.volt,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.volt.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        isRecording ? Icons.stop : Icons.mic,
        color: Colors.black,
        size: 30,
      ),
    ),
  );
}

class _WorkoutCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _WorkoutCard({required this.data});
  @override
  Widget build(BuildContext context) {
    final sets = data['workout_sets'] as List;
    final date = DateTime.parse(data['date']);
    sets.sort(
      (a, b) => (a['order_index'] ?? 0).compareTo(b['order_index'] ?? 0),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // HEADER: Workout Name & Date
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
              color: Colors.white.withOpacity(0.02),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  data['name'] ?? 'Workout',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                Text(
                  "${date.day} ${_monthName(date.month)}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppColors.volt,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // --- TABLE HEADERS ---
                Row(
                  children: const [
                    Expanded(
                      flex: 3,
                      child: Text(
                        "EXERCISE",
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          "SETS",
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          "REPS",
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          "KG",
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Divider(color: Colors.white.withOpacity(0.1), height: 1),
                const SizedBox(height: 12),

                // --- EXERCISE ROWS ---
                ...sets
                    .map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                s['exercise_name'] ?? 'Unknown',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Center(
                                child: Text(
                                  "${s['sets']}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Center(
                                child: Text(
                                  "${s['reps']}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Center(
                                child: Text(
                                  "${s['weight']}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.volt,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ],
            ),
          ),
          if (sets.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                "No exercises logged.",
                style: TextStyle(color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  String _monthName(int m) => [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m - 1];
}
