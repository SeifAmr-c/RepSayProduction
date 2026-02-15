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
  bool _loadingOfferings = true;

  // RevenueCat packages (loaded dynamically)
  Package? _monthlyPackage;
  Package? _annualPackage;

  @override
  void initState() {
    super.initState();
    _fetchOfferings();
  }

  /// Fetch offerings from RevenueCat based on user type (user vs coach)
  Future<void> _fetchOfferings() async {
    try {
      Offerings offerings = await Purchases.getOfferings();

      // Select the right offering based on user type
      final offeringId = widget.isCoach ? 'coach_pro' : 'user_pro';
      Offering? offering = offerings.getOffering(offeringId);

      // Fallback to 'default' offering if specific one isn't found
      offering ??= offerings.current;

      if (offering != null) {
        setState(() {
          _monthlyPackage = offering!.monthly;
          _annualPackage = offering.annual;
          _loadingOfferings = false;
        });
      } else {
        setState(() => _loadingOfferings = false);
      }
    } catch (e) {
      debugPrint('❌ Failed to fetch offerings: $e');
      setState(() => _loadingOfferings = false);
    }
  }

  /// Get the display price for a package (localized by App Store)
  String _getPrice(Package? package, String fallback) {
    if (package == null) return fallback;
    return package.storeProduct.priceString;
  }

  /// Calculate savings percentage between monthly and annual
  String get _savingsText {
    if (_monthlyPackage == null || _annualPackage == null) {
      return "Best Value";
    }
    final monthlyPrice = _monthlyPackage!.storeProduct.price;
    final annualPrice = _annualPackage!.storeProduct.price;
    final yearlyCostOfMonthly = monthlyPrice * 12;
    final savedAmount = yearlyCostOfMonthly - annualPrice;
    if (yearlyCostOfMonthly <= 0) return "Best Value";
    final percent = (savedAmount / yearlyCostOfMonthly * 100).round();
    return "Save $percent%";
  }

  Future<void> _makePurchase() async {
    final packageToBuy = _selectedPlan == 0 ? _monthlyPackage : _annualPackage;

    if (packageToBuy == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Subscription not available. Please try again later.",
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Trigger the Apple Pay Sheet via RevenueCat
      CustomerInfo customerInfo = await Purchases.purchasePackage(packageToBuy);

      // Check if the purchase was successful
      if (customerInfo.entitlements.all["pro"]?.isActive == true) {
        if (mounted) {
          // Save "Pro" status to database as a backup
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
          ).showSnackBar(const SnackBar(content: Text("Welcome to Pro! 🎉")));
        }
      }
    } on PlatformException catch (e) {
      // Handle User Cancellation or Apple Errors
      var errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? "Purchase failed")),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    try {
      CustomerInfo customerInfo = await Purchases.restorePurchases();
      if (customerInfo.entitlements.all["pro"]?.isActive == true) {
        if (mounted) {
          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            await Supabase.instance.client
                .from('profiles')
                .update({'plan': 'pro'})
                .eq('id', user.id);
          }

          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Pro access restored! 🎉")),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No active subscription found.")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to restore purchases.")),
        );
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
        child: _loadingOfferings
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.volt),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    const Icon(Icons.star, color: AppColors.volt, size: 60),
                    const SizedBox(height: 20),
                    Text(
                      widget.isCoach
                          ? "Coach Pro Access"
                          : "Unlock Full Access",
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
                    if (_monthlyPackage != null)
                      _buildPlanOption(
                        index: 0,
                        title: "Monthly",
                        price: "${_getPrice(_monthlyPackage, '')} / mo",
                        subtitle: "Cancel anytime",
                      ),
                    if (_monthlyPackage != null) const SizedBox(height: 16),
                    if (_annualPackage != null)
                      _buildPlanOption(
                        index: 1,
                        title: "Annual",
                        price: "${_getPrice(_annualPackage, '')} / yr",
                        subtitle: _savingsText,
                        isBestValue: true,
                      ),

                    if (_monthlyPackage == null && _annualPackage == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          "Subscriptions are not available right now.\nPlease try again later.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
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

                    // Subscribe Button
                    if (_monthlyPackage != null || _annualPackage != null)
                      SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _makePurchase,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
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
                            _isLoading
                                ? "PROCESSING..."
                                : "Subscribe with Apple Pay",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Restore Purchases
                    TextButton(
                      onPressed: _isLoading ? null : _restorePurchases,
                      child: const Text(
                        "Restore Purchases",
                        style: TextStyle(
                          color: Colors.grey,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
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
