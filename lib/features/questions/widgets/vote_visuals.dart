import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/vote_result.dart';

/// The shared visual language of the binary TAK/NIE vote: the two slanted
/// buttons and the green/red community-split panels with the floating "VS".
///
/// Extracted so the real daily vote ([DailyVotePanel]) and the onboarding
/// "taste" vote render the SAME shapes — the onboarding card has to feel like
/// the real thing for the aha to land. The widgets here are purely presentational
/// (no providers, no network): the caller owns the state and the result, so the
/// same pixels back a live cast and a curated demo split alike.

/// Horizontal slant (in px) applied to the vote shapes so the two sides read as
/// a diagonal `/` split rather than two flat pills.
const double _kSkew = 16;

/// Shared height of the slanted buttons and result panels.
const double _kVoteHeight = 56;

/// [_kVoteHeight] grown for the system font, so the label + percentage inside a
/// result panel don't clip at a large accessibility text size. Capped: past
/// ~1.6× the panels would start crowding the question above them, and the text
/// stays legible without the box following it all the way up.
double _voteHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  return _kVoteHeight * math.min(1.6, math.max(1, scale));
}

/// The pre-vote state: the two slanted TAK / NIE buttons. [onVote] is handed the
/// chosen side ([VoteResult.yes] / [VoteResult.no]); [busy] dims + disables them
/// while a cast is in flight.
class VoteButtonsRow extends StatelessWidget {
  const VoteButtonsRow({required this.busy, required this.onVote, super.key});

  final bool busy;
  final void Function(int choice) onVote;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: busy ? 0.5 : 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Row(
          children: [
            Expanded(
              child: _VoteButton(
                label: context.l10n.voteYes,
                hint: AppTheme.yes,
                slant: _Slant.left,
                onTap: busy ? null : () => onVote(VoteResult.yes),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _VoteButton(
                label: context.l10n.voteNo,
                hint: AppTheme.no,
                slant: _Slant.right,
                onTap: busy ? null : () => onVote(VoteResult.no),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The post-vote state: the two slanted result panels (green TAK %, red NIE %)
/// with the "VS" badge over the seam. The caller's own side
/// ([VoteResult.myChoice]) is brightened and checked.
///
/// The raw vote total is deliberately NOT shown: early on the counts are small,
/// and a low "40 votes" reads as "nobody's here" and discourages voting. The
/// percentages alone carry the social signal and look livelier at any scale.
class VoteResultsRow extends StatelessWidget {
  const VoteResultsRow({
    required this.result,
    this.communityHidden = false,
    this.confirmMyVote = false,
    super.key,
  });

  final VoteResult result;

  /// When true, the community percentages are withheld: we only have an offline
  /// cached snapshot, so rather than show a possibly-stale split we confirm just
  /// the user's own side (a dash stands in for each %) and add a caption noting
  /// the numbers return online. See the daily panel's offline path.
  final bool communityHidden;

  /// When true, a "Twój głos: TAK/NIE" chip sits under the bars so the user can
  /// always tell which side they picked — the in-panel highlight alone was too
  /// easy to miss. Opt-in: the onboarding taste card leaves it off (it has its
  /// own majority/minority line), the real daily turns it on.
  final bool confirmMyVote;

  @override
  Widget build(BuildContext context) {
    // The two slanted panels plus a "VS" badge floating over the seam.
    final panels = SizedBox(
      height: _voteHeight(context),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: _ResultPanel(
                  label: context.l10n.voteYes,
                  pct: result.yesPct,
                  color: AppTheme.yes,
                  slant: _Slant.left,
                  mine: result.myChoice == VoteResult.yes,
                  showPct: !communityHidden,
                ),
              ),
              const SizedBox(width: 28),
              Expanded(
                child: _ResultPanel(
                  label: context.l10n.voteNo,
                  pct: result.noPct,
                  color: AppTheme.no,
                  slant: _Slant.right,
                  mine: result.myChoice == VoteResult.no,
                  showPct: !communityHidden,
                ),
              ),
            ],
          ),
          const _VsBadge(),
        ],
      ),
    );

    final showMine = confirmMyVote && result.hasVoted;
    if (!showMine && !communityHidden) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: panels,
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          panels,
          // A quiet "Twój głos" sits directly under the tile the user picked —
          // no chip or background, just a muted caption aligned to that side.
          if (showMine) ...[
            const SizedBox(height: 6),
            _MyVoteCaption(mineIsYes: result.myChoice == VoteResult.yes),
          ],
          if (communityHidden) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.offlineResultsHidden,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.subtle,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A muted "Twój głos" caption placed under whichever tile the user chose. It
/// mirrors the two-column layout of the result bars (same 28px seam gap) so the
/// label lines up under the picked side rather than floating in the centre.
class _MyVoteCaption extends StatelessWidget {
  const _MyVoteCaption({required this.mineIsYes});

  final bool mineIsYes;

  @override
  Widget build(BuildContext context) {
    final label = Center(
      child: Text(
        context.l10n.yourVote,
        style: TextStyle(
          color: context.colors.subtle,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
    return Row(
      children: [
        Expanded(child: mineIsYes ? label : const SizedBox.shrink()),
        const SizedBox(width: 28),
        Expanded(child: mineIsYes ? const SizedBox.shrink() : label),
      ],
    );
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.label,
    required this.hint,
    required this.slant,
    required this.onTap,
  });

  final String label;

  /// Side colour shown as a thin accent strip so the button previews its meaning.
  final Color hint;
  final _Slant slant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _SkewClipper(slant),
      child: Material(
        color: context.colors.accent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: _voteHeight(context),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: context.colors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                // Thin colour strip at the bottom hinting which side this is.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(height: 4, color: hint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.label,
    required this.pct,
    required this.color,
    required this.slant,
    required this.mine,
    this.showPct = true,
  });

  final String label;
  final int pct;
  final Color color;
  final _Slant slant;
  final bool mine;

  /// When false the percentage is replaced by a muted dash (offline: we hold no
  /// trustworthy community split, only the user's own [mine] side).
  final bool showPct;

  @override
  Widget build(BuildContext context) {
    // Push the two sides apart so the picked one clearly "wins": the chosen
    // panel gets a stronger fill and full-strength text, the other fades back.
    final pctColor = !showPct
        ? color.withValues(alpha: 0.55)
        : (mine ? color : color.withValues(alpha: 0.62));
    return ClipPath(
      clipper: _SkewClipper(slant),
      child: Container(
        height: _voteHeight(context),
        color: color.withValues(alpha: mine ? 0.42 : 0.12),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color.withValues(alpha: mine ? 1 : 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                if (mine) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.check_rounded, color: color, size: 14),
                ],
              ],
            ),
            Text(
              showPct ? '$pct%' : '–',
              style: TextStyle(
                color: pctColor,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The circular "VS" badge that sits over the diagonal seam between the panels.
class _VsBadge extends StatelessWidget {
  const _VsBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.background,
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.accent, width: 2),
      ),
      child: Text(
        'VS',
        style: TextStyle(
          color: context.colors.ink,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Which way a slanted shape leans. Both share the same `/` diagonal so the two
/// sides mirror around the central seam.
enum _Slant { left, right }

/// Clips a box into a parallelogram leaning along a `/` diagonal. Both sides
/// share the same lean so the panels stay parallel; [_Slant.left] is the TAK
/// side (seam on its right), [_Slant.right] is the NIE side (seam on its left).
class _SkewClipper extends CustomClipper<Path> {
  const _SkewClipper(this.slant);

  final _Slant slant;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    // Top edge is shifted right by _kSkew relative to the bottom edge → `/`.
    return Path()
      ..moveTo(_kSkew, 0)
      ..lineTo(w, 0)
      ..lineTo(w - _kSkew, h)
      ..lineTo(0, h)
      ..close();
  }

  @override
  bool shouldReclip(_SkewClipper oldClipper) => oldClipper.slant != slant;
}
