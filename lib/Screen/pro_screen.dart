import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart'; // For AppColors
import '../Services/subscription_service.dart';

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
    _checkExistingEntitlement();
  }

  /// If user already has an active subscription, redirect back immediately
  Future<void> _checkExistingEntitlement() async {
    await SubscriptionService.instance.checkEntitlement();
    if (SubscriptionService.instance.isPro.value && mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You already have Pro access! 🎉")),
      );
    }
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
          SnackBar(
            content: const Text(
              "Subscription not available. Please try again later.",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    bool alreadyPopped = false;
    try {
      // Trigger the In-App Purchase sheet via RevenueCat
      CustomerInfo customerInfo = await Purchases.purchasePackage(packageToBuy);

      // Check if the purchase was successful
      if (customerInfo.entitlements.all["Pro"]?.isActive == true) {
        await SubscriptionService.instance.checkEntitlement();

        if (mounted) {
          alreadyPopped = true;
          await _showCongratsDialog();
          if (mounted) Navigator.pop(context, true);
        }
      }
    } on PlatformException catch (e) {
      var errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e.message ?? "Purchase failed",
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: AppColors.surface,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    } finally {
      await SubscriptionService.instance.checkEntitlement();
      if (!alreadyPopped &&
          SubscriptionService.instance.isPro.value &&
          mounted) {
        await _showCongratsDialog();
        if (mounted) Navigator.pop(context, true);
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Shows a congratulations dialog when the user upgrades to Pro.
  Future<void> _showCongratsDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.star, color: AppColors.volt, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "Congratulations! 🎉",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          "You have been upgraded to Pro!\n\nYou now have unlimited access to voice recordings and weight analysis, and also have access to early access features.",
          style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.volt,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text(
              "Let's Go!",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);

    // Show loading spinner dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          color: AppColors.surface,
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.volt),
                SizedBox(height: 16),
                Text(
                  "Restoring purchases...",
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      CustomerInfo customerInfo = await Purchases.restorePurchases();
      await SubscriptionService.instance.checkEntitlement();

      // Close spinner
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (customerInfo.entitlements.all["Pro"]?.isActive == true ||
          SubscriptionService.instance.isPro.value) {
        if (mounted) {
          await _showCongratsDialog();
          if (mounted) Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                "No active subscription found.",
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: AppColors.surface,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    } catch (e) {
      // Close spinner
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "Failed to restore purchases.",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
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
                              : const Icon(Icons.lock_open, size: 24),
                          label: Text(
                            _isLoading ? "PROCESSING..." : "Subscribe Now",
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

                    const SizedBox(height: 16),

                    // ── Subscription Compliance Footer (Guideline 3.1.2) ──
                    const Text(
                      'Subscriptions will be charged to your Apple ID account '
                      'at confirmation of purchase. Subscriptions automatically '
                      'renew unless cancelled at least 24 hours before the end '
                      'of the current period. Your account will be charged for '
                      'renewal within 24 hours prior to the end of the current '
                      'period. You can manage and cancel your subscriptions by '
                      'going to your account settings on the App Store after '
                      'purchase.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => launchUrl(
                            Uri.parse('https://repsayyy.vercel.app/#terms'),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text(
                            'Terms of Use',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '·',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => launchUrl(
                            Uri.parse('https://repsayyy.vercel.app/#privacy'),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text(
                            'Privacy Policy',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
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
