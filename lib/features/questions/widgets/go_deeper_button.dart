import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// The glowing "wejdz glebiej" pill. Tapping it opens the "Smaczki" panel from
/// the bottom.
class GoDeeperButton extends StatelessWidget {
  const GoDeeperButton({super.key, required this.onTap});

  final VoidCallback onTap;

  static const _radius = BorderRadius.all(Radius.circular(18));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.goDeeper,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: DecoratedBox(
            // Tie the button to the orange "spark" it's built around — a tinted
            // wash, a soft halo and an orange outline — so it reads as the lit
            // "go deeper" affordance in BOTH themes. The old fixed navy outline
            // looked heavy and out of place on the light off-white canvas.
            decoration: const BoxDecoration(
              borderRadius: _radius,
              color: Color(0x24EA6A12),
              border: Border.fromBorderSide(
                BorderSide(color: Color(0xB3EA6A12)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x40EA6A12),
                  blurRadius: 16,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              child: _Label(),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label();

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.goDeeper,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: AppTheme.spark,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}
