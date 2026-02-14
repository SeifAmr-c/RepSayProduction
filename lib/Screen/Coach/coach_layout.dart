import 'package:flutter/material.dart';
import '../../main.dart'; // AppColors
import '../settings_screen.dart'; // Reuse Settings
import 'coach_clients_screen.dart';

class CoachLayout extends StatefulWidget {
  const CoachLayout({super.key});
  @override
  State<CoachLayout> createState() => _CoachLayoutState();
}

class _CoachLayoutState extends State<CoachLayout> {
  int _idx = 0;
  final _screens = [const CoachClientsScreen(), const SettingsScreen()]; // Reusing SettingsScreen

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _screens[_idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.volt,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people_outline, color: Colors.grey), selectedIcon: Icon(Icons.people, color: Colors.black), label: "Clients"),
          NavigationDestination(icon: Icon(Icons.settings_outlined, color: Colors.grey), selectedIcon: Icon(Icons.settings, color: Colors.black), label: "Settings"),
        ],
      ),
    );
  }
}