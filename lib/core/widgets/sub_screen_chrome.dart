import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// Soft radial glow bleeding down from the top of a sub-screen. Purely
/// decorative; shared so every sub-screen (Favorites, Privacy, question
/// history …) opens with the same warm header.
class TopGlow extends StatelessWidget {
  const TopGlow({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: -80,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Container(
          height: 360,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 0.85,
              colors: [
                AppTheme.spark.withValues(alpha: 0.20),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The standard sub-screen header: a left-aligned title in the brand accent with
/// a round close button floating in the top-right corner. Shared by the settings
/// sub-screens and the question history so they all read the same way — a title
/// and an X to close, never a drag-up sheet.
class SubScreenHeader extends StatelessWidget {
  const SubScreenHeader({
    super.key,
    required this.title,
    required this.onClose,
  });

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topLeft,
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 44, top: 4),
          child: Text(
            title.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.title().copyWith(color: AppTheme.spark),
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: SubScreenCloseButton(onTap: onClose),
        ),
      ],
    );
  }
}

/// The round "X" used in the top-right of every sub-screen header. Named to
/// avoid clashing with Flutter's own [CloseButton].
class SubScreenCloseButton extends StatelessWidget {
  const SubScreenCloseButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.cardSurface,
      shape: CircleBorder(side: BorderSide(color: context.colors.hairline)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(Icons.close, size: 20, color: context.colors.subtle),
        ),
      ),
    );
  }
}
