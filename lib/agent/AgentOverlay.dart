import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Pages/AgentPage.dart';
import '../utils/Responsive.dart';
import '../main.dart' show guideNavigatorKey;
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/UnseenAggregates.dart';
import '../utils/UnseenDot.dart';
import '../widgets/AgentFab.dart';
import 'AgentController.dart';

/// The route name of the assistant's page, so the button can step aside there.
const String kAgentRouteName = '/assistant';

/// Tells the floating button when the assistant's own page is on top, where the button would only
/// duplicate it and could cover its send button.
///
/// Attach [instance] to the app's `navigatorObservers`. It follows the route stack and reads nothing
/// but each route's name, so it does not touch any screen's own navigation.
class AgentRouteVisibility extends NavigatorObserver {
  AgentRouteVisibility();

  static final AgentRouteVisibility instance = AgentRouteVisibility();

  /// True while the route on top is the assistant's page.
  final ValueNotifier<bool> onAgent = ValueNotifier<bool>(false);

  Route<dynamic>? _top;

  void _setTop(Route<dynamic>? route) {
    _top = route;
    final isAgent = route?.settings.name == kAgentRouteName;
    // Navigator callbacks can arrive while the tree is building; deliver the change afterwards so
    // listeners never call setState mid-build.
    scheduleMicrotask(() => onAgent.value = isAgent);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _setTop(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _setTop(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route == _top) _setTop(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == _top) _setTop(newRoute);
  }
}

/// Whether the MAIN SHELL (Home and the other main tabs) is on screen. The assistant's button shows only then: never on the splash, the sign-in,
/// a loading screen, "update required" or anything else before Home. The shell sets it when it appears and clears it when it goes.
///
/// THE SHELL IS COUNTED, NOT FLIPPED: a shell that is replaced by another one in the SAME frame (a sign-in again, a profile switch, a restart of the
/// app's flow) used to clear the flag after the new one had set it, and the button stayed hidden for good. Every shell [attach]es itself and
/// [detach]es when it goes; the button shows while at least one is attached, whatever order they come in.
class AgentShell {
  AgentShell._();
  static final ValueNotifier<bool> ready = ValueNotifier<bool>(false);
  static final Set<Object> _holders = <Object>{};

  static void attach(Object shell) {
    _holders.add(shell);
    _sync();
  }

  static void detach(Object shell) {
    _holders.remove(shell);
    _sync();
  }

  // read at the END of the turn, so two changes in one frame cannot leave an old answer behind
  static void _sync() => scheduleMicrotask(() => ready.value = _holders.isNotEmpty);

  /// Tests start with no shell.
  @visibleForTesting
  static void reset() {
    _holders.clear();
    ready.value = false;
  }
}

/// The one conversation of this app session. It survives leaving the page and coming back; "New
/// chat" clears it.
class AgentSession {
  AgentSession._();
  static AgentController controller = AgentController();

  /// On a computer the assistant opens as a panel beside the page (the shell listens); on a phone it is the full page the button opens.
  static final ValueNotifier<bool> panelOpen = ValueNotifier<bool>(false);

  /// Tests start from a clean conversation.
  static void useForTests(AgentController? c) => controller = c ?? AgentController();
}

/// The assistant's persistent entry point: a floating button on EVERY screen of the signed-in app.
///
/// Root-level, not per-screen: it wraps the `child` that `MaterialApp.builder` passes — the whole
/// Navigator, whichever route is on top — so it sits above every screen, survives navigation and
/// needs no per-screen wiring.
///
/// It is hidden (kept mounted, so its position survives) while the assistant's own page is on top,
/// and absent until an admin is signed in, so it never appears over the splash or sign-in.
///
/// Position: draggable, saved as a FRACTION of the screen (so it survives rotation and another phone),
/// clear of the floating navigation by default, never off-screen. A colour of its own — the assistant's
/// sky blue, drawn as a glossy 3D button with a light shine that sweeps across it every few seconds.
class AgentOverlay extends StatelessWidget {
  const AgentOverlay({super.key, required this.child, this.signedIn, this.onOpen, this.shellReady});

  final Widget child;

  /// Tests hand in their own signed-in signal and what a tap does; the app never sets these.
  @visibleForTesting
  final Listenable? signedIn;
  @visibleForTesting
  final VoidCallback? onOpen;

  /// Tests hand in their own "the shell is on screen" signal; a test that hands in [signedIn] only (a bare overlay with no shell) counts as ready.
  @visibleForTesting
  final ValueListenable<bool>? shellReady;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ListenableBuilder(
          listenable: signedIn ?? AdminProfileProvider.instance,
          builder: (context, _) {
            if (AdminProfileProvider.current == null) return const SizedBox.shrink();
            // On a computer the assistant lives in the side navigation (a panel); the floating button is for phones and tablets.
            if (context.isDesktop) return const SizedBox.shrink();
            return ValueListenableBuilder<bool>(
              valueListenable: AgentRouteVisibility.instance.onAgent,
              builder: (context, onAgent, _) => ValueListenableBuilder<bool>(
                valueListenable: shellReady ?? (signedIn != null ? _alwaysReady : AgentShell.ready),
                // it fades in smoothly when Home appears; before that it is not even in the way of a tap
                builder: (context, ready, _) => _DraggableAgentButton(hidden: onAgent, shown: ready, onOpen: onOpen),
              ),
            );
          },
        ),
      ],
    );
  }
}

final ValueNotifier<bool> _alwaysReady = ValueNotifier<bool>(true);

const String _kPrefsDx = 'agent_button_dx_fraction';
const String _kPrefsDy = 'agent_button_dy_fraction';

/// Diameter of the button; also what keeps it fully on-screen when a position is clamped.
const double kAgentButtonSize = 56;
const double _kSideInset = 14;

class _DraggableAgentButton extends StatefulWidget {
  const _DraggableAgentButton({required this.hidden, required this.shown, this.onOpen});

  final bool hidden;

  /// The main shell is on screen: fade in (false: invisible and untouchable).
  final bool shown;
  final VoidCallback? onOpen;

  @override
  State<_DraggableAgentButton> createState() => _DraggableAgentButtonState();
}

class _DraggableAgentButtonState extends State<_DraggableAgentButton> {
  Offset? _position; // top-left, logical pixels
  Offset? _pendingFraction;
  // the button is there from the first frame (at its default spot); a saved spot only moves it when it arrives
  bool _loaded = true;
  bool _dragging = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    double? dx;
    double? dy;
    try {
      final prefs = await SharedPreferences.getInstance();
      dx = prefs.getDouble(_kPrefsDx);
      dy = prefs.getDouble(_kPrefsDy);
    } catch (_) {/* a saved spot is a convenience */}
    if (!mounted) return;
    setState(() {
      // a spot that is not a sensible fraction of the screen is ignored (never a reason for the button to be lost)
      final ok = dx != null && dy != null && dx.isFinite && dy.isFinite && dx >= 0 && dx <= 1 && dy >= 0 && dy <= 1;
      _pendingFraction = ok ? Offset(dx, dy) : null;
      _loaded = true;
    });
  }

  Future<void> _persist(Offset fraction) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kPrefsDx, fraction.dx);
      await prefs.setDouble(_kPrefsDy, fraction.dy);
    } catch (_) {}
  }

  double _clamp(double v, double lo, double hi) => v.clamp(lo, hi < lo ? lo : hi).toDouble();

  Offset _resolve(Size screen, EdgeInsets safe, double bottomInset) {
    final maxX = screen.width - kAgentButtonSize - _kSideInset;
    final maxY = screen.height - kAgentButtonSize - bottomInset;
    final minY = safe.top;
    final raw = _position ??
        (_pendingFraction != null
            ? Offset(_pendingFraction!.dx * screen.width, _pendingFraction!.dy * screen.height)
            : Offset(maxX, maxY));
    return Offset(_clamp(raw.dx, _kSideInset, maxX), _clamp(raw.dy, minY, maxY));
  }

  /// Orange dot while the plan has changed since the guide last opened it. Built once (a live listener), when the profile is known.
  Stream<bool>? _planUnseenStream;
  Stream<bool> get _planUnseen => _planUnseenStream ??= UnseenAggregates.planUnseen(AdminProfileProvider.current?.id ?? '');

  void _open() {
    final custom = widget.onOpen;
    if (custom != null) return custom();
    guideNavigatorKey.currentState?.push(MaterialPageRoute(
      settings: const RouteSettings(name: kAgentRouteName),
      builder: (_) => const AgentPage(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final screen = media.size;
    // clear of the floating navigation at the bottom, like every other floating thing in the app
    // (and above the keyboard when it is open, so it is never hidden behind it)
    final bottomInset = GuideSpace.navClearanceOf(context) + GuideSpace.md + media.viewInsets.bottom;
    final pos = _resolve(screen, media.padding, bottomInset);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Offstage(
        offstage: widget.hidden,
        child: TickerMode(
          enabled: !widget.hidden,
          child: IgnorePointer(
            ignoring: !widget.shown,
            child: AnimatedOpacity(
              key: const ValueKey('agent-button-fade'),
              opacity: widget.shown ? 1 : 0,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOut,
              child: GestureDetector(
            key: const ValueKey('agent-button'),
            onPanStart: (_) => setState(() => _dragging = true),
            onPanUpdate: (d) => setState(() {
              _position = Offset(
                _clamp(pos.dx + d.delta.dx, _kSideInset, screen.width - kAgentButtonSize - _kSideInset),
                _clamp(pos.dy + d.delta.dy, media.padding.top, screen.height - kAgentButtonSize - bottomInset),
              );
            }),
            onPanEnd: (_) {
              setState(() => _dragging = false);
              final p = _position ?? pos;
              _persist(Offset(p.dx / screen.width, p.dy / screen.height));
            },
            onTap: _open,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: Semantics(
              button: true,
              label: 'AI assistant',
              child: AnimatedScale(
                scale: _dragging ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 120),
                child: StreamBuilder<bool>(
                  stream: _planUnseen,
                  builder: (context, snap) => UnseenBadge(
                    key: const ValueKey('agent-fab-dot'),
                    show: snap.data ?? false,
                    offset: const Offset(2, 2),
                    dotSize: 12,
                    child: AgentFab(key: const ValueKey('agent-fab'), size: kAgentButtonSize, pressed: _pressed && !_dragging),
                  ),
                ),
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
