import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'SeenMarkers.dart';
import 'UnseenDot.dart';
import '../Services/UpdateFCM.dart';

/// Wraps a hub tile / nav item with an [UnseenBadge] driven by one feature's
/// "is there new content I haven't seen" state — Master Task 2026-09-10,
/// Part 6.
///
/// Every call site only has to say WHICH content to watch (a query
/// returning the single most-recently-active matching doc) and what
/// feature key it is; this widget does the guide-id resolution and the
/// stream hoisting exactly once per instance, in [initState]/its
/// completion — never inside `build()` (Part 6 item 6) — regardless of how
/// many places in this app use it. Without this, the same async-resolve-
/// then-hoist plumbing would have to be hand-written at every one of this
/// app's badge sites.
class UnseenFeatureBadge extends StatefulWidget {
  final Widget child;
  final String featureKey;

  /// Set only for a feature scoped to one sub-entity (a specific student, a
  /// specific target) rather than the whole feature.
  final String? subKey;

  /// Given the resolved guide id, the query for every doc this feature
  /// should watch — a single equality filter, same as every other query in
  /// this app (no `.orderBy` paired with it, matching this project's
  /// established no-composite-index convention: `ServiceAssignments.dart`'s
  /// own header comment). This widget reduces the max [timestampField]
  /// across the returned docs itself rather than relying on the query to
  /// pre-sort/limit.
  final Stream<QuerySnapshot<Map<String, dynamic>>> Function(String guideId)
      latestQuery;

  /// Which field on that doc holds the timestamp to compare against the
  /// viewer's last-seen cursor. Ignored when [extractTimestamp] is given.
  final String timestampField;

  /// Override for a doc whose relevant timestamp is nested (e.g. inside a
  /// `pendingProposal` map) rather than a plain top-level field. Returning
  /// null means "this doc has no current activity to report" (e.g. a
  /// target with no pending proposal at all).
  final Timestamp? Function(Map<String, dynamic> data)? extractTimestamp;

  /// AGGREGATE mode — for a hub tile asking "is ANY sub-entity of this
  /// per-sub-entity feature unseen" (e.g. any one of several goal targets,
  /// any one of several students' comment threads), rather than one single
  /// whole-feature cursor. When set, [subKey] is ignored: every doc from
  /// [latestQuery] is compared against ITS OWN cursor (keyed by whatever
  /// this returns for that doc), and the badge shows if ANY doc is newer
  /// than its own cursor (or has no cursor yet at all).
  final String Function(String docId, Map<String, dynamic> data)? subKeyOf;

  /// Passed straight through to [UnseenBadge.offset]. Defaults to that
  /// widget's own default (tuned for a small icon) — a tile-shaped [child]
  /// (rounded corners, a drop shadow) should pass a more generous inset
  /// explicitly (grid-squeeze fix, 2026-09-10, item 2) so the dot lands on
  /// the tile's visible surface, not in the corner's shadow/curvature.
  final Offset dotOffset;

  /// Passed straight through to [UnseenBadge.fillParent] — see that
  /// widget's own doc comment for the full contract (grid-squeeze /
  /// disappearing-icon fix, 2026-09-11). `false` (the default) is
  /// correct for every current caller of this widget in either app.
  final bool fillParent;

  const UnseenFeatureBadge({
    super.key,
    required this.child,
    required this.featureKey,
    required this.latestQuery,
    this.timestampField = 'updatedAt',
    this.extractTimestamp,
    this.subKey,
    this.subKeyOf,
    this.dotOffset = const Offset(2, -2),
    this.fillParent = false,
  });

  @override
  State<UnseenFeatureBadge> createState() => _UnseenFeatureBadgeState();
}

class _UnseenFeatureBadgeState extends State<UnseenFeatureBadge> {
  Stream<bool>? _unseen;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final guide = await UpdateTokenService().getSavedGuide();
    if (!mounted || guide == null || guide.isEmpty) return;

    if (widget.subKeyOf != null) {
      setState(() => _unseen = _aggregateUnseen(guide));
      return;
    }

    final latest = widget.latestQuery(guide).map((snap) {
      Timestamp? max;
      for (final doc in snap.docs) {
        final ts = widget.extractTimestamp != null
            ? widget.extractTimestamp!(doc.data())
            : doc.data()[widget.timestampField];
        if (ts is Timestamp && (max == null || ts.compareTo(max) > 0)) {
          max = ts;
        }
      }
      return max;
    });

    final seen = widget.subKey == null
        ? SeenMarkers.seenAt(guide, widget.featureKey)
        : SeenMarkers.seenAtSub(guide, widget.featureKey, widget.subKey!);

    setState(() => _unseen = SeenMarkers.unseenFrom(latest, seen));
  }

  /// Aggregate mode's own combinator — every doc compared against ITS OWN
  /// cursor, ORed together, rather than one max-timestamp-vs-one-cursor
  /// comparison. Hand-rolled the same way [SeenMarkers.unseenFrom] is, for
  /// the same reason (no new package dependency for combining two hoisted
  /// streams).
  Stream<bool> _aggregateUnseen(String guide) {
    late StreamController<bool> controller;
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs;
    Map<String, Timestamp>? cursors;
    StreamSubscription? subA, subB;

    void emit() {
      if (docs == null || cursors == null) return;
      final anyUnseen = docs!.any((doc) {
        final ts = widget.extractTimestamp != null
            ? widget.extractTimestamp!(doc.data())
            : doc.data()[widget.timestampField];
        if (ts is! Timestamp) return false;
        final key = widget.subKeyOf!(doc.id, doc.data());
        final cursor = cursors![key];
        return cursor == null || ts.compareTo(cursor) > 0;
      });
      controller.add(anyUnseen);
    }

    controller = StreamController<bool>.broadcast(
      onListen: () {
        subA = widget.latestQuery(guide).listen((snap) {
          docs = snap.docs;
          emit();
        });
        subB = SeenMarkers.subCursors(guide, widget.featureKey).listen((c) {
          cursors = c;
          emit();
        });
      },
      onCancel: () {
        subA?.cancel();
        subB?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Widget build(BuildContext context) {
    final unseen = _unseen;
    if (unseen == null) return widget.child;

    return StreamBuilder<bool>(
      stream: unseen,
      builder: (context, snap) => UnseenBadge(
        show: snap.data ?? false,
        offset: widget.dotOffset,
        fillParent: widget.fillParent,
        child: widget.child,
      ),
    );
  }
}

/// The dot of ONE target with a proposal waiting (a HOD's or a guide's edit to its phases): shown while the proposal is newer than this admin's own cursor for THIS
/// target (`seenMarkers.{admin}.goalProposals.{targetId}`, written when its page is opened). It is the child behind the Home targets strip's dot and the Home tab's dot
/// (`UnseenAggregates.goalProposalsUnseen`, the same comparison for every target). Hoisted in [initState], never built in `build()`.
class GoalProposalDot extends StatefulWidget {
  const GoalProposalDot({super.key, required this.guideId, required this.targetId, required this.proposedAt, required this.child});

  final String guideId;
  final String targetId;
  final DateTime? proposedAt;
  final Widget child;

  @override
  State<GoalProposalDot> createState() => _GoalProposalDotState();
}

class _GoalProposalDotState extends State<GoalProposalDot> {
  late Stream<bool> _unseen = _make();

  Stream<bool> _make() {
    final at = widget.proposedAt;
    if (at == null || widget.guideId.isEmpty) return Stream.value(false);
    return SeenMarkers.seenAtSub(widget.guideId, 'goalProposals', widget.targetId).map((seen) => seen == null || at.isAfter(seen.toDate()));
  }

  @override
  void didUpdateWidget(GoalProposalDot old) {
    super.didUpdateWidget(old);
    if (old.proposedAt != widget.proposedAt || old.targetId != widget.targetId || old.guideId != widget.guideId) _unseen = _make();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
        stream: _unseen,
        builder: (context, snap) => UnseenBadge(key: const ValueKey('goal-proposal-dot'), show: snap.data ?? false, offset: const Offset(2, -2), child: widget.child),
      );
}
