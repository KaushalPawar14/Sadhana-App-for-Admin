import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Pages/AgentPage.dart';
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

/// The one conversation of this app session. It survives leaving the page and coming back; "New
/// chat" clears it.
class AgentSession {
  AgentSession._();
  static AgentController controller = AgentController();

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
/// saffron, drawn as a glossy 3D button with a light shine that sweeps across it every few seconds.
class AgentOverlay extends StatelessWidget {
  const AgentOverlay({super.key, required this.child, this.signedIn, this.onOpen});

  final Widget child;

  /// Tests hand in their own signed-in signal and what a tap does; the app never sets these.
  @visibleForTesting
  final Listenable? signedIn;
  @visibleForTesting
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ListenableBuilder(
          listenable: signedIn ?? AdminProfileProvider.instance,
          builder: (context, _) {
            if (AdminProfileProvider.current == null) return const SizedBox.shrink();
            return ValueListenableBuilder<bool>(
              valueListenable: AgentRouteVisibility.instance.onAgent,
              builder: (context, onAgent, _) => _DraggableAgentButton(hidden: onAgent, onOpen: onOpen),
            );
          },
        ),
      ],
    );
  }
}

const String _kPrefsDx = 'agent_button_dx_fraction';
const String _kPrefsDy = 'agent_button_dy_fraction';

/// Diameter of the button; also what keeps it fully on-screen when a position is clamped.
const double kAgentButtonSize = 56;
const double _kSideInset = 14;

class _DraggableAgentButton extends StatefulWidget {
  const _DraggableAgentButton({required this.hidden, this.onOpen});

  final bool hidden;
  final VoidCallback? onOpen;

  @override
  State<_DraggableAgentButton> createState() => _DraggableAgentButtonState();
}

class _DraggableAgentButtonState extends State<_DraggableAgentButton> {
  Offset? _position; // top-left, logical pixels
  Offset? _pendingFraction;
  bool _loaded = false;
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
      _pendingFraction = (dx != null && dy != null) ? Offset(dx, dy) : null;
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
    final bottomInset = GuideSpace.navClearanceOf(context) + GuideSpace.md;
    final pos = _resolve(screen, media.padding, bottomInset);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Offstage(
        offstage: widget.hidden,
        child: TickerMode(
          enabled: !widget.hidden,
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
    );
  }
}
