import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized subscription state manager.
/// Uses RevenueCat as the source of truth for entitlement status.
/// Listens for real-time CustomerInfo updates so premium state
/// refreshes immediately after purchase, restore, or cancellation.
class SubscriptionService {
  // ── Singleton ──
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  /// Reactive flag that any widget can listen to.
  final ValueNotifier<bool> isPro = ValueNotifier<bool>(false);

  bool _initialized = false;

  /// Call once after RevenueCat is configured (in main.dart).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Register a global listener so the app reacts immediately
    // whenever Apple confirms a purchase, restore, or expiry.
    Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdate);

    // Do an initial check right away.
    await checkEntitlement();
  }

  // ── Called every time RevenueCat has new CustomerInfo ──
  void _onCustomerInfoUpdate(CustomerInfo info) {
    // === DEBUG: Print ALL entitlements RevenueCat knows about ===
    debugPrint('═══════════════════════════════════════');
    debugPrint('🔍 RevenueCat CustomerInfo Dump:');
    debugPrint('   Customer ID: ${info.originalAppUserId}');
    debugPrint('   Active Subscriptions: ${info.activeSubscriptions}');
    debugPrint(
      '   All Entitlement IDs: ${info.entitlements.all.keys.toList()}',
    );
    for (final entry in info.entitlements.all.entries) {
      debugPrint('   Entitlement "${entry.key}":');
      debugPrint('     isActive: ${entry.value.isActive}');
      debugPrint('     productId: ${entry.value.productIdentifier}');
      debugPrint('     isSandbox: ${entry.value.isSandbox}');
    }
    debugPrint('═══════════════════════════════════════');

    final active = info.entitlements.all["Pro"]?.isActive == true;
    isPro.value = active;
    debugPrint('🔔 SubscriptionService: pro=${isPro.value}');

    // Keep Supabase in sync (fire-and-forget).
    _syncToSupabase(active, info);
  }

  /// Manually refresh entitlement (e.g. on app resume, pull‑to‑refresh).
  Future<void> checkEntitlement() async {
    try {
      final info = await Purchases.getCustomerInfo();
      _onCustomerInfoUpdate(info);
    } catch (e) {
      debugPrint('⚠️ SubscriptionService.checkEntitlement failed: $e');
    }
  }

  /// Link the RevenueCat anonymous user to the Supabase user ID.
  /// Must be called after every successful login / sign-up.
  Future<void> loginUser(String supabaseUserId) async {
    try {
      debugPrint('🔗 Calling Purchases.logIn($supabaseUserId)...');
      final result = await Purchases.logIn(supabaseUserId);
      debugPrint('🔗 logIn result - created: ${result.created}');
      _onCustomerInfoUpdate(result.customerInfo);
      debugPrint('🔗 RevenueCat logged in as $supabaseUserId');
    } catch (e) {
      debugPrint('⚠️ RevenueCat logIn failed: $e');
    }
  }

  /// Unlink RevenueCat user on sign-out.
  Future<void> logoutUser() async {
    try {
      if (await Purchases.isAnonymous == false) {
        await Purchases.logOut();
      }
      isPro.value = false;
      debugPrint('🔓 RevenueCat logged out');
    } catch (e) {
      debugPrint('⚠️ RevenueCat logOut failed: $e');
    }
  }

  // ── Keep Supabase profiles table in sync ──
  Future<void> _syncToSupabase(bool active, CustomerInfo info) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final productId = info.entitlements.all["Pro"]?.productIdentifier ?? '';

      if (active) {
        await Supabase.instance.client
            .from('profiles')
            .update({'plan': 'pro', 'product_id': productId})
            .eq('id', user.id);
      } else {
        // Only revert if not a gifted pro (gifted pro has pro_expires_at)
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('pro_expires_at')
            .eq('id', user.id)
            .maybeSingle();
        final hasGiftExpiry = profile?['pro_expires_at'] != null;

        if (!hasGiftExpiry) {
          await Supabase.instance.client
              .from('profiles')
              .update({'plan': 'free', 'product_id': null})
              .eq('id', user.id);
        }
      }
    } catch (e) {
      debugPrint('⚠️ SubscriptionService._syncToSupabase failed: $e');
    }
  }
}
