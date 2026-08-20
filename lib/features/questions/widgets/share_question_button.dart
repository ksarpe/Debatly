import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/monitoring/monitoring.dart';
import '../../../core/share/widget_to_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../services/analytics.dart';
import 'share_question_card.dart';

/// A visible "share" pill shown beneath the question (under the vote panel on
/// the daily). Tapping it renders the question as a branded [QuestionShareCard]
/// image and opens the platform share sheet (WhatsApp, Messenger, SMS, email,
/// Stories…) with that image plus a short Debatly signoff as the accompanying
/// text.
///
/// The image makes the share feel intentional (and recognisably "Debatly") rather
/// than a bare line of text; the same poster render doubles as store-screenshot
/// art. If rendering the card fails for any reason we fall back to sharing the
/// question as plain text, so the button never dead-ends.
///
/// Styled as a quiet, borderless pill so it reads as an intentional
/// secondary action without competing with the glowing "go deeper" CTA below.
///
/// Only the question's own text is shared — never a locked teaser — so the
/// caller renders this strictly for readable questions.
class ShareQuestionButton extends StatefulWidget {
  const ShareQuestionButton({
    super.key,
    required this.questionText,
    this.barStyle = false,
  });

  /// The full text of the question currently on screen.
  final String questionText;

  /// When true, wears the bottom action bar's rounded-rectangle chrome
  /// ([AppTheme.ctaRadius], matching the "go deeper" CTA beside it) instead of
  /// the standalone stadium pill, and stretches to fill the width it is given.
  final bool barStyle;

  @override
  State<ShareQuestionButton> createState() => _ShareQuestionButtonState();
}

class _ShareQuestionButtonState extends State<ShareQuestionButton> {
  /// True while the card is being rendered / the share sheet is being prepared,
  /// so a second tap can't fire a parallel render.
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    final text = widget.questionText.trim();
    if (text.isEmpty) return;

    // Capture everything that needs a live BuildContext BEFORE the first await,
    // so we never touch a possibly-unmounted context afterwards.
    final l10n = context.l10n;
    final ui.FlutterView view = View.of(context);
    // iPad presents the share sheet as a popover anchored to the tapped widget;
    // without an origin rect it throws there. Derive it from this button's box
    // so the sheet points at the pill (harmless/ignored on phones).
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    setState(() => _busy = true);
    Analytics.log('share_card_opened', {'type': 'question'});
    try {
      final params = await _buildShareParams(
        text: text,
        l10n: l10n,
        view: view,
        origin: origin,
      );
      await SharePlus.instance.share(params);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Builds the share payload: the branded image card plus the signoff text,
  /// degrading to text-only if the card can't be rendered/encoded.
  Future<ShareParams> _buildShareParams({
    required String text,
    required AppLocalizations l10n,
    required ui.FlutterView view,
    required Rect? origin,
  }) async {
    final message = l10n.shareMessage(text);
    try {
      // Decode the brand logo up front: the card is captured in one synchronous
      // off-screen pass, so an async Image.asset would paint blank. Null just
      // falls back to the text wordmark.
      final logo = await QuestionShareCard.loadLogo();
      final png = await renderWidgetToPng(
        child: QuestionShareCard(
          questionText: text,
          tagline: l10n.shareCardHook,
          logo: logo,
        ),
        logicalSize: const Size(360, 640),
        view: view,
      );
      if (png != null) {
        return ShareParams(
          text: message,
          subject: l10n.shareSubject,
          sharePositionOrigin: origin,
          files: [
            XFile.fromData(
              png,
              mimeType: 'image/png',
              name: 'spark-question.png',
            ),
          ],
        );
      }
    } catch (e, st) {
      // Falls back to a text-only share, so the user still shares — but a
      // card that stopped rendering is invisible in release otherwise.
      await Monitoring.captureException(
        e,
        stackTrace: st,
        feature: 'share',
        extra: {'card': 'question'},
      );
    }
    // Fallback: text-only share (the original behaviour).
    return ShareParams(
      text: message,
      subject: l10n.shareSubject,
      sharePositionOrigin: origin,
    );
  }

  static const _radius = BorderRadius.all(Radius.circular(30));

  @override
  Widget build(BuildContext context) {
    // In the bottom action bar the pill drops the stadium corners for the
    // shared CTA radius so all three controls in the row read as one family.
    final radius = widget.barStyle ? AppTheme.ctaRadius : _radius;
    return Semantics(
      button: true,
      label: context.l10n.shareTooltip,
      child: Tooltip(
        message: context.l10n.shareTooltip,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: radius),
          child: InkWell(
            borderRadius: radius,
            onTap: _busy ? null : _share,
            // The pill is sized to the touch target, not to its icon: at 42 it
            // was under both platforms' minimum and a thumb regularly missed it.
            child: SizedBox(
              width: kMinTouchTarget,
              height: kMinTouchTarget,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  // While the card renders, the spinner takes the icon's place
                  // so the pill keeps its shape and the tap clearly "did
                  // something".
                  child: _busy
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.subtle,
                        )
                      : Icon(
                          Icons.ios_share,
                          size: 20,
                          color: context.colors.subtle,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
