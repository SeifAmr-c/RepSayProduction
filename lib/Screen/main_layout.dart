import 'package:flutter/material.dart';
import 'package:flutter_test_1/Screen/home_screen.dart';
import 'package:flutter_test_1/Screen/calorie_calculator_screen.dart';
import 'package:flutter_test_1/Screen/exercise_analysis_screen.dart';
import 'package:flutter_test_1/Screen/settings_screen.dart';
import '../main.dart'; // Import to access AppColors

class MainLayout extends StatefulWidget {
  MainLayout() : super(key: mainLayoutKey);

  static final GlobalKey<_MainLayoutState> mainLayoutKey =
      GlobalKey<_MainLayoutState>();

  static void navigateToTab(int index) {
    mainLayoutKey.currentState?._switchTab(index);
  }

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0; // Start at Home/Main

  void _switchTab(int index) {
    setState(() => _currentIndex = index);
  }

  final List<Widget> _screens = [
    const HomeScreen(), // Index 0: Record
    const CalorieCalculatorScreen(), // Index 1: Calories
    const ExerciseAnalysisScreen(), // Index 2: Analysis
    const SettingsScreen(), // Index 3: Settings
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
              return const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              );
            }
            return const TextStyle(color: Colors.grey, fontSize: 11);
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
              selectedIcon: Icon(
                Icons.mic,
                color: Colors.black,
              ), // Black icon on Green Pill
              label: 'Record',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.local_fire_department_outlined,
                color: Colors.grey,
              ),
              selectedIcon: Icon(
                Icons.local_fire_department,
                color: Colors.black,
              ),
              label: 'Calories',
            ),
            NavigationDestination(
              icon: Icon(Icons.analytics_outlined, color: Colors.grey),
              selectedIcon: Icon(Icons.analytics, color: Colors.black),
              label: 'Analysis',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, color: Colors.grey),
              selectedIcon: Icon(
                Icons.settings,
                color: Colors.black,
              ), // Black icon on Green Pill
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
