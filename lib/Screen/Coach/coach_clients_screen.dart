import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../main.dart'; // Ensure this points to your AppColors
// If you have the manual workout file, keep this import. If not, comment it out.
import '../manual_workout_screen.dart';
import '../pro_screen.dart';
import '../../helpers/review_helper.dart';
import '../auth_screen.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class CoachClientsScreen extends StatefulWidget {
  const CoachClientsScreen({super.key});

  @override
  State<CoachClientsScreen> createState() => _CoachClientsScreenState();
}

class _CoachClientsScreenState extends State<CoachClientsScreen> {
  final _supabase = Supabase.instance.client;
  String _coachName = "Coach";
  List<Map<String, dynamic>> _clients = [];
  bool _loading = true;
  String _plan = 'free';
  int _clientsAdded = 0; // Track clients added this month (persistent counter)
  static const int _freeClientLimit = 3;
  RealtimeChannel? _profileChannel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupProGiftListener();
    ReviewHelper.checkAndRequestReview();
  }

  Future<void> _loadData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Get Profile & Plan with client counter
      final profile = await _supabase
          .from('profiles')
          .select(
            'full_name, plan, clients_added_this_month, client_month, failed_voice_attempts, pro_expires_at, pro_gift_message',
          )
          .eq('id', user.id)
          .single();

      // Get clients counter with month reset logic
      final currentMonth = DateTime.now().month;
      int clientsUsed = profile['clients_added_this_month'] ?? 0;
      int savedMonth = profile['client_month'] ?? currentMonth;

      // Reset counter if month changed
      if (savedMonth != currentMonth) {
        clientsUsed = 0;
        await _supabase
            .from('profiles')
            .update({
              'clients_added_this_month': 0,
              'client_month': currentMonth,
            })
            .eq('id', user.id);
      }

      if (mounted) {
        final fullName = profile['full_name'] as String? ?? 'Coach';
        setState(() {
          _coachName = fullName.split(' ')[0]; // Extract first name only
          _plan = profile['plan'] ?? 'free';
          _clientsAdded = clientsUsed;
        });
      }

      // Check pro expiry
      final proExpiresAt = profile['pro_expires_at'] as String?;
      if (proExpiresAt != null && profile['plan'] == 'pro') {
        final expiryDate = DateTime.parse(proExpiresAt);
        if (DateTime.now().isAfter(expiryDate)) {
          await _supabase
              .from('profiles')
              .update({'plan': 'free', 'pro_expires_at': null})
              .eq('id', user.id);
          if (mounted) setState(() => _plan = 'free');
        }
      }

      // Check for pending gift message
      final giftMsg = profile['pro_gift_message'] as String?;
      if (giftMsg != null && giftMsg.isNotEmpty && mounted) {
        _showProGiftDialog(giftMsg);
        await _supabase
            .from('profiles')
            .update({'pro_gift_message': null})
            .eq('id', user.id);
      }

      // Get Clients
      final clients = await _supabase
          .from('clients')
          .select()
          .eq('coach_id', user.id) // Ensure we only get this coach's clients
          .order('created_at');

      if (mounted) {
        setState(() {
          _clients = List<Map<String, dynamic>>.from(clients);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Load data error: $e');
      // If profile doesn't exist (account deleted), sign out and redirect to login
      if (e.toString().contains('PGRST116') ||
          e.toString().contains('0 rows')) {
        await _supabase.auth.signOut();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthScreen()),
            (r) => false,
          );
        }
      }
    }
  }

  void _setupProGiftListener() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _profileChannel = _supabase
        .channel('coach-profile-gift-${user.id}')
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
              setState(() {
                _plan = newData['plan'] ?? _plan;
              });
              _showProGiftDialog(giftMsg);
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

  void _addClientDialog() {
    // Plan Limit Check - use counter instead of clients list length
    if (_plan == 'free' && _clientsAdded >= _freeClientLimit) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            "Client Limit Reached",
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            "Free accounts can add up to 3 clients. Upgrade to Pro for unlimited clients.",
            style: TextStyle(color: Colors.grey),
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
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProScreen(isCoach: true),
                  ),
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
      return;
    }

    final nameCtrl = TextEditingController();
    final ageCtrl = TextEditingController();
    bool nameError = false;
    bool ageError = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            "Add New Client",
            style: TextStyle(color: Colors.white),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    onChanged: (_) {
                      if (nameError) setDialogState(() => nameError = false);
                    },
                    decoration: InputDecoration(
                      labelText: "Client Name",
                      labelStyle: TextStyle(
                        color: nameError ? Colors.red : Colors.grey,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: nameError
                            ? const BorderSide(color: Colors.red, width: 2)
                            : BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: nameError ? Colors.red : AppColors.volt,
                          width: 2,
                        ),
                      ),
                      errorText: nameError ? "Name is required" : null,
                      errorStyle: const TextStyle(color: Colors.red),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ageCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    onChanged: (_) {
                      if (ageError) setDialogState(() => ageError = false);
                    },
                    decoration: InputDecoration(
                      labelText: "Age",
                      labelStyle: TextStyle(
                        color: ageError ? Colors.red : Colors.grey,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: ageError
                            ? const BorderSide(color: Colors.red, width: 2)
                            : BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: ageError ? Colors.red : AppColors.volt,
                          width: 2,
                        ),
                      ),
                      errorText: ageError ? "Age is required" : null,
                      errorStyle: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.all(16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.volt,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              onPressed: () async {
                // Validate fields
                bool hasError = false;
                if (nameCtrl.text.trim().isEmpty) {
                  setDialogState(() => nameError = true);
                  hasError = true;
                }
                if (ageCtrl.text.trim().isEmpty) {
                  setDialogState(() => ageError = true);
                  hasError = true;
                }
                if (hasError) return;

                await _supabase.from('clients').insert({
                  'coach_id': _supabase.auth.currentUser!.id,
                  'name': nameCtrl.text.trim(),
                  'age': int.tryParse(ageCtrl.text) ?? 0,
                });

                // Increment clients counter (doesn't decrement on delete)
                await _supabase.rpc('increment_clients', params: {});

                if (mounted) {
                  Navigator.pop(ctx);
                  _loadData();
                }
              },
              child: const Text(
                "Add Client",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editClientDialog(Map<String, dynamic> client, int index) {
    final nameCtrl = TextEditingController(text: client['name']);
    final ageCtrl = TextEditingController(text: client['age'].toString());
    bool nameError = false;
    bool ageError = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            "Edit Client",
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) {
                    if (nameError) setDialogState(() => nameError = false);
                  },
                  decoration: InputDecoration(
                    labelText: "Client Name",
                    labelStyle: TextStyle(
                      color: nameError ? Colors.red : Colors.grey,
                    ),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: nameError
                          ? const BorderSide(color: Colors.red, width: 2)
                          : BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: nameError ? Colors.red : AppColors.volt,
                        width: 2,
                      ),
                    ),
                    errorText: nameError ? "Name is required" : null,
                    errorStyle: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ageCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) {
                    if (ageError) setDialogState(() => ageError = false);
                  },
                  decoration: InputDecoration(
                    labelText: "Age",
                    labelStyle: TextStyle(
                      color: ageError ? Colors.red : Colors.grey,
                    ),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: ageError
                          ? const BorderSide(color: Colors.red, width: 2)
                          : BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: ageError ? Colors.red : AppColors.volt,
                        width: 2,
                      ),
                    ),
                    errorText: ageError ? "Age is required" : null,
                    errorStyle: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
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
                // Validate fields
                bool hasError = false;
                if (nameCtrl.text.trim().isEmpty) {
                  setDialogState(() => nameError = true);
                  hasError = true;
                }
                if (ageCtrl.text.trim().isEmpty) {
                  setDialogState(() => ageError = true);
                  hasError = true;
                }
                if (hasError) return;

                Navigator.pop(ctx);
                await _updateClient(
                  client['id'],
                  nameCtrl.text.trim(),
                  int.tryParse(ageCtrl.text) ?? client['age'],
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

  Future<void> _updateClient(String id, String name, int age, int index) async {
    try {
      await _supabase
          .from('clients')
          .update({'name': name, 'age': age})
          .eq('id', id);
      if (mounted) {
        setState(() {
          _clients[index]['name'] = name;
          _clients[index]['age'] = age;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to update: $e")));
      }
    }
  }

  Future<void> _deleteClient(String id, int index) async {
    try {
      // First delete all workouts for this client
      final workouts = await _supabase
          .from('workouts')
          .select('id')
          .eq('client_id', id);
      for (var w in (workouts as List)) {
        await _supabase.from('workout_sets').delete().eq('workout_id', w['id']);
      }
      await _supabase.from('workouts').delete().eq('client_id', id);
      // Then delete the client
      await _supabase.from('clients').delete().eq('id', id);
      if (mounted) {
        setState(() {
          _clients.removeAt(index);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to delete: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        toolbarHeight: 70,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Hello, $_coachName",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
            const Text(
              "Manage your athletes",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: _addClientDialog,
              icon: const Icon(Icons.add, size: 16, color: Colors.black),
              label: const Text(
                "Add Client",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.volt,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.volt),
            )
          : _clients.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 80,
                    color: Colors.grey.shade700,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "No clients yet",
                    style: TextStyle(color: Colors.grey, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Tap 'Add Client' to get started",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _clients.length,
              itemBuilder: (ctx, i) {
                final client = _clients[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Slidable(
                    key: Key(client['id']),
                    endActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      extentRatio: 0.4,
                      children: [
                        SlidableAction(
                          onPressed: (_) => _editClientDialog(client, i),
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          icon: Icons.edit,
                          label: 'Edit',
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            bottomLeft: Radius.circular(12),
                          ),
                        ),
                        SlidableAction(
                          onPressed: (_) => _deleteClient(client['id'], i),
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          icon: Icons.delete,
                          label: 'Delete',
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                      ],
                    ),
                    child: Card(
                      color: AppColors.surface,
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        title: Text(
                          client['name'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          "${client['age']} Years Old",
                          style: const TextStyle(color: Colors.grey),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          color: AppColors.volt,
                          size: 16,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClientDetailScreen(
                                clientId: client['id'],
                                clientName: client['name'],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ==========================================
// CLIENT DETAIL SCREEN (FIXED WITH REALTIME)
// ==========================================
class ClientDetailScreen extends StatefulWidget {
  final String clientId;
  final String clientName;
  const ClientDetailScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  final _supabase = Supabase.instance.client;
  final AudioRecorder _recorder = AudioRecorder();
  List<Map<String, dynamic>> _workouts = [];
  bool _isRecording = false;

  // Realtime Channel to listen for database changes
  late RealtimeChannel _workoutsChannel;

  // Timer & Animations
  Timer? _countdownTimer;
  Timer? _amplitudeTimer;
  int _secondsLeft = 30;
  String? _currentRecordingPath;

  // Wave Animation
  List<double> _amplitudeBars = List<double>.filled(10, 0.1);

  // Plan & Recording Limit
  String _userPlan = 'free';
  int _monthlyRecordingCount = 0;
  final int _freeRecordingLimit = 2;
  int _failedAttempts = 0; // Track failed voice recording attempts

  @override
  void initState() {
    super.initState();
    _fetchClientWorkouts();
    _fetchPlanData();

    // --- REALTIME LISTENER ---
    // This listens for any NEW workout added for this specific client
    // As soon as the AI inserts the row, this triggers and refreshes the list
    _workoutsChannel = _supabase
        .channel('public:workouts:client=${widget.clientId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'workouts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'client_id',
            value: widget.clientId,
          ),
          callback: (payload) {
            // New workout detected! Refresh the list immediately.
            _fetchClientWorkouts();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _recorder.dispose();
    _countdownTimer?.cancel();
    _amplitudeTimer?.cancel();
    _supabase.removeChannel(_workoutsChannel); // Clean up listener
    super.dispose();
  }

  Future<void> _fetchClientWorkouts() async {
    try {
      final res = await _supabase
          .from('workouts')
          .select('*, workout_sets(*)')
          .eq('client_id', widget.clientId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() => _workouts = List<Map<String, dynamic>>.from(res));
      }
    } catch (e) {
      debugPrint('Error fetching workouts: $e');
    }
  }

  Future<void> _fetchPlanData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Get Plan, Recording Counter, and Failed Attempts
      final profile = await _supabase
          .from('profiles')
          .select(
            'plan, recordings_this_month, recording_month, failed_voice_attempts',
          )
          .eq('id', user.id)
          .maybeSingle();

      // Get recordings counter with month reset logic
      final currentMonth = DateTime.now().month;
      int recordingsUsed = profile?['recordings_this_month'] ?? 0;
      int savedMonth = profile?['recording_month'] ?? currentMonth;

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

      if (mounted) {
        setState(() {
          _userPlan = profile?['plan'] ?? 'free';
          _monthlyRecordingCount = recordingsUsed;
          _failedAttempts = profile?['failed_voice_attempts'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error fetching plan: $e');
    }
  }

  void _showRecordingLimitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          "Recording Limit Reached",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "You have used your 3 free voice logs this month. Upgrade to Pro for unlimited recording.",
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
                MaterialPageRoute(
                  builder: (_) => const ProScreen(isCoach: true),
                ),
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
      debugPrint('=== Starting workout update ===');
      debugPrint('Workout ID: $id, New Name: $newName');
      debugPrint('Updated sets count: ${updatedSets.length}');

      // 1. Update workout name
      final workoutResult = await _supabase
          .from('workouts')
          .update({'name': newName})
          .eq('id', id)
          .select();
      debugPrint('Workout update result: $workoutResult');

      // 2. Update each exercise in workout_sets
      for (final set in updatedSets) {
        debugPrint('Updating set ID: ${set['id']} - ${set['exercise_name']}');
        final setResult = await _supabase
            .from('workout_sets')
            .update({
              'exercise_name': set['exercise_name'],
              'sets': set['sets'],
              'reps': set['reps'],
              'weight': set['weight'],
            })
            .eq('id', set['id'])
            .select();
        debugPrint('Set update result: $setResult');
      }

      debugPrint('=== All updates complete, refreshing data ===');

      // 3. Refresh workouts from database to ensure data is in sync
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop(); // Close loading dialog
        await _fetchClientWorkouts();
        debugPrint('=== Data refreshed ===');
      }
    } catch (e) {
      debugPrint('=== UPDATE ERROR: $e ===');
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
      await _supabase.from('workout_sets').delete().eq('workout_id', id);
      await _supabase.from('workouts').delete().eq('id', id);

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {
          _workouts.removeAt(index);
        });
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to delete: $e")));
      }
    }
  }

  Future<void> _startRecording() async {
    // Check recording limit for free users
    if (_userPlan == 'free' && _monthlyRecordingCount >= _freeRecordingLimit) {
      _showRecordingLimitDialog();
      return;
    }

    if (!await _recorder.hasPermission()) return;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/client_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _secondsLeft = 30;
      _currentRecordingPath = path;
    });

    // Start countdown timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        _stopRecording();
      } else {
        setState(() => _secondsLeft--);
      }
    });

    // Amplitude listener
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      try {
        final amp = await _recorder.getAmplitude();
        double normalized = (amp.current + 50) / 50;
        if (normalized < 0) normalized = 0;
        if (normalized > 1) normalized = 1;
        if (mounted) {
          setState(() {
            for (int i = 0; i < _amplitudeBars.length - 1; i++) {
              _amplitudeBars[i] = _amplitudeBars[i + 1];
            }
            _amplitudeBars.last = normalized;
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _stopRecording() async {
    if (_currentRecordingPath == null) return;

    await _recorder.stop();
    _countdownTimer?.cancel();
    _amplitudeTimer?.cancel();

    final path = _currentRecordingPath!;
    setState(() {
      _isRecording = false;
      _currentRecordingPath = null;
    });

    // Upload & Process
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
      final storagePath =
          '${_supabase.auth.currentUser!.id}/${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _supabase.storage
          .from('workouts-audio')
          .upload(storagePath, File(path));

      // Call Edge Function and check response
      final response = await _supabase.functions.invoke(
        'process-workout',
        body: {
          'storage_path': storagePath,
          'duration': 30 - _secondsLeft,
          'client_id': widget.clientId, // This ensures it goes to the client
        },
      );

      // Close processing dialog
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      // Check for errors in response
      final data = response.data;
      if (data != null && data['error'] != null) {
        // Show error dialog - DO NOT increment recording count on error
        if (mounted) {
          _failedAttempts++;
          _showVoiceErrorDialog();
        }
        return;
      }

      // SUCCESS: Only increment recordings counter on successful processing
      // Direct update instead of RPC (more reliable)
      await _supabase
          .from('profiles')
          .update({
            'recordings_this_month': _monthlyRecordingCount + 1,
            'recording_month': DateTime.now().month,
          })
          .eq('id', _supabase.auth.currentUser!.id);

      // Refresh data
      if (mounted) {
        await _fetchClientWorkouts();
        await _fetchPlanData(); // Refresh the counter
      }
    } catch (e) {
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

  void _openManualWorkout() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManualWorkoutScreenForClient(
          clientId: widget.clientId,
          clientName: widget.clientName,
        ),
      ),
    );
    // Refresh workouts after returning (in case realtime doesn't trigger)
    if (result == true && mounted) {
      await _fetchClientWorkouts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.clientName,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note, color: AppColors.volt),
            tooltip: "Manual Workout",
            onPressed: _openManualWorkout,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Workout List
          _workouts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.fitness_center,
                        size: 60,
                        color: Colors.grey.shade700,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "No workouts yet",
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Record or log a workout below",
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                  itemCount: _workouts.length,
                  itemBuilder: (ctx, i) {
                    final w = _workouts[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 0),
                      child: Slidable(
                        key: Key(w['id'].toString()),
                        endActionPane: ActionPane(
                          motion: const DrawerMotion(),
                          extentRatio: 0.4,
                          children: [
                            SlidableAction(
                              onPressed: (_) => _showEditWorkoutDialog(w, i),
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              icon: Icons.edit,
                              label: 'Edit',
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                bottomLeft: Radius.circular(16),
                              ),
                            ),
                            SlidableAction(
                              onPressed: (_) => _deleteWorkout(w['id'], i),
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
                        child: _ClientWorkoutCard(data: w),
                      ),
                    );
                  },
                ),

          // Recording UI Overlay
          if (_isRecording)
            Positioned(
              bottom: 90,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 160,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppColors.volt, width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: _amplitudeBars
                            .map(
                              (h) => AnimatedContainer(
                                duration: const Duration(milliseconds: 100),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1.5,
                                ),
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
            ),

          // Mic Button
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isRecording ? _stopRecording : _startRecording,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _isRecording ? Colors.red : AppColors.volt,
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
                    _isRecording ? Icons.stop : Icons.mic,
                    color: Colors.black,
                    size: 30,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// MANUAL WORKOUT FOR CLIENT (Coach Version)
// ==========================================
class ManualWorkoutScreenForClient extends StatefulWidget {
  final String clientId;
  final String clientName;
  const ManualWorkoutScreenForClient({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<ManualWorkoutScreenForClient> createState() =>
      _ManualWorkoutScreenForClientState();
}

class _ManualWorkoutScreenForClientState
    extends State<ManualWorkoutScreenForClient> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  final TextEditingController _nameCtrl = TextEditingController();
  final List<Map<String, dynamic>> _exercises = [];

  @override
  void initState() {
    super.initState();
    _addExerciseRow();
  }

  void _addExerciseRow() {
    setState(() {
      _exercises.add({
        'name': TextEditingController(),
        'sets': TextEditingController(),
        'reps': TextEditingController(),
        'weight': TextEditingController(),
      });
    });
  }

  void _removeExerciseRow(int index) {
    setState(() {
      _exercises.removeAt(index);
    });
  }

  Future<void> _saveWorkout() async {
    if (!_formKey.currentState!.validate()) return;
    if (_exercises.isEmpty) return;

    setState(() => _loading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Create Workout FOR CLIENT
      final workoutRes = await _supabase
          .from('workouts')
          .insert({
            'user_id': user.id,
            'client_id': widget.clientId,
            'name': _nameCtrl.text.isEmpty ? 'Manual Workout' : _nameCtrl.text,
            'date': DateTime.now().toIso8601String(),
            'notes': 'Manual Entry by Coach',
            'duration_seconds': 0,
          })
          .select()
          .single();

      // Create Sets
      final List<Map<String, dynamic>> setsToInsert = [];

      for (int i = 0; i < _exercises.length; i++) {
        final ex = _exercises[i];
        setsToInsert.add({
          'workout_id': workoutRes['id'],
          'exercise_name': ex['name'].text,
          'sets': int.tryParse(ex['sets'].text) ?? 0,
          'reps': int.tryParse(ex['reps'].text) ?? 0,
          'weight': double.tryParse(ex['weight'].text) ?? 0.0,
          'order_index': i,
        });
      }

      await _supabase.from('workout_sets').insert(setsToInsert);

      if (mounted) {
        Navigator.pop(context, true); // Return true to trigger refresh
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          "Log for ${widget.clientName}",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _loading ? null : _saveWorkout,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: AppColors.volt),
                  )
                : const Text(
                    "SAVE",
                    style: TextStyle(
                      color: AppColors.volt,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Workout Name (e.g., Chest Day)",
                fillColor: AppColors.surface,
                filled: true,
                labelStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              "Exercises",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            ..._exercises.asMap().entries.map((entry) {
              int idx = entry.key;
              var controllers = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _miniInput(
                            controllers['name'],
                            "Exercise Name",
                          ),
                        ),
                        IconButton(
                          onPressed: () => _removeExerciseRow(idx),
                          icon: const Icon(
                            Icons.close,
                            color: Colors.grey,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _miniInput(
                            controllers['sets'],
                            "Sets",
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _miniInput(
                            controllers['reps'],
                            "Reps",
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _miniInput(
                            controllers['weight'],
                            "Kg",
                            isNumber: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addExerciseRow,
              icon: const Icon(Icons.add, color: AppColors.volt),
              label: const Text(
                "Add Exercise",
                style: TextStyle(color: AppColors.volt),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.volt),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _miniInput(
    TextEditingController ctrl,
    String hint, {
    bool isNumber = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: hint,
        isDense: true,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      validator: (v) => v!.isEmpty ? "Req" : null,
    );
  }
}

// ==========================================
// CLIENT WORKOUT CARD (Matches User's Style)
// ==========================================
class _ClientWorkoutCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ClientWorkoutCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final sets = (data['workout_sets'] as List?) ?? [];
    final date = DateTime.tryParse(data['date'] ?? '') ?? DateTime.now();

    // Sort by order_index
    final sortedSets = List<dynamic>.from(sets);
    sortedSets.sort(
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
                const Row(
                  children: [
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
                ...sortedSets.map(
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
                ),
              ],
            ),
          ),

          if (sortedSets.isEmpty)
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
