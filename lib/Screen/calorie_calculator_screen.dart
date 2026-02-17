import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';

class CalorieCalculatorScreen extends StatefulWidget {
  const CalorieCalculatorScreen({super.key});

  @override
  State<CalorieCalculatorScreen> createState() =>
      _CalorieCalculatorScreenState();
}

class _CalorieCalculatorScreenState extends State<CalorieCalculatorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ageCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  String _selectedGoal = 'Maintaining';
  bool _isCalculating = false;
  int? _calculatedCalories;

  @override
  void dispose() {
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  /// Mifflin-St Jeor equation + goal modifier
  int _calculateCalories() {
    final age = int.parse(_ageCtrl.text.trim());
    final weight = double.parse(_weightCtrl.text.trim());
    final height = double.parse(_heightCtrl.text.trim());

    // Mifflin-St Jeor (using male formula as a general baseline)
    // BMR = 10 * weight(kg) + 6.25 * height(cm) – 5 * age – 5 (adjusted)
    double bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;

    // Activity multiplier (moderate activity assumed)
    double tdee = bmr * 1.55;

    // Goal adjustment
    switch (_selectedGoal) {
      case 'Bulking':
        tdee += 500; // Caloric surplus
        break;
      case 'Cutting':
        tdee -= 500; // Caloric deficit
        break;
      case 'Maintaining':
      default:
        break; // No change
    }

    return tdee.round();
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCalculating = true);

    // Simulate processing time
    await Future.delayed(const Duration(milliseconds: 1500));

    final calories = _calculateCalories();

    if (mounted) {
      setState(() {
        _calculatedCalories = calories;
        _isCalculating = false;
      });
    }
  }

  void _resetForm() {
    _ageCtrl.clear();
    _weightCtrl.clear();
    _heightCtrl.clear();
    setState(() {
      _selectedGoal = 'Maintaining';
      _calculatedCalories = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _isCalculating
            ? _buildLoadingView()
            : _calculatedCalories != null
            ? _buildResultView()
            : _buildFormView(),
      ),
    );
  }

  // ── LOADING VIEW ──
  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              color: AppColors.volt,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "Processing...",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Calculating your calorie needs",
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── FORM VIEW ──
  Widget _buildFormView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.volt.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.volt.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.local_fire_department_rounded,
                      color: AppColors.volt,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Calculate Your Intake",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "Fill in your details to get an estimated daily calorie target.",
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Age field
            _buildLabel("Age"),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _ageCtrl,
              hint: "e.g. 25",
              suffix: "years",
              maxLength: 2,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter your age';
                }
                final age = int.tryParse(v.trim());
                if (age == null || age < 10 || age > 99) {
                  return 'Enter a valid age (10-99)';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Weight field
            _buildLabel("Weight"),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _weightCtrl,
              hint: "e.g. 75",
              suffix: "kg",
              allowDecimal: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter your weight';
                }
                final weight = double.tryParse(v.trim());
                if (weight == null || weight < 20 || weight > 300) {
                  return 'Enter a valid weight (20-300 kg)';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Height field
            _buildLabel("Height"),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _heightCtrl,
              hint: "e.g. 175",
              suffix: "cm",
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter your height';
                }
                final height = double.tryParse(v.trim());
                if (height == null || height < 100 || height > 250) {
                  return 'Enter a valid height (100-250 cm)';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Goal dropdown
            _buildLabel("Goal"),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: DropdownButtonFormField<String>(
                value: _selectedGoal,
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                icon: Icon(Icons.keyboard_arrow_down, color: AppColors.volt),
                items: ['Bulking', 'Maintaining', 'Cutting']
                    .map(
                      (goal) => DropdownMenuItem(
                        value: goal,
                        child: Row(
                          children: [
                            Icon(
                              goal == 'Bulking'
                                  ? Icons.trending_up
                                  : goal == 'Cutting'
                                  ? Icons.trending_down
                                  : Icons.trending_flat,
                              color: AppColors.volt,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(goal),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedGoal = v);
                },
              ),
            ),
            const SizedBox(height: 40),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.volt,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  "Calculate",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── RESULT VIEW ──
  Widget _buildResultView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // Result card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.volt.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.volt.withOpacity(0.05),
                  blurRadius: 30,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.volt.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.local_fire_department_rounded,
                    color: AppColors.volt,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Your Needed Calorie Intake",
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Text(
                  "$_calculatedCalories",
                  style: TextStyle(
                    color: AppColors.volt,
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const Text(
                  "calories / day",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.volt.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "Goal: $_selectedGoal",
                    style: TextStyle(
                      color: AppColors.volt,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Disclaimer
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Do not take this as a trusted reference. Calorie needs differ from one person to another based on health conditions, activity level, and metabolism. For an accurate calorie intake, please visit a doctor or a certified nutritionist.",
                    style: TextStyle(
                      color: Colors.orange.withOpacity(0.9),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Buttons
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _resetForm,
              icon: const Icon(Icons.refresh),
              label: const Text(
                "Calculate Another",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.volt,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _resetForm,
              icon: const Icon(Icons.home_outlined),
              label: const Text(
                "Return to Home",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.grey.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── HELPERS ──
  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    String? suffix,
    int? maxLength,
    bool allowDecimal = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: [
        if (allowDecimal)
          FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
        else
          FilteringTextInputFormatter.digitsOnly,
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
      style: const TextStyle(color: Colors.white, fontSize: 16),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5)),
        suffixText: suffix,
        suffixStyle: TextStyle(color: AppColors.volt, fontSize: 14),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.volt),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        counterText: "",
      ),
    );
  }
}
