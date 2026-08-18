import 'package:flutter/material.dart';

import '../locale/l10n_extension.dart';
import '../theme/app_theme.dart';

/// Lists shorter than this don't render a search field — scanning a handful of
/// cards by eye is faster than typing, and the field would just push content
/// down. Shared by History and Favorites so both screens grow the search bar at
/// the same size.
const int kQuestionSearchMinItems = 6;

/// True when [text] matches the user's [query], ignoring case and Polish
/// diacritics — so "zolnierz" typed on a phone keyboard still finds "żołnierz".
/// An empty (or whitespace) query matches everything.
bool matchesQuestionQuery(String text, String query) {
  final q = _fold(query.trim());
  if (q.isEmpty) return true;
  return _fold(text).contains(q);
}

/// Lowercases and strips Polish diacritics for accent-insensitive matching.
String _fold(String s) {
  const diacritics = {
    'ą': 'a',
    'ć': 'c',
    'ę': 'e',
    'ł': 'l',
    'ń': 'n',
    'ó': 'o',
    'ś': 's',
    'ź': 'z',
    'ż': 'z',
  };
  var out = s.toLowerCase();
  diacritics.forEach((from, to) => out = out.replaceAll(from, to));
  return out;
}

/// The search field shown above long question lists (History, Favorites).
/// Styled like the auth form fields — filled accent surface, hairline border,
/// spark focus ring — with a leading magnifier and a clear button once the user
/// has typed something. Owns its [TextEditingController]; parents only receive
/// [onChanged] with the raw text.
class QuestionSearchField extends StatefulWidget {
  const QuestionSearchField({
    super.key,
    required this.onChanged,
    this.autofocus = false,
    this.onClose,
  });

  final ValueChanged<String> onChanged;

  /// Focus the field the moment it appears — for fields revealed by tapping a
  /// search icon (History), so the keyboard opens without a second tap.
  final bool autofocus;

  /// When set, the field is collapsible: the suffix X is always present and
  /// clears typed text first, then closes the field (via this callback) once
  /// the text is empty. When null (Favorites), the X only appears with text
  /// and only clears.
  final VoidCallback? onClose;

  @override
  State<QuestionSearchField> createState() => _QuestionSearchFieldState();
}

class _QuestionSearchFieldState extends State<QuestionSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      onChanged: (value) {
        widget.onChanged(value);
        // The clear button appears/disappears with the text.
        setState(() {});
      },
      textInputAction: TextInputAction.search,
      style: TextStyle(color: context.colors.ink, fontSize: 14.5),
      decoration: InputDecoration(
        hintText: context.l10n.searchQuestionsHint,
        hintStyle: TextStyle(color: context.colors.subtle),
        filled: true,
        fillColor: context.colors.accent,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: context.colors.subtle,
        ),
        suffixIcon: _controller.text.isEmpty
            ? (widget.onClose == null
                  ? null
                  : IconButton(
                      tooltip: context.l10n.searchCloseTooltip,
                      onPressed: widget.onClose,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: context.colors.subtle,
                      ),
                    ))
            : IconButton(
                tooltip: context.l10n.searchClearTooltip,
                onPressed: _clear,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: context.colors.subtle,
                ),
              ),
        enabledBorder: border(context.colors.hairline),
        focusedBorder: border(AppTheme.spark, 1.5),
      ),
    );
  }
}
