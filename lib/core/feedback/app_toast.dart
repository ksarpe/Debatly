import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The visual flavour of a toast — drives its accent colour and default icon.
enum ToastType { success, error, info }

/// An optional action affordance shown at the trailing edge of a toast (e.g.
/// "Open settings" on a permission warning).
typedef ToastAction = ({String label, VoidCallback onPressed});

/// A lightweight, app-styled toast ("sonner") that slides in from the top,
/// stacks when several arrive, auto-dismisses, and can be tapped or swiped away.
///
/// It replaces the default Material [SnackBar] everywhere so every transient
/// message — "added to favourites", a failed vote, a restored purchase — reads
/// as the same polished card in either theme rather than the stock grey bar.
///
/// Toasts live in the *root* overlay (above the navigator), so one shown just
/// before a screen pops still rides along onto the screen underneath.
///
/// Usage (anywhere with a [BuildContext] under the app):
/// ```dart
/// AppToast.success(context, context.l10n.favoriteAdded);
/// AppToast.error(context, context.l10n.voteFailed);
/// ```
///
/// For a message shown *after* an `await` that may unmount the caller, grab the
/// overlay up front with [capture] and fire it with [showOn] — mirrors how the
/// old code captured a `ScaffoldMessenger` before the gap.
class AppToast {
  AppToast._();

  /// Newer toasts past this count drop the oldest, so the stack never grows
  /// into a wall.
  static const int _maxVisible = 3;
  static const Duration _defaultHold = Duration(seconds: 3);
  static const Duration _errorHold = Duration(seconds: 5);

  static final _ToastController _controller = _ToastController();
  static OverlayEntry? _host;
  static OverlayState? _hostOverlay;
  static int _seq = 0;

  /// A success confirmation (green). Pass [icon] to override the default tick —
  /// e.g. a star for "added to favourites".
  ///
  /// Returns an id accepted by [dismiss], so an optimistic confirmation can be
  /// retracted if the action it announced later fails.
  static int success(BuildContext context, String message, {IconData? icon}) =>
      show(context, message, type: ToastType.success, icon: icon);

  /// An error / failure (red).
  static int error(BuildContext context, String message, {IconData? icon}) =>
      show(context, message, type: ToastType.error, icon: icon);

  /// A neutral, informational note (orange).
  static int info(BuildContext context, String message, {IconData? icon}) =>
      show(context, message, type: ToastType.info, icon: icon);

  /// Resolves the root overlay from [context] and shows the toast. A no-op if
  /// the context has no overlay (e.g. already unmounted) — capture the overlay
  /// before an `await` with [capture] + [showOn] for those cases.
  ///
  /// Returns the shown toast's id (for [dismiss]), or -1 if nothing was shown.
  static int show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    IconData? icon,
    Duration? duration,
    ToastAction? action,
  }) => showOn(
    Overlay.maybeOf(context, rootOverlay: true),
    message,
    type: type,
    icon: icon,
    duration: duration,
    action: action,
  );

  /// The root overlay behind [context], captured so a toast can still be shown
  /// after an async gap that unmounts the originating widget (mirrors capturing
  /// a `ScaffoldMessenger` before an `await`).
  static OverlayState? capture(BuildContext context) =>
      Overlay.maybeOf(context, rootOverlay: true);

  /// Shows a toast on a previously [capture]d overlay. No-op if [overlay] is
  /// null.
  ///
  /// Returns the shown toast's id (for [dismiss]), or -1 if nothing was shown.
  static int showOn(
    OverlayState? overlay,
    String message, {
    ToastType type = ToastType.info,
    IconData? icon,
    Duration? duration,
    ToastAction? action,
  }) {
    if (overlay == null) return -1;
    _ensureHost(overlay);
    while (_controller.items.length >= _maxVisible) {
      _controller.removeAt(0);
    }
    final id = _seq++;
    _controller.add(
      _ToastData(
        id: id,
        message: message,
        type: type,
        icon: icon,
        action: action,
        duration:
            duration ?? (type == ToastType.error ? _errorHold : _defaultHold),
      ),
    );
    return id;
  }

  /// Removes a still-visible toast by the id [show]/[showOn] returned — for
  /// retracting an optimistic confirmation whose action turned out to fail.
  /// No-op if the toast already dismissed itself.
  static void dismiss(int id) => _controller.removeId(id);

  /// Ensures a single host overlay entry is mounted in [overlay]. Re-creates it
  /// when the overlay changes (e.g. a fresh widget test), clearing any stale
  /// toasts left from the previous tree.
  static void _ensureHost(OverlayState overlay) {
    if (_host != null && identical(_hostOverlay, overlay)) return;
    _hostOverlay = overlay;
    _controller.clear();
    final entry = OverlayEntry(
      builder: (_) => _ToastHost(controller: _controller),
    );
    _host = entry;
    overlay.insert(entry);
  }
}

/// One queued toast's data.
class _ToastData {
  _ToastData({
    required this.id,
    required this.message,
    required this.type,
    required this.icon,
    required this.action,
    required this.duration,
  });

  final int id;
  final String message;
  final ToastType type;
  final IconData? icon;
  final ToastAction? action;
  final Duration duration;
}

/// The ordered list of live toasts, oldest first. The host listens and rebuilds.
class _ToastController extends ChangeNotifier {
  final List<_ToastData> _items = [];

  List<_ToastData> get items => _items;

  void add(_ToastData data) {
    _items.add(data);
    notifyListeners();
  }

  void removeAt(int index) {
    _items.removeAt(index);
    notifyListeners();
  }

  void removeId(int id) {
    final before = _items.length;
    _items.removeWhere((e) => e.id == id);
    if (_items.length != before) notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }
}

/// The persistent overlay entry: a top-anchored column of the live toasts.
class _ToastHost extends StatefulWidget {
  const _ToastHost({required this.controller});

  final _ToastController controller;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.controller.items;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in items)
                _ToastCard(
                  key: ValueKey(item.id),
                  data: item,
                  onDismissed: () => widget.controller.removeId(item.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single toast card: owns its enter/exit animation, its auto-dismiss timer,
/// and tap / swipe-to-dismiss. It animates *itself* out and only then asks the
/// controller to drop it, so removals stay smooth.
class _ToastCard extends StatefulWidget {
  const _ToastCard({super.key, required this.data, required this.onDismissed});

  final _ToastData data;
  final VoidCallback onDismissed;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _anim.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _leaving) {
        widget.onDismissed();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_reduceMotion) {
        _anim.value = 1;
      } else {
        _anim.forward();
      }
      _timer = Timer(widget.data.duration, _dismiss);
    });
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _dismiss() {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    if (_reduceMotion || !mounted) {
      widget.onDismissed();
    } else {
      _anim.reverse();
    }
  }

  void _runAction() {
    widget.data.action?.onPressed();
    _dismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, child) {
              final t = Curves.easeOutCubic.transform(_anim.value);
              return Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * -16),
                  child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
                ),
              );
            },
            child: Dismissible(
              key: ValueKey('toast-swipe-${widget.data.id}'),
              direction: DismissDirection.horizontal,
              onDismissed: (_) {
                _leaving = true;
                _timer?.cancel();
                widget.onDismissed();
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: _ToastSurface(
                  data: widget.data,
                  onAction: widget.data.action == null ? null : _runAction,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card chrome: a floating surface with a tinted icon badge, the message,
/// and an optional trailing action.
class _ToastSurface extends StatelessWidget {
  const _ToastSurface({required this.data, required this.onAction});

  final _ToastData data;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = _accentFor(data.type);
    final icon = data.icon ?? _iconFor(data.type);

    return Material(
      color: colors.cardSurface,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.hairline),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                data.message,
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 14,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (data.action case final action?) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  action.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _accentFor(ToastType type) => switch (type) {
    ToastType.success => AppTheme.yes,
    ToastType.error => AppTheme.no,
    ToastType.info => AppTheme.spark,
  };

  IconData _iconFor(ToastType type) => switch (type) {
    ToastType.success => Icons.check_rounded,
    ToastType.error => Icons.error_outline_rounded,
    ToastType.info => Icons.info_outline_rounded,
  };
}
