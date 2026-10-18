import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart';

/// The branded screen the app opens on.
///
/// `main()` has already awaited `SupabaseService.initialize()` before
/// the first frame, so by the time this paints the storefront is ready
/// to go. The screen is a minimum brand moment ([minimumDuration]),
/// not a spinner pretending to work -- the dots are honest decoration
/// for the short wait, and the dashboard replaces this screen the
/// moment the timer fires.
///
/// Android shows the blush launch frame (see
/// `android/.../launch_background.xml`) before Flutter's first frame,
/// so the full sequence is: blush system window -> this splash ->
/// storefront, with no white flash anywhere.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// Minimum time the brand stays on screen. Long enough to read the
  /// wordmark, short enough to never feel like a wait.
  static const Duration minimumDuration = Duration(milliseconds: 850);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Gentle breathing on the logo card.
  late final AnimationController _logoPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  // The three dots bounce in a staggered loop off this one clock.
  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  Timer? _gate;

  @override
  void initState() {
    super.initState();

    _gate = Timer(SplashScreen.minimumDuration, _enterStorefront);
  }

  void _enterStorefront() {
    // The timer can outlive a very fast navigation (for example the
    // password-reset deep link landing straight on the dashboard), in
    // which case there is nothing left to replace.
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const DashboardScreen()),
    );
  }

  @override
  void dispose() {
    _gate?.cancel();
    _logoPulse.dispose();
    _dots.dispose();
    super.dispose();
  }

  /// A translucent "dew drop" bubble for the background. Positioned
  /// entirely by the [Positioned] parent, hence no offset here.
  Widget _drop(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The splash background is the rose gradient, so it wants white
    // status icons even though main() defaults to dark for the cream
    // pages that follow.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),

      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,

          // Same diagonal the app header uses, so the splash reads as
          // the top of the storefront it is about to reveal.
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFC25E7A), Color(0xFFF0A6B8)],
            ),
          ),

          child: Stack(
            children: [
              // Scattered dew drops. Fixed positions, never animated --
              // all the motion is on the logo and the dots, and keeping
              // the background still is what stops the screen feeling
              // busy.
              Positioned(top: -60, right: -46, child: _drop(180, 0.10)),
              Positioned(top: 130, left: -50, child: _drop(120, 0.07)),
              Positioned(bottom: 170, right: -30, child: _drop(100, 0.10)),
              Positioned(bottom: -50, left: 30, child: _drop(170, 0.06)),
              Positioned(top: 70, right: 90, child: _drop(22, 0.20)),
              Positioned(bottom: 90, left: 70, child: _drop(14, 0.18)),

              SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),

                    child: Column(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        // ---- Logo card ----
                        ScaleTransition(
                          scale: Tween<double>(begin: 1.0, end: 1.05).animate(
                            CurvedAnimation(
                              parent: _logoPulse,
                              curve: Curves.easeInOut,
                            ),
                          ),

                          child: Container(
                            width: 112,
                            height: 112,
                            padding: const EdgeInsets.all(9),

                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 30,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),

                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                'assets/images/touchskin_logo.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 26),

                        // ---- Wordmark ----
                        const Text(
                          'TouchSkin',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),

                        const SizedBox(height: 8),

                        const Text(
                          'SKINCARE, CURATED FOR YOU',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.6,
                          ),
                        ),

                        const SizedBox(height: 48),

                        // ---- Staggered dot loader ----
                        AnimatedBuilder(
                          animation: _dots,

                          builder: (context, child) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,

                              children: List.generate(3, (index) {
                                // Each dot runs the same 0..1 sine wave,
                                // offset by a fifth of the loop so the
                                // bounce travels left to right.
                                final phase =
                                    (_dots.value - index * 0.18 + 1.0) % 1.0;

                                final wave = math.sin(phase * math.pi);

                                return Padding(
                                  padding: EdgeInsets.only(
                                    right: index == 2 ? 0 : 10,
                                  ),

                                  child: Opacity(
                                    opacity: 0.35 + 0.65 * wave,

                                    child: Transform.scale(
                                      scale: 0.5 + 0.5 * wave,
                                      child: child,
                                    ),
                                  ),
                                );
                              }),
                            );
                          },

                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        const Text(
                          'Preparing your shelf…',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12.5,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
