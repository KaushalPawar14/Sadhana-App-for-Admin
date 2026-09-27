import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../Services/UpdateFCM.dart';
import '../utils/ColorProvider.dart';
import '../utils/GuideRoster.dart';
import '../utils/PlanningQueries.dart';
import 'AssociationManager.dart';

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
/// Scoping follows Section 2: SBSD is the HOD and sees every guide's overdue
/// items; any other guide sees only their own.
class OverdueAssociationsPage extends StatefulWidget {
  const OverdueAssociationsPage({super.key});

  @override
  State<OverdueAssociationsPage> createState() =>
      _OverdueAssociationsPageState();
}

class _OverdueAssociationsPageState extends State<OverdueAssociationsPage> {
  String? _guide;
  bool _isHod = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGuide();
  }

  Future<void> _loadGuide() async {
    final guide = await UpdateTokenService().getSavedGuide();
    if (!mounted) return;
    setState(() {
      _guide = guide;
      _isHod = guide == kHodGuideId;
      _loading = false;
    });
  }

  // The stream, the overdue predicate and the day count now live in
  // `utils/PlanningQueries.dart` so this screen and the weekly planning
  // overview cannot drift on what "overdue" means. Behaviour is unchanged.

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            backgroundColor: colorProvider.color,
            elevation: 0,
            iconTheme: IconThemeData(color: colorProvider.secondColor),
            title: Text(
              "Overdue Associations",
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<QuerySnapshot>(
                  stream: scopedAssociationsStream(_guide ?? ''),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: count == 0
              ? [Colors.green.shade600, Colors.green.shade300]
              : [Colors.red.shade700, Colors.red.shade300],
        ),
      ),
      child: Row(
        children: [
          Icon(
            count == 0 ? Icons.check_circle : Icons.event_busy,
            color: Colors.white,
            size: 34,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$count overdue",
                  style: const TextStyle(
                    fontSize: 22,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _isHod
                      ? "All guides (HOD view)"
                      : "Your students · ${_guide ?? ''}",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          "Nothing overdue",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
      ),
    );
  }

  Widget _itemCard(_OverdueItem item) {
    final data = item.data;
    final status = (data['status'] ?? '').toString();
    final studentName = (data['studentName'] ?? 'Unknown student').toString();
    final guideId = (data['guideId'] ?? '').toString();
    final days = daysOverdue(item.since);

    final label = status == 'pending'
        ? "Proposed for"
        : "Was confirmed for";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
                      ? Colors.orange.shade50
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: status == 'pending'
                        ? Colors.orange.shade800
                        : Colors.blue.shade800,
                  ),
                ),
              ),
            ],
          ),

          // Only useful when looking across guides.
          if (_isHod && guideId.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.person_pin, size: 13, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  "Guide: $guideId",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ],

          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.event, size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                "$label ${DateFormat('dd MMM yyyy').format(item.since)}",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              days == 1 ? "1 day overdue" : "$days days overdue",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade800,
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
