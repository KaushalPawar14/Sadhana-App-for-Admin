import 'package:flutter/material.dart';

/// WIDTH CLASSES for the Guide app on a computer (the web build). Decided from the window's WIDTH with `MediaQuery` — never `LayoutBuilder`
/// (a standing rule of this app).
///
/// A phone (anything narrower than [kTabletMin]) is NEVER treated as wide: every wide-screen change in the app is behind these checks, so
/// the mobile app looks and behaves exactly as it always did.
///
///   phone     < 600 dp   the app as it is: bottom pill navigation, one column
///   tablet    600–899    the same single-column app, content centred with a reading width
///   desktop   ≥ 900      side navigation, wide content, lists beside details, the assistant as a side panel
const double kTabletMin = 600;
const double kDesktopMin = 900;

/// The widest a page of reading content grows (lines stay readable on a big monitor).
const double kContentMaxWidth = 1080;

/// A square tile (Home, Tasks ...) never grows past this on a wide window: it flows into a grid with several per row instead of stretching.
/// A Home plan widget (THIS WEEK, TODAY'S TASKS) on a wide window: compact, like the tiles under it, never stretched across the column.
const double kHomeCardMaxWidth = 560;

const double kTileMaxSide = 220;

/// A navigation card in a wide grid (Analysis, Tasks ...): about three per row of the content column.
const double kCardGridWidth = 320;

/// The widest a dialog or form grows.
const double kDialogMaxWidth = 560;

/// The side panel the assistant opens in on a computer.
const double kAssistantPanelWidth = 440;

/// The side navigation's width.
const double kSideNavWidth = 232;

bool isDesktopWidth(double width) => width >= kDesktopMin;
bool isTabletWidth(double width) => width >= kTabletMin && width < kDesktopMin;

extension ResponsiveContext on BuildContext {
  double get _w => MediaQuery.sizeOf(this).width;

  /// A computer-sized window (≥ 900 dp wide).
  bool get isDesktop => isDesktopWidth(_w);

  /// A tablet-sized window (600–899 dp wide).
  bool get isTablet => isTabletWidth(_w);

  /// Wider than a phone.
  bool get isWide => _w >= kTabletMin;
}

/// The width of the content column on this window: the whole window on a phone, at most [kContentMaxWidth] on a wide one (minus the side
/// navigation on a computer).
double contentWidthOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (!context.isWide) return w;
  final avail = context.isDesktop ? w - kSideNavWidth : w;
  return avail > kContentMaxWidth ? kContentMaxWidth : avail;
}

/// Centres [child] with a maximum width on a wide window; on a phone it is [child] itself (the same widget, nothing added).
///
/// The page keeps its state (its streams, scroll positions, text fields) when the window is resized across a width class: the child is
/// held by a [GlobalKey], so Flutter moves it instead of building it again.
class ContentWidth extends StatefulWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = kContentMaxWidth});

  final Widget child;
  final double maxWidth;

  @override
  State<ContentWidth> createState() => _ContentWidthState();
}

class _ContentWidthState extends State<ContentWidth> {
  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (!context.isWide) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: widget.maxWidth), child: child),
    );
  }
}
