import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles in-app review prompts using Apple's native SKStoreReviewController.
/// Ratings go directly to the App Store (5-star system).
///
/// Timing logic:
/// - First prompt: 2 days after app install
/// - Repeat: every 3 days if user hasn't rated yet
class ReviewHelper {
  static const String _installDateKey = 'review_install_date';
  static const String _lastPromptKey = 'review_last_prompt_date';
  static const String _hasRatedKey = 'review_has_rated';

  static const int _daysBeforeFirstPrompt = 2;
  static const int _daysBetweenPrompts = 3;

  /// Call this after the main screen loads. It checks timing and
  /// conditionally triggers Apple's native review dialog.
  static Future<void> checkAndRequestReview() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // If user already rated, never prompt again
      if (prefs.getBool(_hasRatedKey) == true) return;

      final now = DateTime.now();

      // Record install date on first launch
      final installDateStr = prefs.getString(_installDateKey);
      if (installDateStr == null) {
        await prefs.setString(_installDateKey, now.toIso8601String());
        debugPrint('📱 ReviewHelper: Install date recorded');
        return; // First launch, don't prompt yet
      }

      final installDate = DateTime.parse(installDateStr);
      final daysSinceInstall = now.difference(installDate).inDays;

      // Don't prompt if less than 2 days since install
      if (daysSinceInstall < _daysBeforeFirstPrompt) {
        debugPrint(
          '📱 ReviewHelper: Too soon (${daysSinceInstall}d since install, need ${_daysBeforeFirstPrompt}d)',
        );
        return;
      }

      // Check if enough time passed since last prompt
      final lastPromptStr = prefs.getString(_lastPromptKey);
      if (lastPromptStr != null) {
        final lastPrompt = DateTime.parse(lastPromptStr);
        final daysSinceLastPrompt = now.difference(lastPrompt).inDays;
        if (daysSinceLastPrompt < _daysBetweenPrompts) {
          debugPrint(
            '📱 ReviewHelper: Too soon since last prompt (${daysSinceLastPrompt}d, need ${_daysBetweenPrompts}d)',
          );
          return;
        }
      }

      // Check if in-app review is available
      final inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        debugPrint('📱 ReviewHelper: Requesting review...');
        await inAppReview.requestReview();

        // Save the prompt date
        await prefs.setString(_lastPromptKey, now.toIso8601String());

        // Mark as rated after showing (Apple doesn't tell us if user rated,
        // but after showing the native dialog we assume they either rated
        // or dismissed it — we'll re-prompt in 3 days if they dismissed)
        debugPrint('📱 ReviewHelper: Review dialog shown');
      } else {
        debugPrint('📱 ReviewHelper: In-app review not available');
      }
    } catch (e) {
      debugPrint('📱 ReviewHelper: Error - $e');
    }
  }

  /// Call this to mark the user as having rated (optional, for manual tracking).
  static Future<void> markAsRated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasRatedKey, true);
    debugPrint('📱 ReviewHelper: Marked as rated');
  }

  /// Reset all review tracking (useful for testing).
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_installDateKey);
    await prefs.remove(_lastPromptKey);
    await prefs.remove(_hasRatedKey);
    debugPrint('📱 ReviewHelper: Reset all tracking');
  }
}
