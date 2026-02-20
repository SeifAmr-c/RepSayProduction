import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart'; // Import to access AppColors
import 'auth_screen.dart';
import 'pro_screen.dart'; // Import Pro Screen
import 'admin_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String _email = '';
  String _plan = 'free';
  String _role = 'user';

  // Counters
  int _workoutsUsed = 0;
  int _clientsAdded = 0;

  // Limits
  final int _freeRecordingLimit = 2; // Free tier limit
  final int _freeClientLimit = 3; // Limit for Coaches

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    setState(() {
      _email = user.email ?? 'No Email';
    });

    try {
      // 1. Get Profile (Plan, Role, Recording & Client Counters)
      final profile = await _supabase
          .from('profiles')
          .select(
            'plan, role, recordings_this_month, recording_month, clients_added_this_month, client_month',
          )
          .eq('id', user.id)
          .maybeSingle();

      final plan = profile?['plan'] ?? 'free';
      final role = profile?['role'] ?? 'user';
      final currentMonth = DateTime.now().month;

      // Get recordings counter with month reset logic
      int workoutsCount = profile?['recordings_this_month'] ?? 0;
      int savedRecordingMonth = profile?['recording_month'] ?? currentMonth;

      // Get clients counter with month reset logic
      int clientsCount = profile?['clients_added_this_month'] ?? 0;
      int savedClientMonth = profile?['client_month'] ?? currentMonth;

      // Reset counters if month changed
      Map<String, dynamic> updates = {};
      if (savedRecordingMonth != currentMonth) {
        workoutsCount = 0;
        updates['recordings_this_month'] = 0;
        updates['recording_month'] = currentMonth;
      }
      if (savedClientMonth != currentMonth && role == 'coach') {
        clientsCount = 0;
        updates['clients_added_this_month'] = 0;
        updates['client_month'] = currentMonth;
      }
      if (updates.isNotEmpty) {
        await _supabase.from('profiles').update(updates).eq('id', user.id);
      }

      if (mounted) {
        setState(() {
          _plan = plan;
          _role = role;
          _workoutsUsed = workoutsCount;
          _clientsAdded = clientsCount;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
    if (mounted)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (r) => false,
      );
  }

  void _deleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent,
              size: 28,
            ),
            SizedBox(width: 10),
            Text("Delete Account", style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          "Are you sure you want to delete your account?\n\nThis action is permanent and will delete all your data including workouts, clients, and profile information.",
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performAccountDeletion();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  Future<void> _performAccountDeletion() async {
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
                  "Deleting account...",
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Call edge function to delete account
      // JWT token is automatically sent by Supabase client
      final response = await _supabase.functions.invoke('delete-account');

      // Close loading dialog
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      // Check for errors
      final data = response.data;
      if (data != null && data['error'] != null) {
        throw Exception(data['error']);
      }

      // Show success dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.volt, size: 28),
                SizedBox(width: 10),
                Text("Account Deleted", style: TextStyle(color: Colors.white)),
              ],
            ),
            content: const Text(
              "Your account and all associated data have been successfully deleted.",
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
                  backgroundColor: AppColors.volt,
                  foregroundColor: Colors.black,
                ),
                child: const Text("Continue"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 28),
                SizedBox(width: 10),
                Text("Error", style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text(
              "Failed to delete account: ${e.toString().replaceAll('Exception:', '').trim()}",
              style: const TextStyle(color: Colors.grey),
            ),
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
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Could not open $url")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.volt)),
      );

    final isPro = _plan == 'pro';
    final isCoach = _role == 'coach';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          "Settings",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // --- PRO BANNER START ---
          if (!isPro)
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProScreen(isCoach: isCoach),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFDbf756), Color(0xFFB4CC46)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.star,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Upgrade to Pro",
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isCoach
                                ? "Unlimited clients & recording."
                                : "Unlimited recording & backup.",
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.black,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),

          // --- PRO BANNER END ---
          _buildSection("Account"),
          _buildTile(Icons.email_outlined, "Email", _email),
          _buildTile(
            Icons.verified_outlined,
            "Plan",
            isPro ? "Pro Plan" : "Free Plan",
            trailing: isPro
                ? const Icon(Icons.star, color: AppColors.volt)
                : null,
          ),

          // --- USAGE TILES START ---

          // 1. Client Usage (Coach Only)
          if (isCoach)
            _buildTile(
              Icons.people_outline,
              "Clients Left",
              isPro
                  ? "Unlimited"
                  : "${_freeClientLimit - _clientsAdded} / $_freeClientLimit",
            ),

          // 2. Recording Usage (Everyone)
          _buildTile(
            Icons.mic_none_outlined,
            "Recordings Left",
            isPro
                ? "Unlimited"
                : "${_freeRecordingLimit - _workoutsUsed} / $_freeRecordingLimit",
          ),

          // --- USAGE TILES END ---
          _buildSection("Features"),
          _buildTile(
            Icons.new_releases_outlined,
            "What is new?",
            "Latest updates",
            onTap: () {},
          ),

          _buildSection("About App"),
          _buildTile(
            Icons.lock_outline,
            "Privacy Policy",
            "",
            onTap: () => _openUrl("https://repsayyy.vercel.app/#privacy"),
          ),
          _buildTile(
            Icons.info_outline,
            "About Us",
            "",
            onTap: () => _openUrl("https://repsayyy.vercel.app/#about"),
          ),
          _buildTile(
            Icons.mail_outline,
            "Contact Us",
            "",
            onTap: () => _openUrl("https://repsayyy.vercel.app/#contact"),
          ),
          _buildInstagramTile(),

          _buildSection("Actions"),
          // Admin button - only visible for admin email
          if (_email.toLowerCase() == 'seiffn162004@gmail.com')
            _buildActionTile(
              Icons.admin_panel_settings,
              "Admin Panel",
              AppColors.volt,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              ),
            ),
          _buildActionTile(
            Icons.logout,
            "Sign Out",
            Colors.redAccent,
            _signOut,
          ),
          _buildActionTile(
            Icons.delete_outline,
            "Delete Account",
            Colors.redAccent,
            _deleteAccount,
          ),

          const SizedBox(height: 16),

          // Beta notice
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "The app is in the beta phase. If you have any recommendations, contact us on our website.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.5),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildInstagramTile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        onTap: () => _openUrl(
          "https://www.instagram.com/repsayeg?igsh=MTI0ZDFwZGl5MzN2cA%3D%3D&utm_source=qr",
        ),
        leading: const Icon(
          Icons.photo_camera_front_outlined,
          color: AppColors.volt,
        ),
        title: const Text(
          "Instagram",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        trailing: SizedBox(
          width: 28,
          height: 28,
          child: CustomPaint(painter: _InstagramLogoPainter()),
        ),
      ),
    );
  }

  Widget _buildSection(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 10),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
  );

  Widget _buildTile(
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppColors.volt),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        subtitle: subtitle.isNotEmpty
            ? Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              )
            : null,
        trailing:
            trailing ??
            (onTap != null
                ? const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey,
                  )
                : null),
      ),
    );
  }

  Widget _buildActionTile(
    IconData icon,
    String title,
    Color color,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ),
    );
  }
}

// Custom painter that draws the Instagram logo shape in AppColors.volt
class _InstagramLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.volt
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Rounded rectangle (outer border)
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(8),
    );
    canvas.drawRRect(rrect, paint);

    // Center circle (camera lens)
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width * 0.22, paint);

    // Small dot (flash) top-right
    final dotPaint = Paint()
      ..color = AppColors.volt
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.28),
      2.5,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
