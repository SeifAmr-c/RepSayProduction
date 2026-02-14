import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart'; // For AppColors

class ProScreen extends StatefulWidget {
  final bool isCoach;
  const ProScreen({super.key, this.isCoach = false});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  // 0 = Monthly, 1 = Annual
  int _selectedPlan = 1;
  bool _isLoading = false;

  // Dynamic pricing based on user type
  double get _monthlyPrice => widget.isCoach ? 350.0 : 79.99;
  double get _annualPrice => widget.isCoach ? 3500.0 : 899.99;

  String get _savingsText {
    // Monthly * 12 = 959.88. Annual = 899.99. Savings = ~60.
    final yearlyCostOfMonthly = _monthlyPrice * 12;
    final savedAmount = yearlyCostOfMonthly - _annualPrice;
    final percent = (savedAmount / yearlyCostOfMonthly * 100).round();
    return "Save ${percent}% (EGP ${savedAmount.toStringAsFixed(0)})/year";
  }

  Future<void> _makePurchase() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch the "Menu" from RevenueCat
      Offerings offerings = await Purchases.getOfferings();

      if (offerings.current != null) {
        Package? packageToBuy;

        // 2. Select the right package based on user choice
        if (_selectedPlan == 0) {
          packageToBuy = offerings.current!.monthly;
        } else {
          packageToBuy = offerings.current!.annual;
        }

        // 3. Trigger the Apple Pay Sheet
        if (packageToBuy != null) {
          CustomerInfo customerInfo = await Purchases.purchasePackage(
            packageToBuy,
          );

          // 4. Check if the purchase was successful
          if (customerInfo.entitlements.all["pro"]?.isActive == true) {
            if (mounted) {
              // OPTIONAL: Save "Pro" status to your database as a backup
              final user = Supabase.instance.client.auth.currentUser;
              if (user != null) {
                await Supabase.instance.client
                    .from('profiles')
                    .update({'plan': 'pro'})
                    .eq('id', user.id);
              }

              Navigator.pop(context, true); // Refresh the previous screen
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("Welcome to Pro!")));
            }
          }
        }
      }
    } on PlatformException catch (e) {
      // Handle User Cancellation or Apple Errors
      var errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message ?? "Error")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              const Icon(Icons.star, color: AppColors.volt, size: 60),
              const SizedBox(height: 20),
              Text(
                widget.isCoach ? "Coach Pro Access" : "Unlock Full Access",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.isCoach
                    ? "Unlimited clients, recording, and analytics."
                    : "Unlimited recording, cloud backup, and advanced analytics.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 40),

              // Plans
              _buildPlanOption(
                index: 0,
                title: "Monthly",
                price: "EGP $_monthlyPrice / mo",
                subtitle: "Cancel anytime",
              ),
              const SizedBox(height: 16),
              _buildPlanOption(
                index: 1,
                title: "Annual",
                price: "EGP ${_annualPrice.toStringAsFixed(0)} / yr",
                subtitle: _savingsText,
                isBestValue: true,
              ),

              const SizedBox(height: 40),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade800)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      "SECURED BY APP STORE",
                      style: TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade800)),
                ],
              ),
              const SizedBox(height: 20),

              // Apple Pay / Subscribe Button
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _makePurchase,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, // Apple Pay style
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.apple, size: 28),
                  label: Text(
                    _isLoading ? "PROCESSING..." : "Subscribe with Apple Pay",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanOption({
    required int index,
    required String title,
    required String price,
    String? subtitle,
    bool isBestValue = false,
  }) {
    final isSelected = _selectedPlan == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedPlan = index);
        HapticFeedback.selectionClick();
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.volt : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio Circle
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.volt : Colors.grey,
                ),
                color: isSelected ? AppColors.volt : null,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.black)
                  : null,
            ),
            const SizedBox(width: 16),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      if (isBestValue) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.volt,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            "BEST VALUE",
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    price,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isBestValue ? AppColors.volt : Colors.grey,
                        fontSize: 12,
                        fontWeight: isBestValue
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
