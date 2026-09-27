import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/ColorProvider.dart';
import '../utils/GuideRoster.dart';
import '../utils/UnseenFeatureBadge.dart';
import 'FlaggedMessages.dart';
import 'PriorityStudents.dart';

/// Priority Students hub — the two "who needs attention" screens, together.
///
/// Reached from the "Priority Students" tile on the Folk Analysis tab (which
/// occupies the slot the never-implemented "Best Performer" tile used to hold).
/// Both destinations are **existing screens opened completely unchanged**; this
/// page only gathers their entry points, the same way `AbcdeHubPage` gathers
/// the five ABCDE screens.
///
/// The two belong together: one lists students flagged by activity signals
/// (stale contact, missing reports, overdue meetings, a low LIT axis), the
/// other lists students flagged by something they wrote in the AI chat. Both
/// answer "who should I reach out to", from different evidence.
///
/// ⚠️ Rule 10 note: `PriorityStudentsPage` surfaces LIT axes as named flags and
/// `FlaggedMessagesPage` surfaces chat distress. Neither is touched here, and
/// this page deliberately shows **no** student data itself — it is navigation
/// only, so nothing on it needs scoping.
class PriorityHubPage extends StatelessWidget {
  const PriorityHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: colorProvider.color,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "Priority Students",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorProvider.secondColor,
                fontSize: 20,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text(
                  "Two ways of seeing who needs you — one from their activity, "
                  "one from what they have written.",
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: colorProvider.secondColor.withOpacity(.75),
                  ),
                ),
              ),
              _HubButton(
                title: "Priority Students",
                subtitle: "Stale contact, missing reports, overdue meetings",
                icon: Icons.flag,
                // Blue, matching the Admin Hub tiles these two came from,
                // rather than the ABCDE hub's per-dimension colours — these
                // are not ABCDE limbs.
                colours: const [Color(0xFF1565C0), Color(0xFF1E88E5)],
                destination: const PriorityStudentsPage(),
              ),
              _HubButton(
                title: "Flagged Messages",
                subtitle: "Distress signals and pastoral notes from chat",
                icon: Icons.flag_outlined,
                colours: const [Color(0xFFC62828), Color(0xFFE53935)],
                destination: const FlaggedMessagesPage(),
                // Master Task 2026-09-10, Part 6 — unseen = a flagged
                // message since this guide last opened the list. Mirrors
                // `FlaggedMessagesPage._stream`'s own HOD-sees-all filter
                // exactly.
                wrapBadge: (tile) => UnseenFeatureBadge(
                  featureKey: 'flaggedMessages',
                  timestampField: 'createdAt',
                  latestQuery: (guide) {
                    final col = FirebaseFirestore.instance
                        .collection('flaggedChatMessages');
                    return (guide == kHodGuideId
                            ? col
                            : col.where('guideId', isEqualTo: guide))
                        .snapshots();
                  },
                  child: tile,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A raised gradient button, deliberately the same shape and treatment as the
/// ABCDE hub's, so the two hubs read as the same kind of surface.
class _HubButton extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colours;
  final Widget destination;

  /// Master Task 2026-09-10, Part 6 — see `_AbcdeButton.wrapBadge`'s own
  /// doc comment (`AbcdeHub.dart`); identical role here.
  final Widget Function(Widget tile)? wrapBadge;

  const _HubButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colours,
    required this.destination,
    this.wrapBadge,
  });

  @override
  State<_HubButton> createState() => _HubButtonState();
}

class _HubButtonState extends State<_HubButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tile = AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _pressed ? 3 : 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.colours,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              // Tinted to the button's own hue — a neutral grey shadow under a
              // saturated gradient reads as dirt, not depth.
              BoxShadow(
                color: widget.colours.first.withOpacity(_pressed ? .22 : .40),
                blurRadius: _pressed ? 8 : 16,
                offset: Offset(0, _pressed ? 3 : 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(_pressed ? .06 : .12),
                blurRadius: _pressed ? 4 : 10,
                offset: Offset(0, _pressed ? 2 : 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.22),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Icon(widget.icon, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(.85),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: Colors.white.withOpacity(.9), size: 22),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () => Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => widget.destination,
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        ),
        child: widget.wrapBadge != null ? widget.wrapBadge!(tile) : tile,
      ),
    );
  }
}
