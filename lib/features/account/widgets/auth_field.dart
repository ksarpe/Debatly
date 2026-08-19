import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// The eyebrow label that sits above every field in the auth forms.
Widget authFieldLabel(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8, left: 2),
  child: Text(
    text,
    style: AppTypography.support().copyWith(color: context.colors.subtle),
  ),
);

/// Shared look for the auth text fields: filled, 12px radius, spark focus ring.
///
/// Lives here rather than inside a single screen so the sign-in sheet and the
/// "set a new password" sheet cannot drift apart visually.
InputDecoration authFieldDecoration(
  BuildContext context, {
  String? hint,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: AppTypography.support(
      fontSize: 13,
    ).copyWith(color: context.colors.subtle),
    filled: true,
    fillColor: context.colors.accent,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    enabledBorder: border(context.colors.hairline),
    focusedBorder: border(AppTheme.spark, 1.5),
    errorBorder: border(kAuthFieldError),
    focusedErrorBorder: border(kAuthFieldError, 1.5),
    disabledBorder: border(context.colors.hairline),
  );
}

/// Error-state border colour for the auth fields. A fixed red rather than a
/// theme token: `AppColors` carries no danger colour, and this one reads on
/// both the light and the dark field fill.
const Color kAuthFieldError = Color(0xFFE5484D);
