import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// The paywall hero: "PRO" as a brand sticker — the question text's signature
/// Anton stroke-and-fill treatment, but with a spark-gradient fill — slightly
/// tilted, glowing from behind, with a counter-tilted bolt badge pinned to its
/// corner. Pops in once when the sheet opens (one-shot, so tests can settle).
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
    colors: [Color(0xFFFFC168), AppTheme.spark, Color(0xFFEA580C)],
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
                    colors: [Color(0x47F97316), Color(0x00F97316)],
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
                    Positioned(
                      top: -8,
                      right: -26,
                      child: Transform.rotate(
                        angle: 0.30,
                        child: const _BoltSticker(),
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      left: -26,
                      child: Icon(
                        Icons.auto_awesome,
                        size: 18,
                        color: AppTheme.spark.withValues(alpha: 0.75),
                      ),
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

/// The little round bolt badge riding the corner of the "PRO" sticker. The
/// background-coloured ring separates it from the letters underneath.
class _BoltSticker extends StatelessWidget {
  const _BoltSticker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.spark, Color(0xFFEA580C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.background, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x55F97316), blurRadius: 14, spreadRadius: 1),
        ],
      ),
      child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
    );
  }
}
