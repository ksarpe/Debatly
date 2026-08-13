import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// The paywall hero: "PRO" as a brand sticker — the question text's signature
/// Anton stroke-and-fill treatment, but with a spark-gradient fill — slightly
/// tilted and glowing from behind. Pops in once when the sheet opens
/// (one-shot, so tests can settle).
class PaywallHero extends StatefulWidget {
  const PaywallHero({super.key});

  @override
  State<PaywallHero> createState() => _PaywallHeroState();
}

class _PaywallHeroState extends State<PaywallHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const double _fontSize = 56;

  /// Both text layers must share the exact same metrics to stay aligned; only
  /// the paint differs (stroke below, gradient fill above).
  static final TextStyle _stroke = QuestionTextStyles.strokeFor(
    _fontSize,
  ).copyWith(letterSpacing: 3);
  static final TextStyle _fill = QuestionTextStyles.fillFor(
    _fontSize,
  ).copyWith(letterSpacing: 3);

  static const Gradient _fillGradient = LinearGradient(
    colors: [Color(0xFFFFC168), AppTheme.spark, Color(0xFFD9510B)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.55, end: 1).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
        ),
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: _controller,
            curve: const Interval(0, 0.5),
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Soft spark wash radiating from behind the sticker.
              Container(
                width: 260,
                height: 104,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0x47EA6A12), Color(0x00EA6A12)],
                  ),
                ),
              ),
              Transform.rotate(
                angle: -0.055,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Text('PRO', style: _stroke),
                    ShaderMask(
                      shaderCallback: _fillGradient.createShader,
                      child: Text('PRO', style: _fill),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
