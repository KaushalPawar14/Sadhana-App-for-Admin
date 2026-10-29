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

/// Centres [child] with a maximum width on a wide window; on a phone it is [child] itself (the same widget, nothing added).
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = kContentMaxWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!context.isWide) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}
