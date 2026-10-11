import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/PlanningQueries.dart';
import '../utils/StudentScope.dart';
import 'AssociationManager.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideWait.dart';

/// Overdue associations dashboard (Phase 6, half 1, item 2).
///
/// An association is overdue when:
///   * `status == 'pending'` and `preferredDate` has passed — a proposal
///     nobody ever confirmed, or
///   * `status == 'confirmed'` and `confirmedDate` has passed — a meeting that
///     should have happened and was never marked complete.
///
/// Reads the existing `associations` collection only. Status and date are
/// matched **in Dart**, exactly as `AssociationManager` does, so no composite
/// index and no new collection are needed (Rule 12).
///
/// Scoping follows the role hierarchy: a HOD sees every overdue item; any other
/// admin sees those about the students they may see (`StudentScope`).
class OverdueAssociationsPage extends StatefulWidget {
  const OverdueAssociationsPage({super.key});

  @override
  State<OverdueAssociationsPage> createState() =>
      _OverdueAssociationsPageState();
}

class _OverdueAssociationsPageState extends State<OverdueAssociationsPage> {
  final AdminProfile _profile = AdminProfileProvider.require();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _associations =
      StudentScope(_profile).historyStream('associations');

  bool get _isHod => _profile.isHod;

  /// HOD and Guide lists mix several admins' records, so the card names the owner.
  bool get _showsGuideLabel => _profile.isHod || _profile.isGuide;

  // The stream, the overdue predicate and the day count now live in
  // `utils/PlanningQueries.dart` so this screen and the weekly planning
  // overview cannot drift on what "overdue" means. Behaviour is unchanged.

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: GuideAppBar(
            title: Text("Overdue Associations")),
          body: StreamBuilder<QuerySnapshot>(
                  stream: _associations,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const GuideWait();
                    }

                    // Filtered in Dart, matching AssociationManager's approach.
                    final overdue = <_OverdueItem>[];

                    for (final doc in snapshot.data?.docs ?? []) {
                      final data = doc.data() as Map<String, dynamic>;
                      final since = associationOverdueSince(data);
                      if (since == null) continue;
                      overdue.add(_OverdueItem(doc.id, data, since));
                    }

                    // Longest overdue first — the most neglected at the top.
                    overdue.sort((a, b) => a.since.compareTo(b.since));

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        _summaryCard(overdue.length),
                        const SizedBox(height: 18),
                        if (overdue.isEmpty)
                          _emptyCard()
                        else
                          ...overdue.map(_itemCard),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _summaryCard(int count) {
    return GuideSummaryBanner(
      tone: count == 0 ? GuideTone.good : GuideTone.bad,
      icon: count == 0 ? Icons.check_circle_outline : Icons.event_busy_outlined,
      title: "$count overdue",
      lines: [
        _isHod
            ? "All guides (HOD view)"
            : "Your students · ${_profile.displayName}",
      ],
    );
  }

  Widget _emptyCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          "Nothing overdue",
          style: TextStyle(color: context.g.mutedText, fontSize: 14),
        ),
      ),
    );
  }

  Widget _itemCard(_OverdueItem item) {
    final data = item.data;
    final status = (data['status'] ?? '').toString();
    final studentName = (data['studentName'] ?? 'Unknown student').toString();
    // The current owner is the server-stamped `scopeGuide`; unstamped records
    // fall back to the historic `guideId`.
    final guideId = (data['scopeGuide'] ?? data['guideId'] ?? '').toString();
    final guideName = _profile.adminById(guideId)?.displayName ?? guideId;
    final days = daysOverdue(item.since);

    final label = status == 'pending'
        ? "Proposed for"
        : "Was confirmed for";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  studentName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: status == 'pending'
                      ? context.g.warning.withValues(alpha: .14)
                      : context.g.brass.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: status == 'pending'
                        ? context.g.warning
                        : context.g.brass,
                  ),
                ),
              ),
            ],
          ),

          // Only useful when looking across guides.
          if (_showsGuideLabel && guideId.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.person_pin, size: 13, color: context.g.mutedText),
                const SizedBox(width: 4),
                Flexible(child: Text(
                  "Guide: $guideName",
                  style: TextStyle(fontSize: 12, color: context.g.mutedText),
                ))],
            ),
          ],

          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.event, size: 13, color: context.g.mutedText),
              const SizedBox(width: 4),
              Flexible(child: Text(
                "$label ${DateFormat('dd MMM yyyy').format(item.since)}",
                style: TextStyle(fontSize: 12, color: context.g.mutedText),
              ))],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: context.g.danger.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              days == 1 ? "1 day overdue" : "$days days overdue",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.g.danger,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  // Deep link — opens on the tab this record lives on.
                  builder: (_) => AssociationManagerPage(
                    highlightAssociationId: item.id,
                  ),
                ),
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text("Open in Association Manager"),
            ),
          ),
        ],
      ),
    );
  }
}

/// A record plus the date that made it overdue, so the date is computed once
/// during filtering and reused for sorting and display.
class _OverdueItem {
  final String id;
  final Map<String, dynamic> data;
  final DateTime since;

  const _OverdueItem(this.id, this.data, this.since);
}
