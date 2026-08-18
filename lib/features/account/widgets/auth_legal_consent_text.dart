import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// Fine-print "by continuing you agree to … Terms … Privacy" line with two
/// tappable links. A `StatefulWidget` because the [TapGestureRecognizer]s it
/// attaches to the link spans must be disposed. The sentence is one localized
/// template with `{terms}`/`{privacy}` placeholders (so each language keeps
/// natural grammar); we substitute private-use sentinel chars, then split on
/// them to slot in the tappable link spans.
class AuthLegalConsentText extends StatefulWidget {
  const AuthLegalConsentText({
    super.key,
    required this.onTapTerms,
    required this.onTapPrivacy,
  });

  final VoidCallback onTapTerms;
  final VoidCallback onTapPrivacy;

  @override
  State<AuthLegalConsentText> createState() => _AuthLegalConsentTextState();
}

class _AuthLegalConsentTextState extends State<AuthLegalConsentText> {
  static const _termsMark = '%%TERMS%%';
  static const _privacyMark = '%%PRIVACY%%';

  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = () => widget.onTapTerms();
    _privacyTap = TapGestureRecognizer()..onTap = () => widget.onTapPrivacy();
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final template = l10n.authLegalConsent(_termsMark, _privacyMark);
    const linkStyle = TextStyle(
      color: AppTheme.spark,
      fontWeight: FontWeight.w700,
    );

    final spans = <InlineSpan>[];
    var start = 0;
    final pattern = RegExp(
      '${RegExp.escape(_termsMark)}|${RegExp.escape(_privacyMark)}',
    );
    for (final match in pattern.allMatches(template)) {
      if (match.start > start) {
        spans.add(TextSpan(text: template.substring(start, match.start)));
      }
      final isTerms = match.group(0) == _termsMark;
      spans.add(
        TextSpan(
          text: isTerms ? l10n.authLegalTermsLink : l10n.authLegalPrivacyLink,
          style: linkStyle,
          recognizer: isTerms ? _termsTap : _privacyTap,
        ),
      );
      start = match.end;
    }
    if (start < template.length) {
      spans.add(TextSpan(text: template.substring(start)));
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
      style: AppTypography.support(
        height: 1.4,
      ).copyWith(color: context.colors.subtle),
    );
  }
}
