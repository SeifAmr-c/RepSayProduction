import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart'; // For AppColors

class ManualWorkoutScreen extends StatefulWidget {
  const ManualWorkoutScreen({super.key});

  @override
  State<ManualWorkoutScreen> createState() => _ManualWorkoutScreenState();
}

class _ManualWorkoutScreenState extends State<ManualWorkoutScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  final TextEditingController _nameCtrl = TextEditingController();
  final List<Map<String, dynamic>> _exercises = [];

  @override
  void initState() {
    super.initState();
    _addExerciseRow(); // Start with one empty row
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

      // 1. Create Workout
      final workoutRes = await _supabase
          .from('workouts')
          .insert({
            'user_id': user.id,
            'name': _nameCtrl.text.isEmpty ? 'Manual Workout' : _nameCtrl.text,
            'date': DateTime.now().toIso8601String(),
            'notes': 'Manual Entry',
            'duration_seconds': 0,
          })
          .select()
          .single();

      // 2. Create Sets
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
        Navigator.pop(context, true); // Return "true" to refresh home
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Log Workout", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _loading ? null : _saveWorkout,
            child: _loading 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.volt)) 
              : const Text("SAVE", style: TextStyle(color: AppColors.volt, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Workout Name
            TextFormField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Workout Name (e.g., Chest Day)",
                fillColor: AppColors.surface, filled: true,
                labelStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),
            
            const Text("Exercises", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            // Dynamic List
            ..._exercises.asMap().entries.map((entry) {
              int idx = entry.key;
              var controllers = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _miniInput(controllers['name'], "Exercise Name")),
                        IconButton(onPressed: () => _removeExerciseRow(idx), icon: const Icon(Icons.close, color: Colors.grey, size: 20))
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _miniInput(controllers['sets'], "Sets", isNumber: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _miniInput(controllers['reps'], "Reps", isNumber: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _miniInput(controllers['weight'], "Kg", isNumber: true)),
                      ],
                    )
                  ],
                ),
              );
            }).toList(),

            // Add Button
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addExerciseRow,
              icon: const Icon(Icons.add, color: AppColors.volt),
              label: const Text("Add Exercise", style: TextStyle(color: AppColors.volt)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.volt), padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _miniInput(TextEditingController ctrl, String hint, {bool isNumber = false}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: hint,
        isDense: true,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      validator: (v) => v!.isEmpty ? "Req" : null,
    );
  }
}