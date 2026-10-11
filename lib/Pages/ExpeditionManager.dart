import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/SeenMarkers.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentScope.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideWait.dart';

/// Expedition (pilgrimage / retreat) management.
///
/// Tab 1 — trips this guide created (`expeditions`), with registration counts.
/// Tab 2 — every registration belonging to the students this admin may see
/// (`StudentScope`), with the state of their post-trip reflection.
class ExpeditionManagerPage extends StatefulWidget {
  const ExpeditionManagerPage({super.key});

  @override
  State<ExpeditionManagerPage> createState() => _ExpeditionManagerPageState();
}

class _ExpeditionManagerPageState extends State<ExpeditionManagerPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = GuideDb.instance;

  String? _selectedGuide;

  /// Explicit controller so the FAB can react to tab changes — reading the
  /// inherited DefaultTabController does not trigger a rebuild.
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _loadGuide();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGuide() async {
    final guide = AdminProfileProvider.current?.id;
    if (mounted) setState(() => _selectedGuide = guide);
    // Master Task 2026-09-10, Part 6 — opening this screen is "seen" for
    // newly-submitted reflections (the Tab 2 feed this guide reviews).
    if (guide != null && guide.isNotEmpty) {
      SeenMarkers.markSeen(guide, 'expeditionReflections');
    }
  }

  /// Registrations of the students this admin may see (server-stamped scope
  /// fields; HOD unfiltered). One query shape for both tabs.
  Stream<QuerySnapshot<Map<String, dynamic>>> _registrationsStream() =>
      StudentScope.current().historyStream('expeditionRegistrations');

  String _formatTs(dynamic value) {
    if (value is! Timestamp) return "Not set";
    return DateFormat('dd MMM yyyy').format(value.toDate());
  }

  ({Color color, String label}) _statusStyle(String status) {
    switch (status) {
      case 'ongoing':
        return (color: context.g.warning, label: 'Ongoing');
      case 'completed':
        return (color: context.g.success, label: 'Completed');
      default:
        return (color: context.g.brass, label: 'Upcoming');
    }
  }

  Widget _shell({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.g.cardShadow,
      ),
      child: child,
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Create a trip
  // ---------------------------------------------------------------------------

  Future<void> _createTripDialog() async {
    String title = '';
    String description = '';
    String location = '';
    String maxParticipants = '';
    DateTime? tripDate;
    DateTime? deadline;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return GuideDialog(
            title: const Text("New Expedition"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    autofocus: true,
                    onChanged: (v) => title = v,
                    decoration: InputDecoration(
                      labelText: "Title",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    onChanged: (v) => description = v,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: "Description",
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    onChanged: (v) => location = v,
                    decoration: InputDecoration(
                      labelText: "Location",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    onChanged: (v) => maxParticipants = v,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: "Max participants (optional)",
                    ),
                  ),
                  const SizedBox(height: 6),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event, size: 20),
                    title:
                        const Text("Trip date", style: TextStyle(fontSize: 14)),
                    trailing: Text(
                      tripDate == null
                          ? "Not set"
                          : DateFormat('dd MMM yyyy').format(tripDate!),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: now,
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 730)),
                      );
                      if (picked != null) {
                        setDialogState(() => tripDate = picked);
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.how_to_reg, size: 20),
                    title: const Text("Registration deadline",
                        style: TextStyle(fontSize: 14)),
                    trailing: Text(
                      deadline == null
                          ? "Not set"
                          : DateFormat('dd MMM yyyy').format(deadline!),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: now,
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 730)),
                      );
                      if (picked != null) {
                        setDialogState(() => deadline = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: context.g.brass),
                onPressed: () => Navigator.pop(dialogContext, true),
                child:
                    Text("Create", style: TextStyle(color: context.g.onPrimary)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    if (title.trim().isEmpty || tripDate == null) {
      if (mounted) {
        showSnackbar(
          context,
          "Title and trip date are required",
          Colors.red,
          Icons.error,
        );
      }
      return;
    }

    try {
      await _firestore.collection('expeditions').add({
        'title': title.trim(),
        'description': description.trim(),
        'location': location.trim(),
        'tripDate': Timestamp.fromDate(tripDate!),
        'registrationDeadline':
            deadline == null ? null : Timestamp.fromDate(deadline!),
        'createdBy': _selectedGuide ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'maxParticipants': int.tryParse(maxParticipants.trim()),
        'status': 'upcoming',
      });

      if (!mounted) return;
      showSnackbar(context, "Expedition created", Colors.green, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not create trip", Colors.red, Icons.error);
    }
  }

  /// Lets the guide move a trip through upcoming → ongoing → completed.
  Future<void> _changeStatus(String docId, String current) async {
    final next = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text("Trip status"),
        children: ['upcoming', 'ongoing', 'completed'].map((s) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, s),
            child: Row(
              children: [
                Icon(
                  s == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: context.g.brass,
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(_statusStyle(s).label))],
            ),
          );
        }).toList(),
      ),
    );

    if (next == null || next == current) return;

    try {
      await _firestore
          .collection('expeditions')
          .doc(docId)
          .update({'status': next});

      if (!mounted) return;
      showSnackbar(context, "Status updated", Colors.blue, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not update", Colors.red, Icons.error);
    }
  }

  // ---------------------------------------------------------------------------
  // Registrations
  // ---------------------------------------------------------------------------

  void _showRegistrations(
    String tripTitle,
    List<QueryDocumentSnapshot> registrations,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: BoxDecoration(
            color: context.g.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.g.chipBackground,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                tripTitle,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                "${registrations.length} registered",
                style: TextStyle(fontSize: 12, color: context.g.mutedText),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: registrations.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text("Nobody has registered yet"),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: registrations.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final reflected = data['hasReflected'] == true;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: context.g.brass,
                              child: Text(
                                (data['studentName'] ?? '?')
                                    .toString()
                                    .characters
                                    .first
                                    .toUpperCase(),
                                style: TextStyle(color: context.g.onPrimary),
                              ),
                            ),
                            title: Text(
                              (data['studentName'] ?? 'Unknown').toString(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              reflected
                                  ? "Reflection submitted"
                                  : "Reflection pending",
                              style: TextStyle(
                                fontSize: 11,
                                color: reflected ? context.g.success : context.g.warning,
                              ),
                            ),
                            trailing: Icon(
                              reflected ? Icons.check_circle : Icons.schedule,
                              size: 18,
                              color: reflected ? context.g.success : context.g.warning,
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReflection(Map<String, dynamic> data) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: Text((data['studentName'] ?? 'Reflection').toString()),
        content: SingleChildScrollView(
          child: Text(
            (data['reflectionText'] ?? '').toString().isEmpty
                ? "No reflection text."
                : (data['reflectionText']).toString(),
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1 — trips
  // ---------------------------------------------------------------------------

  Widget _buildTrips(String guide) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('expeditions')
          .where('createdBy', isEqualTo: guide)
          .snapshots(),
      builder: (context, tripSnap) {
        if (tripSnap.connectionState == ConnectionState.waiting) {
          return const GuideWait();
        }

        final trips = tripSnap.data?.docs ?? [];

        if (trips.isEmpty) {
          return const Center(child: Text("No trips created yet"));
        }

        // One registration stream serves every card's count.
        return StreamBuilder<QuerySnapshot>(
          stream: _registrationsStream(),
          builder: (context, regSnap) {
            final allRegs = regSnap.data?.docs ?? [];

            final sorted = trips.toList()
              ..sort((a, b) {
                final aDate = (a.data() as Map<String, dynamic>)['tripDate'];
                final bDate = (b.data() as Map<String, dynamic>)['tripDate'];
                if (aDate is! Timestamp || bDate is! Timestamp) return 0;
                return aDate.compareTo(bDate);
              });

            return ListView(
              padding: const EdgeInsets.all(16),
              children: sorted.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final status = (data['status'] ?? 'upcoming').toString();
                final style = _statusStyle(status);

                final registrations = allRegs
                    .where((r) =>
                        ((r.data() as Map<String, dynamic>)['expeditionId'] ??
                            '') ==
                        doc.id)
                    .toList();

                final max = data['maxParticipants'];
                final capacity = max is num ? " / ${max.toInt()}" : "";

                return _shell(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              (data['title'] ?? 'Untitled').toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _changeStatus(doc.id, status),
                            child: _chip(style.label, style.color),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.place,
                              size: 15, color: context.g.mutedText),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              (data['location'] ?? 'No location').toString(),
                              style: TextStyle(
                                fontSize: 12,
                                color: context.g.mutedText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.event,
                              size: 15, color: context.g.mutedText),
                          const SizedBox(width: 5),
                          Flexible(child: Text(
                            _formatTs(data['tripDate']),
                            style: TextStyle(
                              fontSize: 12,
                              color: context.g.mutedText,
                            ),
                          )),
                          const SizedBox(width: 14),
                          Icon(Icons.people,
                              size: 15, color: context.g.mutedText),
                          const SizedBox(width: 5),
                          Flexible(child: Text(
                            "${registrations.length}$capacity",
                            style: TextStyle(
                              fontSize: 12,
                              color: context.g.mutedText,
                            ),
                          ))],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showRegistrations(
                            (data['title'] ?? 'Trip').toString(),
                            registrations,
                          ),
                          icon: const Icon(Icons.list_alt, size: 17),
                          label: const Text("View Registrations"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.g.brass,
                            side: BorderSide(color: context.g.brass),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2 — registrations & reflections
  // ---------------------------------------------------------------------------

  Widget _buildRegistrations(String guide) {
    return StreamBuilder<QuerySnapshot>(
      stream: _registrationsStream(),
      builder: (context, regSnap) {
        if (regSnap.connectionState == ConnectionState.waiting) {
          return const GuideWait();
        }

        final regs = regSnap.data?.docs ?? [];

        if (regs.isEmpty) {
          return const Center(child: Text("No registrations yet"));
        }

        // Trips are global content: a student of this admin may have joined a
        // trip another admin created, so every trip title is read here.
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('expeditions').snapshots(),
          builder: (context, tripSnap) {
            final titles = <String, String>{};
            for (final doc in tripSnap.data?.docs ?? []) {
              titles[doc.id] =
                  ((doc.data() as Map<String, dynamic>)['title'] ?? 'Trip')
                      .toString();
            }

            // Grouped by trip so a guide reads one expedition at a time.
            final grouped = <String, List<QueryDocumentSnapshot>>{};
            for (final reg in regs) {
              final expId =
                  ((reg.data() as Map<String, dynamic>)['expeditionId'] ?? '')
                      .toString();
              grouped.putIfAbsent(expId, () => []).add(reg);
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: grouped.entries.map((entry) {
                final tripTitle = titles[entry.key] ?? 'Unknown trip';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, top: 4),
                      child: Text(
                        tripTitle,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...entry.value.map((reg) {
                      final data = reg.data() as Map<String, dynamic>;
                      final reflected = data['hasReflected'] == true;

                      return _shell(
                        child: InkWell(
                          onTap: reflected ? () => _showReflection(data) : null,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (data['studentName'] ?? 'Unknown')
                                          .toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Registered ${_formatTs(data['registeredAt'])}",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.g.mutedText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _chip(
                                reflected ? "Submitted" : "Pending",
                                reflected ? context.g.success : context.g.warning,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 10),
                  ],
                );
              }).toList(),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        final guide = _selectedGuide;

        return GuideScaffold(
          appBar: GuideAppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "Expeditions",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorProvider.secondColor,
                fontSize: 20,
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              labelColor: context.g.brass,
              unselectedLabelColor: context.g.mutedText,
              indicatorColor: context.g.brass,
              tabs: const [
                Tab(text: "Manage Trips"),
                Tab(text: "Reflections"),
              ],
            )),
          body: guide == null
              ? const GuideWait()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTrips(guide),
                    _buildRegistrations(guide),
                  ],
                ),
          floatingActionButton: (guide != null && _tabController.index == 0)
              ? FloatingActionButton.extended(
                  backgroundColor: context.g.brass,
                  onPressed: _createTripDialog,
                  icon: Icon(Icons.add, color: context.g.onPrimary),
                  label: Text(
                    "New Trip",
                    style: TextStyle(color: context.g.onPrimary),
                  ),
                )
              : null,
        );
      },
    );
  }
}
