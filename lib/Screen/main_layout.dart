import 'package:flutter/material.dart';
import 'package:flutter_test_1/Screen/home_screen.dart';    
import 'package:flutter_test_1/Screen/settings_screen.dart'; 
import '../main.dart'; // Import to access AppColors

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0; // Start at Home/Main

  final List<Widget> _screens = [
    const HomeScreen(),     // Index 0: The Microphone/Main Screen
    const SettingsScreen(), // Index 1: Settings
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background, // Match global background
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return const TextStyle(color: Colors.white, fontWeight: FontWeight.bold);
            }
            return const TextStyle(color: Colors.grey);
          }),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          backgroundColor: AppColors.background, // Matte Black
          indicatorColor: AppColors.volt, // Neon Green Pill
          surfaceTintColor: Colors.transparent, // Removes the slight white tint
          
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.mic_none_outlined, color: Colors.grey),
              selectedIcon: Icon(Icons.mic, color: Colors.black), // Black icon on Green Pill
              label: 'Record', 
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, color: Colors.grey),
              selectedIcon: Icon(Icons.settings, color: Colors.black), // Black icon on Green Pill
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}