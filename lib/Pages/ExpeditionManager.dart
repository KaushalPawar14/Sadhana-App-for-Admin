import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../Services/HierarchyApi.dart';
import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/ExpeditionModel.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentScope.dart';
import '../theme/GuideTheme.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideMeta.dart';
import '../widgets/GuideSheet.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideWait.dart';
import 'ExpeditionRegistrations.dart';

/// Expedition (pilgrimage / retreat) management.
///
/// Tab 1 - Manage Trips: the active trips (a HOD sees every trip; everyone else the trips they created),
/// with registration counts, each student's attendance, and delete.
/// Tab 2 - History: trips whose date has passed (moved here by the server the day after the trip date),
/// read only: the final status of every student, and delete for the trip's creator and HODs.
///
/// Every trip is for ONE gender (`targetGender`): a Guide or Male Enabler creates boys' trips, a Female Enabler
/// girls'; a HOD chooses when creating. The Student app shows a student only the active trips of their own gender.
class ExpeditionManagerPage extends StatefulWidget {
  const ExpeditionManagerPage({super.key});

  @override
  State<ExpeditionManagerPage> createState() => _ExpeditionManagerPageState();
}

class _ExpeditionManagerPageState extends State<ExpeditionManagerPage>
    with SingleTickerProviderStateMixin {
  FirebaseFirestore get _firestore => GuideDb.instance;

  String? _selectedGuide;
  bool _isHod = false;

  /// Explicit controller so the FAB can react to tab changes.
  late final TabController _tabController;

  /// The trips this admin may see; rebuilt on Retry.
  late Stream<QuerySnapshot<Map<String, dynamic>>> _tripsStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    final profile = AdminProfileProvider.current;
    _selectedGuide = profile?.id;
    _isHod = profile?.isHod ?? false;
    _tripsStream = _openTripsStream();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// A HOD reads every trip; everyone else the trips they created (the rules prove exactly this query).
  Stream<QuerySnapshot<Map<String, dynamic>>> _openTripsStream() {
    final trips = _firestore.collection('expeditions');
    return (_isHod || _selectedGuide == null ? trips : trips.where('createdBy', isEqualTo: _selectedGuide)).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _registrationsStream() =>
      StudentScope.current().historyStream('expeditionRegistrations');

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
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  // ---------------------------------------------------------------------------
  // Create a trip
  // ---------------------------------------------------------------------------

  Future<void> _createTripDialog() async {
    final profile = AdminProfileProvider.current;
    if (profile == null) return;
    String title = '';
    String description = '';
    String location = '';
    String maxParticipants = '';
    DateTime? tripDate;
    DateTime? endDate; // the LAST day; the same date for a one-day trip
    DateTime? deadline;
    String? datesError;
    // A Guide / Male Enabler: boys. A Female Enabler: girls. A HOD chooses.
    String? targetGender = tripTargetGenderFor(profile);

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
                  if (profile.isHod) ...[
                    const Text("This trip is for", style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final g in const ['male', 'female'])
                          GuideChoiceChip(
                            key: ValueKey('trip-for-$g'),
                            label: targetGenderLabel(g),
                            selected: targetGender == g,
                            onSelected: (_) => setDialogState(() => targetGender = g),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Text(
                      "This trip is for ${targetGenderLabel(targetGender).toLowerCase()}.",
                      key: const ValueKey('trip-for-fixed'),
                      style: TextStyle(fontSize: 13, color: context.g.mutedText),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    autofocus: true,
                    onChanged: (v) => title = v,
                    decoration: const InputDecoration(labelText: "Title"),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    onChanged: (v) => description = v,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: "Description", alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    onChanged: (v) => location = v,
                    decoration: const InputDecoration(labelText: "Location"),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    onChanged: (v) => maxParticipants = v,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Max participants (optional)"),
                  ),
                  const SizedBox(height: 6),
                  // Start and end. Choosing the start fills the end while it is empty or would
                  // fall before it, so a one-day trip is still a single choice.
                  ListTile(
                    key: const ValueKey('trip-start'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event, size: 20),
                    title: const Text("Trip start date", style: TextStyle(fontSize: 14)),
                    trailing: Text(
                      tripDate == null ? "Not set" : DateFormat('dd MMM yyyy').format(tripDate!),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: tripDate ?? now,
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 730)),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          tripDate = picked;
                          if (endDate == null || endDate!.isBefore(picked)) endDate = picked;
                          datesError = null;
                        });
                      }
                    },
                  ),
                  ListTile(
                    key: const ValueKey('trip-end'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_available, size: 20),
                    title: const Text("Trip end date", style: TextStyle(fontSize: 14)),
                    subtitle: const Text(
                      "The trip moves to History the day after this",
                      style: TextStyle(fontSize: 11.5),
                    ),
                    trailing: Text(
                      endDate == null ? "Not set" : DateFormat('dd MMM yyyy').format(endDate!),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () async {
                      final now = DateTime.now();
                      final first = tripDate ?? now;
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: endDate ?? first,
                        firstDate: first,
                        lastDate: now.add(const Duration(days: 730)),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          endDate = picked;
                          tripDate ??= picked;
                          datesError = null;
                        });
                      }
                    },
                  ),
                  if (datesError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(datesError!, style: TextStyle(fontSize: 12, color: context.g.danger)),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.how_to_reg, size: 20),
                    title: const Text("Registration deadline", style: TextStyle(fontSize: 14)),
                    trailing: Text(
                      deadline == null ? "Not set" : DateFormat('dd MMM yyyy').format(deadline!),
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
                      if (picked != null) setDialogState(() => deadline = picked);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: context.g.brass),
                onPressed: () {
                  // Checked in the dialog, where the guide can fix it, rather than after it has
                  // closed and everything typed is gone.
                  final problem = tripDatesProblem(tripDate, endDate);
                  if (problem != null) {
                    setDialogState(() => datesError = problem);
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: Text("Create", style: TextStyle(color: context.g.onPrimary)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    if (targetGender == null) {
      if (mounted) showSnackbar(context, "Choose Boys or Girls for this trip", Colors.red, Icons.error);
      return;
    }
    if (title.trim().isEmpty || tripDate == null || endDate == null) {
      if (mounted) showSnackbar(context, "Title and trip dates are required", Colors.red, Icons.error);
      return;
    }

    try {
      await _firestore.collection('expeditions').add({
        'title': title.trim(),
        'description': description.trim(),
        'location': location.trim(),
        // The start stays `tripDate`, which every older reader already uses; the new `endDate` is the last
        // day (the same date for a one-day trip). The trip moves to History the day after IT.
        'tripDate': Timestamp.fromDate(tripDate!),
        'endDate': Timestamp.fromDate(endDate!),
        'registrationDeadline': deadline == null ? null : Timestamp.fromDate(deadline!),
        'createdBy': _selectedGuide ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'maxParticipants': int.tryParse(maxParticipants.trim()),
        'status': 'upcoming',
        // Who the trip is for, and where it is in its life: active until the day after the trip's END date,
        // when the server sets `archived: true` and it moves to History.
        'targetGender': targetGender,
        'archived': false,
      });

      if (!mounted) return;
      showSnackbar(context, "Expedition created", Colors.green, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not create trip", Colors.red, Icons.error);
    }
  }

  /// Lets the creator move a trip through upcoming -> ongoing -> completed.
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
                  s == current ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18,
                  color: context.g.brass,
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(_statusStyle(s).label)),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (next == null || next == current) return;

    try {
      await _firestore.collection('expeditions').doc(docId).update({'status': next});
      if (!mounted) return;
      showSnackbar(context, "Status updated", Colors.blue, Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not update", Colors.red, Icons.error);
    }
  }

  // ---------------------------------------------------------------------------
  // Delete (an active trip, or a History card)
  // ---------------------------------------------------------------------------

  Future<void> _confirmDelete(String tripId, Map<String, dynamic> trip, {required bool history}) async {
    final name = history ? historyTitle(trip) : (trip['title'] ?? 'this trip').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: Text(history ? "Delete this History card?" : "Delete this trip?"),
        content: Text(
          '"$name" and every registration for it will be removed permanently. '
          '${history ? '' : 'Students will no longer see it. '}This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
          TextButton(
            key: const ValueKey('confirm-delete-trip'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text("Delete", style: TextStyle(color: dialogContext.g.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await HierarchyApi.instance.deleteExpedition(tripId);
      if (!mounted) return;
      showSnackbar(context, "Trip deleted", Colors.blue, Icons.check_circle);
    } on HierarchyException catch (e) {
      if (!mounted) return;
      showSnackbar(context, e.message, Colors.red, Icons.error);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not delete the trip", Colors.red, Icons.error);
    }
  }

  // ---------------------------------------------------------------------------
  // Registrations
  // ---------------------------------------------------------------------------

  void _showRegistrations(String tripId, String tripTitle) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          decoration: BoxDecoration(
            color: context.g.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const GuideSheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(tripTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              Flexible(child: ExpeditionRegistrationsList(tripId: tripId, editable: true)),
            ],
          ),
        );
      },
    );
  }

  void _openHistoryTrip(String tripId, Map<String, dynamic> trip) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpeditionHistoryTripPage(
          tripId: tripId,
          trip: trip,
          onDelete: () => _confirmDelete(tripId, trip, history: true),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1 - active trips
  // ---------------------------------------------------------------------------

  Widget _buildTrips(List<QueryDocumentSnapshot<Map<String, dynamic>>> all) {
    final trips = all.where((d) => !tripArchived(d.data())).toList()
      ..sort((a, b) => soonestFirst(a.data(), b.data()));

    if (trips.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text("No active trips. Tap \"New Trip\" to create one.", textAlign: TextAlign.center),
        ),
      );
    }

    // One registration stream serves every card's count.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _registrationsStream(),
      builder: (context, regSnap) {
        final allRegs = regSnap.data?.docs ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: trips.map((doc) {
            final data = doc.data();
            final status = (data['status'] ?? 'upcoming').toString();
            final style = _statusStyle(status);
            final registrations = allRegs.where((r) => (r.data()['expeditionId'] ?? '') == doc.id).length;
            final max = data['maxParticipants'];
            final capacity = max is num ? " / ${max.toInt()}" : "";
            final forWho = targetGenderLabel(data['targetGender']?.toString());

            return _shell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (data['title'] ?? 'Untitled').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
                      Icon(Icons.place, size: 15, color: context.g.mutedText),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          (data['location'] ?? 'No location').toString(),
                          style: TextStyle(fontSize: 12, color: context.g.mutedText),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _meta(Icons.event, tripDatesText(data)),
                      _meta(Icons.people, "$registrations$capacity"),
                      if (forWho.isNotEmpty) _meta(Icons.wc, "For ${forWho.toLowerCase()}", key: ValueKey('trip-for-${doc.id}')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: ValueKey('registrations-${doc.id}'),
                          onPressed: () => _showRegistrations(doc.id, (data['title'] ?? 'Trip').toString()),
                          icon: const Icon(Icons.list_alt, size: 17),
                          label: const Text("View Registrations"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.g.brass,
                            side: BorderSide(color: context.g.brass),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: ValueKey('delete-trip-${doc.id}'),
                        tooltip: "Delete trip",
                        onPressed: () => _confirmDelete(doc.id, data, history: false),
                        icon: Icon(Icons.delete_outline, color: context.g.danger),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _meta(IconData icon, String text, {Key? key}) {
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: context.g.mutedText),
        const SizedBox(width: 5),
        Flexible(child: Text(text, style: TextStyle(fontSize: 12, color: context.g.mutedText))),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2 - History
  // ---------------------------------------------------------------------------

  Widget _buildHistory(List<QueryDocumentSnapshot<Map<String, dynamic>>> all) {
    final past = all.where((d) => tripArchived(d.data())).toList()
      ..sort((a, b) => newestFirst(a.data(), b.data()));

    if (past.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text("No past trips yet. A trip appears here the day after its date.", textAlign: TextAlign.center),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _registrationsStream(),
      builder: (context, regSnap) {
        final allRegs = regSnap.data?.docs ?? [];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: past.map((doc) {
            final data = doc.data();
            final summary = summariseAttendance(
                allRegs.where((r) => (r.data()['expeditionId'] ?? '') == doc.id).map((r) => r.data()));
            final trip = (data['title'] ?? '').toString();
            final place = (data['location'] ?? '').toString().trim();
            final forWho = targetGenderLabel(data['targetGender']?.toString());
            return _shell(
              child: InkWell(
                key: ValueKey('history-trip-${doc.id}'),
                onTap: () => _openHistoryTrip(doc.id, data),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(historyTitle(data), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        IconButton(
                          key: ValueKey('delete-history-${doc.id}'),
                          tooltip: "Delete",
                          onPressed: () => _confirmDelete(doc.id, data, history: true),
                          icon: Icon(Icons.delete_outline, color: context.g.danger),
                        ),
                      ],
                    ),
                    if (place.isNotEmpty && trip.isNotEmpty)
                      Text(trip, style: TextStyle(fontSize: 12, color: context.g.mutedText)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        _meta(Icons.people, "${summary.total} students"),
                        _meta(Icons.check_circle_outline, "${summary.full} fully, ${summary.partial} partly"),
                        if (forWho.isNotEmpty) _meta(Icons.wc, "For ${forWho.toLowerCase()}"),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: GuideAppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "Expeditions",
              style: TextStyle(fontWeight: FontWeight.bold, color: colorProvider.secondColor, fontSize: 20),
            ),
            bottom: TabBar(
              controller: _tabController,
              labelColor: context.g.brass,
              unselectedLabelColor: context.g.mutedText,
              indicatorColor: context.g.brass,
              tabs: const [
                Tab(text: "Manage Trips"),
                Tab(text: "History"),
              ],
            ),
          ),
          body: _selectedGuide == null
              ? const GuideWait()
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _tripsStream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text("Couldn't load the trips just now.", textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () => setState(() => _tripsStream = _openTripsStream()),
                                child: const Text("Retry"),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (!snap.hasData) return const GuideWait();
                    final docs = snap.data!.docs;
                    return TabBarView(
                      controller: _tabController,
                      children: [_buildTrips(docs), _buildHistory(docs)],
                    );
                  },
                ),
          floatingActionButton: (_selectedGuide != null && _tabController.index == 0)
              ? FloatingActionButton.extended(
                  backgroundColor: context.g.brass,
                  onPressed: _createTripDialog,
                  icon: Icon(Icons.add, color: context.g.onPrimary),
                  label: Text("New Trip", style: TextStyle(color: context.g.onPrimary)),
                )
              : null,
        );
      },
    );
  }
}

/// One trip in History: the students with their FINAL status, read only. A reflection can be opened from a
/// student's row. The trip's creator and HODs can delete the card (with a confirmation).
class ExpeditionHistoryTripPage extends StatelessWidget {
  const ExpeditionHistoryTripPage({
    super.key,
    required this.tripId,
    required this.trip,
    required this.onDelete,
  });

  final String tripId;
  final Map<String, dynamic> trip;

  /// Asks for confirmation and deletes (the manager owns that flow).
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return GuideScaffold(
      appBar: GuideAppBar(
        title: Text(historyTitle(trip), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          IconButton(
            key: const ValueKey('delete-history-detail'),
            tooltip: "Delete",
            icon: Icon(Icons.delete_outline, color: g.danger),
            onPressed: () async {
              await onDelete();
              if (context.mounted && Navigator.of(context).canPop()) {
                // If the trip was deleted, its card is gone: leave this page too.
                final gone = await _tripGone();
                if (gone && context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: g.chipBackground,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: g.mutedText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text("A past trip: read only. Statuses are final.", style: TextStyle(fontSize: 12, color: g.mutedText)),
                ),
              ],
            ),
          ),
          Expanded(child: ExpeditionRegistrationsList(tripId: tripId, editable: false)),
        ],
      ),
    );
  }

  Future<bool> _tripGone() async {
    try {
      final snap = await GuideDb.instance.collection('expeditions').doc(tripId).get();
      return !snap.exists;
    } catch (_) {
      return false;
    }
  }
}
