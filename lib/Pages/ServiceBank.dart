import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/SeenMarkers.dart';
import '../utils/ServiceAssignments.dart';
import '../utils/ServiceBankContent.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentScope.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideWait.dart';
import '../widgets/GuideMeta.dart';
import '../widgets/GuideSheet.dart';

/// Service Bank — replaces `Pages/DevotionalServiceManager.dart` entirely
/// (Phase: Service Bank, Part 4). Reached from the same "D" tile on
/// `Pages/AbcdeHub.dart` the old page used.
///
/// Two tabs: "Services" (the 19 fixed services, Part 4 item 2) and
/// "Assigned" (who has what, Part 4 item 4).
class ServiceBankPage extends StatefulWidget {
  const ServiceBankPage({super.key});

  @override
  State<ServiceBankPage> createState() => _ServiceBankPageState();
}

class _ServiceBankPageState extends State<ServiceBankPage> {
  // The signed-in admin (role-based hierarchy) — the profile is loaded before
  // any screen is shown.
  final String _selectedGuide = AdminProfileProvider.require().id;

  @override
  void initState() {
    super.initState();
    // Master Task 2026-09-10, Part 6 — opening this screen is "seen" for
    // the serviceAssignments feature.
    if (_selectedGuide.isNotEmpty) {
      SeenMarkers.markSeen(_selectedGuide, 'serviceAssignments');
    }
  }

  // ---------------------------------------------------------------------------
  // Assign picker — Part 4 item 3: every student this admin may see (the
  // role-based scope, `StudentScope`) is eligible.
  // ---------------------------------------------------------------------------

  Future<void> _openAssignPicker(ServiceBankEntry service) async {
    final guide = _selectedGuide;
    if (guide.isEmpty) {
      showSnackbar(context, "Still loading your guide profile — try again in a moment",
          context.g.warning, Icons.watch_later_outlined);
      return;
    }

    final usersSnap = await StudentScope.current().studentsGet();
    final eligible = <Map<String, String>>[];
    for (final doc in usersSnap.docs) {
      final data = doc.data();
      final name = (data['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      eligible.add({'uid': doc.id, 'name': name});
    }
    eligible.sort((a, b) => a['name']!.compareTo(b['name']!));

    if (!mounted) return;

    final selected = <String>{};
    bool saving = false;

    // Captured here, read only AFTER the sheet has fully closed — the exact
    // same "Cancel restarts the app" root cause found and fixed on
    // `Pages/BoysDetails.dart`'s add-student dialog applies to any sheet
    // that calls `showSnackbar(context, ...)` using its OWN StatefulBuilder
    // context right after popping the route that owns it. Nothing below
    // touches `context` or `setSheetState` after the pop.
    int? assignedCount;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> save() async {
              setSheetState(() => saving = true);
              try {
                for (final uid in selected) {
                  await assignService(
                    serviceNumber: service.number,
                    studentUid: uid,
                    assignedByGuideId: guide,
                  );
                }
                assignedCount = selected.length;
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } catch (_) {
                setSheetState(() => saving = false);
                if (sheetContext.mounted) {
                  showSnackbar(sheetContext, "Could not save", Colors.red, Icons.error);
                }
              }
            }

            return Container(
              constraints:
                  BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: BoxDecoration(
                color: context.g.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GuideSheetHeader(title: "Assign: ${service.title}"),
                  const SizedBox(height: 4),
                  Text(
                    "Select students",
                    style: TextStyle(fontSize: 12, color: context.g.mutedText),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: eligible.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text("No eligible students"),
                          )
                        : Material(
                            color: Colors.transparent,
                            child: ListView(
                              shrinkWrap: true,
                              children: eligible.map((s) {
                                final uid = s['uid']!;
                                return CheckboxListTile(
                                  value: selected.contains(uid),
                                  title: Text(s['name']!,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600, fontSize: 14)),
                                  activeColor: context.g.brass,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  onChanged: (checked) {
                                    setSheetState(() {
                                      if (checked == true) {
                                        selected.add(uid);
                                      } else {
                                        selected.remove(uid);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (saving || selected.isEmpty) ? null : save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.g.brass,
                      ),
                      child: saving
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: const GuideBusyDot(),
                            )
                          : Text("Assign",
                              style: TextStyle(color: context.g.onPrimary, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (assignedCount != null && mounted) {
      showSnackbar(
        context,
        "Assigned to $assignedCount student${assignedCount == 1 ? '' : 's'}",
        Colors.green,
        Icons.check_circle,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Tab 1 — Services
  // ---------------------------------------------------------------------------

  Widget _serviceExpansionTile(ServiceBankEntry service) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: context.g.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      // Same ExpansionTile pattern this app already uses elsewhere
      // (`WeeklyPlanning.dart`'s `_sectionShell`/`_goalTargetCard`,
      // `TopWeekResults.dart`, `BookLinkManager.dart`) — Rule 1.
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.g.brass.withValues(alpha: .14),
            ),
            child: Center(
              child: Text(
                "${service.number}",
                style: TextStyle(fontWeight: FontWeight.w800, color: context.g.brass),
              ),
            ),
          ),
          title: Text(
            service.title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          children: [
            ...service.subPoints.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("•  ", style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(child: Text(p, style: const TextStyle(fontSize: 13, height: 1.35))),
                    ],
                  ),
                )),
            if (service.nuance != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.g.warning.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.g.warning.withValues(alpha: .14)),
                ),
                child: Text(service.nuance!,
                    style: TextStyle(fontSize: 12.5, color: context.g.warning, height: 1.4)),
              ),
            ],
            if (service.context != null) ...[
              const SizedBox(height: 6),
              Text(service.context!,
                  style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: context.g.mutedText, height: 1.4)),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.g.brass.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Assessment question: “${service.assessmentQuestion}”",
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: context.g.brass, height: 1.4),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openAssignPicker(service),
                icon: const Icon(Icons.person_add_alt_1, size: 16),
                label: const Text("Assign"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServicesTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: kServiceBank.length,
      itemBuilder: (context, i) => _serviceExpansionTile(kServiceBank[i]),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2 — Assigned (Part 4 item 4: readable both ways)
  // ---------------------------------------------------------------------------

  Widget _buildAssignedTab() {
    return _AssignedTabBody(viewerGuide: _selectedGuide);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return DefaultTabController(
          length: 2,
          child: GuideScaffold(
            appBar: GuideAppBar(
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                "Service Bank",
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: colorProvider.secondColor, fontSize: 20),
              ),
              bottom: TabBar(
                labelColor: context.g.brass,
                unselectedLabelColor: context.g.mutedText,
                indicatorColor: context.g.brass,
                tabs: [Tab(text: "Services"), Tab(text: "Assigned")],
              )),
            body: TabBarView(children: [_buildServicesTab(), _buildAssignedTab()]),
          ),
        );
      },
    );
  }
}

/// Part 4 item 4 — "readable both ways". A chip toggle switches the SAME
/// live `allAssignmentsStream()` between grouping by student and grouping
/// by service, matching `Home/Calendar.dart`'s own chip-based `_Tab`/
/// `_tabRow` pattern (Rule 1) rather than a second `TabBar`.
class _AssignedTabBody extends StatefulWidget {
  final String viewerGuide;

  const _AssignedTabBody({required this.viewerGuide});

  @override
  State<_AssignedTabBody> createState() => _AssignedTabBodyState();
}

enum _GroupBy { student, service }

class _AssignedTabBodyState extends State<_AssignedTabBody> {
  _GroupBy _groupBy = _GroupBy.student;

  Widget _chip(String label, _GroupBy value) {
    final selected = _groupBy == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GuideChoiceChip(label: label, selected: selected, onSelected: (_) => setState(() => _groupBy = value)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ServiceAssignment>>(
      stream: allAssignmentsStream(),
      builder: (context, assignSnap) {
        if (!assignSnap.hasData) {
          return GuideWait(snapshot: assignSnap);
        }

        return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          // One scoped users read to resolve names (the assignments stream
          // is already scoped to this admin's visible students).
          future: StudentScope.current().studentsGet(),
          builder: (context, usersSnap) {
            if (!usersSnap.hasData) {
              return GuideWait(snapshot: usersSnap);
            }

            final names = <String, String>{};
            for (final doc in usersSnap.data!.docs) {
              final data = doc.data();
              names[doc.id] = (data['name'] ?? 'Unknown').toString();
            }

            final visible = assignSnap.data!;

            if (visible.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                  child: Text(
                    "No services assigned yet.",
                    style: TextStyle(color: context.g.mutedText),
                  ),
                ),
              );
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      _chip("By Student", _GroupBy.student),
                      _chip("By Service", _GroupBy.service),
                    ],
                  ),
                ),
                Expanded(
                  child: _groupBy == _GroupBy.student
                      ? _byStudent(visible, names)
                      : _byService(visible, names),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _byStudent(List<ServiceAssignment> assignments, Map<String, String> names) {
    final byStudent = <String, List<ServiceAssignment>>{};
    for (final a in assignments) {
      byStudent.putIfAbsent(a.studentUid, () => []).add(a);
    }
    final studentUids = byStudent.keys.toList()
      ..sort((a, b) => (names[a] ?? '').compareTo(names[b] ?? ''));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: studentUids.map((uid) {
        final list = byStudent[uid]!;
        return _groupCard(
          title: names[uid] ?? 'Unknown',
          assignments: list,
          rowLabel: (a) => kServiceBank
              .firstWhere((s) => s.number == a.serviceNumber,
                  orElse: () => kServiceBank.first)
              .title,
        );
      }).toList(),
    );
  }

  Widget _byService(List<ServiceAssignment> assignments, Map<String, String> names) {
    final byService = <int, List<ServiceAssignment>>{};
    for (final a in assignments) {
      byService.putIfAbsent(a.serviceNumber, () => []).add(a);
    }
    final serviceNumbers = byService.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: serviceNumbers.map((serviceNumber) {
        final service = kServiceBank.firstWhere((s) => s.number == serviceNumber,
            orElse: () => kServiceBank.first);
        final list = byService[serviceNumber]!;
        return _groupCard(
          title: "${service.number}. ${service.title}",
          assignments: list,
          rowLabel: (a) => names[a.studentUid] ?? 'Unknown',
        );
      }).toList(),
    );
  }

  Widget _groupCard({
    required String title,
    required List<ServiceAssignment> assignments,
    required String Function(ServiceAssignment) rowLabel,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: context.g.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Text("${assignments.length} assignment${assignments.length == 1 ? '' : 's'}",
              style: TextStyle(fontSize: 11, color: context.g.mutedText)),
          children: assignments.map((a) {
            return _assignmentRow(label: rowLabel(a), assignment: a);
          }).toList(),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case kStatusCompleted:
        return context.g.success;
      case kStatusInProgress:
        return context.g.warning;
      case kStatusWithdrawn:
        return context.g.mutedText;
      default:
        return context.g.mutedText;
    }
  }

  Widget _assignmentRow({required String label, required ServiceAssignment assignment}) {
    final withdrawn = assignment.isWithdrawn;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: withdrawn ? context.g.chipBackground : context.g.chipBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        decoration: withdrawn ? TextDecoration.lineThrough : null,
                        color: withdrawn ? context.g.mutedText : null)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor(assignment.status).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(statusLabel(assignment.status),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _statusColor(assignment.status))),
                    ),
                    if (assignment.competence != null) ...[
                      const SizedBox(width: 6),
                      Icon(
                        assignment.competence!.level == kCompetenceYes
                            ? Icons.check_circle
                            : Icons.hourglass_bottom,
                        size: 13,
                        color: assignment.competence!.level == kCompetenceYes
                            ? context.g.success
                            : context.g.mutedText,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (!withdrawn)
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 20),
              onPressed: () => _openAssignmentDetail(context, assignment, label),
            ),
        ],
      ),
    );
  }

  Future<void> _openAssignmentDetail(
      BuildContext context, ServiceAssignment assignment, String label) async {
    final service = kServiceBank.firstWhere((s) => s.number == assignment.serviceNumber,
        orElse: () => kServiceBank.first);
    final guide = widget.viewerGuide;

    String status = assignment.status;
    String competenceLevel = assignment.competence?.level ?? kCompetenceNotYet;
    final noteController = TextEditingController(text: assignment.competence?.note ?? '');
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> saveStatus(String newStatus) async {
              setSheetState(() => saving = true);
              try {
                await updateAssignmentStatus(
                  assignmentId: assignment.id,
                  newStatus: newStatus,
                  updatedBy: guide,
                );
                setSheetState(() {
                  status = newStatus;
                  saving = false;
                });
              } catch (_) {
                setSheetState(() => saving = false);
              }
            }

            Future<void> saveCompetence() async {
              setSheetState(() => saving = true);
              try {
                await setCompetence(
                  assignmentId: assignment.id,
                  level: competenceLevel,
                  assessedByGuideId: guide,
                  note: noteController.text,
                );
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } catch (_) {
                setSheetState(() => saving = false);
              }
            }

            Future<void> unassign() async {
              final confirmed = await showDialog<bool>(
                context: sheetContext,
                builder: (dc) => GuideDialog(
                  title: const Text("Unassign this service?"),
                  content: Text(
                      "This marks the assignment withdrawn for $label. The record — including any competence already assessed — is kept, not deleted."),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text("Cancel")),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: context.g.danger),
                      onPressed: () => Navigator.pop(dc, true),
                      child: Text("Unassign", style: TextStyle(color: context.g.onPrimary)),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              setSheetState(() => saving = true);
              try {
                await withdrawAssignment(assignmentId: assignment.id, withdrawnBy: guide);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } catch (_) {
                setSheetState(() => saving = false);
              }
            }

            return Container(
              constraints:
                  BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: BoxDecoration(
                color: context.g.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.only(bottom: 14), child: GuideSheetHandle()),
                    const SizedBox(height: 18),
                    Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    Text("${service.number}. ${service.title}",
                        style: TextStyle(fontSize: 12, color: context.g.mutedText)),
                    const SizedBox(height: 16),
                    const Text("Status", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: kAssignmentStatuses.map((s) {
                        return GuideChoiceChip(label: statusLabel(s), selected: status == s, onSelected: saving ? null : (_) => saveStatus(s));
                      }).toList(),
                    ),
                    const Divider(height: 28),
                    // Part 4 item 5 — shown here, at the moment of
                    // assessing, so the assessment question is actually
                    // used rather than assumed remembered.
                    const Text("Competence assessment",
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: context.g.brass.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "“${service.assessmentQuestion}”",
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: context.g.brass,
                            height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        GuideChoiceChip(label: "Not yet", selected: competenceLevel == kCompetenceNotYet, onSelected: saving
                              ? null
                              : (_) => setSheetState(() => competenceLevel = kCompetenceNotYet)),
                        const SizedBox(width: 8),
                        GuideChoiceChip(label: "Yes", color: context.g.success, selected: competenceLevel == kCompetenceYes, onSelected: saving
                              ? null
                              : (_) => setSheetState(() => competenceLevel = kCompetenceYes)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteController,
                      enabled: !saving,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: "Note (optional)",
                      ),
                    ),
                    if (assignment.competence != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        "Last assessed by ${assignment.competence!.assessedBy}"
                        "${assignment.competence!.assessedAt != null ? ' on ${DateFormat('dd MMM yyyy').format(assignment.competence!.assessedAt!)}' : ''}",
                        style: TextStyle(fontSize: 11, color: context.g.mutedText, fontStyle: FontStyle.italic),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: saving ? null : saveCompetence,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.g.brass,
                        ),
                        child: saving
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: const GuideBusyDot())
                            : Text("Save assessment", style: TextStyle(color: context.g.onPrimary)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: saving ? null : unassign,
                        icon: Icon(Icons.remove_circle_outline, size: 16, color: context.g.danger),
                        label: Text("Unassign", style: TextStyle(color: context.g.danger)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    noteController.dispose();
  }
}
