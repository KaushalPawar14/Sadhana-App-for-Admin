import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/Responsive.dart';

import '../actions/PriorityActions.dart';
import '../widgets/GuideDialog.dart';
import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/SeenMarkers.dart';
import 'StudentProfilePage.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/AiText.dart';
import '../widgets/GuideWait.dart';

/// Priority students (Phase 6, half 1, item 4).
///
/// **A transparent checklist, never a score.** Each student shows the actual
/// reasons they surfaced, in plain words. Nothing here computes a blended
/// priority number, a rating, a tier or a percentage — the ordering is simply
/// *how many separate concerns* a student has, and every one of them is named
/// on the card so the guide can disagree with any of them.
///
/// LIT axes are checked and displayed **independently** (Section 8): L, I and
/// T each produce their own line, and are never summed or averaged with each
/// other or with anything else.
///
/// Composed from existing data — no new collection (Rule 12). Overdue
/// associations reuse `associationOverdueSince()`; missing submissions reuse
/// `NotificationManager().missingUsernames`.
class PriorityStudentsPage extends StatefulWidget {
  const PriorityStudentsPage({super.key});

  @override
  State<PriorityStudentsPage> createState() => _PriorityStudentsPageState();
}

class _PriorityStudentsPageState extends State<PriorityStudentsPage> {
  String? _guide;
  bool _isHod = false;
  bool _loading = true;
  bool _rosterFailed = false;

  List<PriorityStudent> _priority = [];
  int _inScope = 0;

  /// This admin's "removed from my priority list" records: student uid -> the concern kinds they had then.
  Map<String, Set<String>> _dismissed = {};
  int _hiddenCount = 0;

  /// On a computer: the student whose profile is open beside the list (list | details).
  String? _detailUid;

  /// Multi-select: long-press a student to start, tap others to add.
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final profile = AdminProfileProvider.require();
    final guide = profile.displayName;
    // Opening this list is "seen" for the automatic priority reasons, the
    // same as the flagged-messages list is for its own dot. Keyed by the
    // admin's ID (what `SeenMarkers.seenAt` is read with), never the display
    // name the rest of this method uses for wording.
    if (profile.id.isNotEmpty) {
      SeenMarkers.markSeen(profile.id, 'priorityReasons');
    }
    // One shared computation (actions/PriorityActions.dart): the AI agent lists the same students, in
    // the same order, with the same reasons.
    final list = await loadPriorityList();

    if (list.rosterFailed) {
      if (!mounted) return;
      setState(() {
        _guide = guide;
        _isHod = profile.isHod;
        _rosterFailed = true;
        _priority = [];
        _inScope = 0;
        _loading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _guide = guide;
      _isHod = profile.isHod;
      _rosterFailed = false;
      _priority = list.students;
      _dismissed = list.dismissed;
      _hiddenCount = list.hiddenCount;
      _selected.clear();
      _inScope = list.inScope;
      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Remove from the priority list (multi-select)
  // ---------------------------------------------------------------------------

  void _toggle(String uid) {
    setState(() {
      if (!_selected.remove(uid)) _selected.add(uid);
    });
  }

  /// Takes the selected students off THIS admin's priority list. It writes one small record per student
  /// (`priorityDismissals/{adminId}__{studentUid}`: adminId, studentUid, kinds, dismissedAt) and nothing else:
  /// the student, their reports, chats, meetings and assessments are never touched.
  Future<void> _removeSelected() async {
    final chosen = _priority.where((p) => _selected.contains(p.uid)).toList();
    if (chosen.isEmpty) return;
    final n = chosen.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: Text(n == 1 ? "Remove 1 student from your Interactions needed list?" : "Remove $n students from your Interactions needed list?"),
        content: const Text(
          "This only takes them off your Interactions needed list. The students themselves and "
          "everything about them (reports, chats, meetings, assessments) are NOT deleted or changed. "
          "A student comes back to the list if a new reason appears.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
          TextButton(
            key: const ValueKey('confirm-remove-priority'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(n == 1 ? "Remove 1 student" : "Remove $n students",
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await removeFromPriority(chosen);
      if (!mounted) return;
      setState(() => _selected.clear());
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n == 1 ? "1 student removed from your Interactions needed list" : "$n students removed from your Interactions needed list"),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not remove them. Nothing was changed.")));
    }
  }

  /// Puts every student this admin removed back on their list (deletes only those small records).
  Future<void> _restoreRemoved() async {
    try {
      await restoreToPriority(_dismissed.keys.toList());
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not restore them just now.")));
    }
  }

  // ---------------------------------------------------------------------------
  // The checklist
  // ---------------------------------------------------------------------------

  Color _toneColour(PriorityTone tone) => switch (tone) {
        PriorityTone.danger => context.g.danger,
        PriorityTone.warning => context.g.warning,
        PriorityTone.brass => context.g.brass,
        PriorityTone.brown => Colors.brown,
      };

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          // a computer shows the list beside the student's profile, so it uses the whole window
          fullWidth: context.isDesktop,
          appBar: GuideAppBar(
            leading: _selecting
                ? IconButton(
                    key: const ValueKey('cancel-selection'),
                    tooltip: "Cancel selection",
                    icon: Icon(Icons.close, color: colorProvider.secondColor),
                    onPressed: () => setState(_selected.clear),
                  )
                : null,
            title: Text(_selecting ? "${_selected.length} selected" : "Interactions needed"),
            actions: [
              if (!_selecting)
                IconButton(
                  tooltip: "Refresh",
                  icon: Icon(Icons.refresh, color: colorProvider.secondColor),
                  onPressed: _loading ? null : _load,
                ),
            ]),
          body: _loading
              ? const GuideWait()
              : _masterDetail(
                  Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            _summaryCard(),
                            if (_hiddenCount > 0 && !_selecting) _restoreLine(),
                            const SizedBox(height: 18),
                            if (_rosterFailed)
                              _messageCard("Could not read the student list")
                            else if (_priority.isEmpty)
                              _messageCard(
                                _inScope == 0
                                    ? "No students in scope yet"
                                    : "No interaction is needed right now",
                              )
                            else ...[
                              if (!_selecting)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text("Press and hold a student to select, then remove from your list.",
                                      style: TextStyle(fontSize: 11, color: context.g.mutedText)),
                                ),
                              ..._priority.map(_studentCard),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_selecting) _selectionBar(),
                  ],
                ),
                ),
        );
      },
    );
  }

  /// A phone / tablet: the list alone (a tap on "Open profile" goes to the profile). A computer: the list on the left, the chosen student's
  /// profile on the right, so nothing is lost by opening someone.
  Widget _masterDetail(Widget list) {
    if (!context.isDesktop) return list;
    final g = context.g;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(key: const ValueKey('priority-list-pane'), width: 460, child: list),
        VerticalDivider(width: 1, color: g.mutedText.withValues(alpha: .2)),
        Expanded(
          key: const ValueKey('priority-detail-pane'),
          child: _detailUid == null
              ? Center(child: Text('Choose a student to see the profile here.', style: context.gText.small))
              : ClipRect(child: StudentProfilePage(key: ValueKey('detail-$_detailUid'), studentUid: _detailUid!)),
        ),
      ],
    );
  }

  Widget _summaryCard() {
    final count = _priority.length;
    return GuideSummaryBanner(
      tone: count == 0 ? GuideTone.good : GuideTone.warn,
      icon: count == 0 ? Icons.check_circle_outline : Icons.flag_outlined,
      title: count == 0 ? "Nobody needs an interaction" : "$count need an interaction",
      lines: [
        if (_inScope > 0) "out of $_inScope students",
        _isHod
            ? "All students (HOD view)"
            : "Your students · ${_guide ?? ''}",
      ],
    );
  }

  /// "N removed by you - Restore": the way back (deletes only this admin's own small removal records).
  Widget _restoreLine() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text("$_hiddenCount removed by you.", style: TextStyle(fontSize: 12, color: context.g.mutedText)),
          TextButton(
            key: const ValueKey('restore-removed'),
            onPressed: _restoreRemoved,
            child: const Text("Restore"),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar() {
    final g = context.g;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(color: g.surface, boxShadow: g.cardShadow),
        child: ElevatedButton.icon(
          key: const ValueKey('remove-from-priority'),
          style: ElevatedButton.styleFrom(
            backgroundColor: g.brass,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: _removeSelected,
          icon: Icon(Icons.playlist_remove, color: g.onPrimary),
          label: Text("Remove from my list", style: TextStyle(color: g.onPrimary)),
        ),
      ),
    );
  }

  Widget _messageCard(String text) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.g.mutedText, fontSize: 14),
        ),
      ),
    );
  }

  Widget _studentCard(PriorityStudent item) {
    final picked = _selected.contains(item.uid);
    return GestureDetector(
      key: ValueKey('priority-${item.uid}'),
      behavior: HitTestBehavior.opaque,
      onLongPress: _selecting ? null : () => _toggle(item.uid),
      onTap: _selecting ? () => _toggle(item.uid) : (context.isDesktop ? () => setState(() => _detailUid = item.uid) : null),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: picked || _detailUid == item.uid ? context.g.brass.withValues(alpha: .10) : context.g.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: picked ? context.g.brass : Colors.transparent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(picked ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 22, color: picked ? context.g.brass : context.g.mutedText),
                ),
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              // A count of named concerns, not a rating. The reasons below are
              // the substance; this is only how the list was ordered.
              Text(
                item.flags.length == 1
                    ? "1 reason"
                    : "${item.flags.length} reasons",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.g.mutedText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          /// Every reason, spelled out. The guide decides what matters.
          ...item.flags.map(
            (flag) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _toneColour(flag.tone),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AiText(
                      flag.label,
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (!_selecting) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentProfilePage(studentUid: item.uid),
                  ),
                ),
                icon: const Icon(Icons.person_outline, size: 16),
                label: const Text("Open profile"),
              ),
            ),
          ],
        ],
      ),
      ),
      ),
    );
  }
}
