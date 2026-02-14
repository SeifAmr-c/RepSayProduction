import 'package:flutter/material.dart';
import '../main.dart'; // Import to access AppColors
import 'terms_of_service_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      "title": "Voice Tracking",
      "desc":
          "No more manual entry. Just speak, and our AI organizes your exercises, sets, and weights automatically.",
      "icon": Icons.mic_rounded,
    },
    {
      "title": "Smart Analytics",
      "desc":
          "Visualize your strength progress over time. See how much heavier you lift week after week.",
      "icon": Icons.insights_rounded,
    },
    {
      "title": "Pro Access",
      "desc":
          "Unlock unlimited recording and cloud backup. Keep your entire fitness history safe forever.",
      "icon": Icons.star_rounded,
    },
  ];

  void _finishOnboarding() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const TermsOfServiceScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background, // DARK BACKGROUND
      appBar: AppBar(backgroundColor: AppColors.background, elevation: 0),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (idx) => setState(() => _currentPage = idx),
              itemCount: _pages.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.all(30.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Animated Icon Card
                      Expanded(
                        flex: 3,
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.surface, // DARK CARD
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                              width: 1,
                            ), // SUBTLE BORDER
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: AppColors.volt.withOpacity(
                                    0.1,
                                  ), // GLOW EFFECT
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _pages[index]['icon'],
                                  size: 60,
                                  color: AppColors.volt,
                                ), // VOLT ICON
                              ),
                              const SizedBox(height: 30),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: Text(
                                  _pages[index]['title'],
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ), // WHITE TEXT
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      Text(
                        _pages[index]['desc'],
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                          height: 1.5,
                        ), // GREY TEXT
                        textAlign: TextAlign.center,
                      ),
                      const Spacer(),
                    ],
                  ),
                );
              },
            ),
          ),

          // Indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _pages.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 6,
                width: _currentPage == index ? 24 : 6,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? AppColors.volt
                      : Colors
                            .grey
                            .shade800, // VOLT ACTIVE / DARK GREY INACTIVE
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Main Button
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  if (_currentPage == 2) {
                    _finishOnboarding();
                  } else {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.volt, // VOLT BACKGROUND
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _currentPage == 2 ? "GET STARTED" : "NEXT",
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ), // BLACK TEXT
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
