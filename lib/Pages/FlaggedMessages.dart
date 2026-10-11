import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/SeenMarkers.dart';
import '../utils/SelectableDelete.dart';
import '../utils/StudentScope.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideWait.dart';
import '../widgets/GuideMeta.dart';

/// Phase 7 — flagged student chat messages.
///
/// Reads `flaggedChatMessages`, the flat collection the `studentChat`
/// function writes when it detects distress. It is deliberately flat rather
/// than a query over `studentChats/{uid}/messages`: "every flagged message
/// across my students" over the nested transcript needs a COLLECTION_GROUP
/// index, while this is one equality filter on the server-stamped scope
/// fields (`StudentScope.historyStream`) — the same shape every other
/// screen in this app uses.
///
/// The transcript remains the source of truth; tapping an entry opens it.
///
/// Scoping follows the role hierarchy: a HOD sees every flagged message, any
/// other admin only those of the students they may see.
class FlaggedMessagesPage extends StatefulWidget {
  const FlaggedMessagesPage({super.key});

  @override
  State<FlaggedMessagesPage> createState() => _FlaggedMessagesPageState();
}

class _FlaggedMessagesPageState extends State<FlaggedMessagesPage> {
  final FirebaseFirestore _firestore = GuideDb.instance;

  String? _guide;
  bool get _isHod => AdminProfileProvider.viewerIsHod;
  bool _loading = true;

  /// HOD and Guide lists mix several admins' students, so the card names the owner.
  bool get _showsGuideLabel {
    final p = AdminProfileProvider.current;
    return p != null && (p.isHod || p.isGuide);
  }

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadGuide();
  }

  Future<void> _loadGuide() async {
    final guide = AdminProfileProvider.current?.id;
    if (!mounted) return;
    setState(() {
      _guide = guide;
      _loading = false;
    });
    // Master Task 2026-09-10, Part 6 — opening this list is "seen" for
    // flagged messages.
    if (guide != null && guide.isNotEmpty) {
      SeenMarkers.markSeen(guide, 'flaggedMessages');
    }
  }

  /// Scope-field equality filters only; sorted in Dart so no composite index
  /// is needed.
  Stream<QuerySnapshot> _stream(String guide) =>
      StudentScope.current().historyStream('flaggedChatMessages');

  // ---------------------------------------------------------------------------
  // Multi-select + delete (Part 2). Shared mechanism — see
  // utils/SelectableDelete.dart's own header for the interaction model and
  // why each delete re-checks permission against fresh data rather than
  // trusting this selection state.
  // ---------------------------------------------------------------------------

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _cancelSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  /// Matches this screen's own read-access model: the server-stamped scope
  /// fields `_stream` reads decide delete permission too — HOD may delete
  /// anything, everyone else only a message about a student they may manage
  /// (`StudentScope.canManage`). A record not yet stamped falls back to its
  /// own `guideId` being the signed-in admin.
  Future<bool> _canDeleteFlagged(Map<String, dynamic> data) async {
    if (_isHod) return true;
    if (!data.containsKey('scopeGuide')) {
      return (data['guideId'] ?? '').toString() == (_guide ?? '');
    }
    return StudentScope.current().canManage(StudentRef(
      uid: (data['studentUid'] ?? '').toString(),
      guideId: (data['scopeGuide'] ?? '').toString(),
      teamGuide: (data['scopeTeam'] ?? '').toString(),
      gender: (data['scopeGender'] ?? '').toString(),
    ));
  }

  Future<void> _deleteSelected() async {
    final deleted = await confirmAndDeleteSelected(
      context: context,
      collectionName: 'flaggedChatMessages',
      selectedIds: _selectedIds,
      canDelete: _canDeleteFlagged,
      itemNounSingular: 'flagged message',
      itemNounPlural: 'flagged messages',
    );
    if (!mounted) return;
    setState(() {
      _selectedIds.removeAll(deleted);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  Future<void> _markReviewed(String docId, bool reviewed) async {
    try {
      await _firestore
          .collection('flaggedChatMessages')
          .doc(docId)
          .update({'reviewed': reviewed});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not update")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: _selectionMode
              ? selectionAppBar(
                  context: context,
                  count: _selectedIds.length,
                  onCancel: _cancelSelectionMode,
                  onDelete: _selectedIds.isEmpty ? null : _deleteSelected,
                )
              : GuideAppBar(
                  title: Text("Flagged Messages")),
          body: _loading ?
              const GuideWait() :
              StreamBuilder<QuerySnapshot>(
                stream: _stream(_guide ?? ''),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const GuideWait();
                  }

                  final docs = (snapshot.data?.docs ?? []).toList()
                    ..sort((a, b) {
                      final ta = (a.data() as Map<String, dynamic>)['createdAt'];
                      final tb = (b.data() as Map<String, dynamic>)['createdAt'];
                      if (ta is! Timestamp) return 1;
                      if (tb is! Timestamp) return -1;
                      return tb.compareTo(ta); // newest first
                    });

                  // Anything that is not explicitly pastoral is treated as
                  // urgent. Records written before `kind` existed have no
                  // such field, and a real distress record must never be
                  // quietly demoted to a calm note by a missing value.
                  final urgent = docs
                      .where((d) =>
                          (d.data() as Map<String, dynamic>)['kind'] !=
                          'pastoral')
                      .toList();
                  final pastoral = docs
                      .where((d) =>
                          (d.data() as Map<String, dynamic>)['kind'] ==
                          'pastoral')
                      .toList();

                  final acute = urgent
                      .where((d) =>
                          (d.data() as Map<String, dynamic>)['acuteRisk'] == true)
                      .length;

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _summaryCard(urgent.length, acute, pastoral.length),
                      const SizedBox(height: 18),
                      if (docs.isEmpty)
                        _emptyCard()
                      else ...[
                        if (urgent.isNotEmpty) ...[
                          _sectionHeader(
                            "Needs attention",
                            "${urgent.length}",
                            context.g.danger,
                          ),
                          ...urgent.map((d) =>
                              _entry(d.id, d.data() as Map<String, dynamic>)),
                        ],
                        if (pastoral.isNotEmpty) ...[
                          _sectionHeader(
                            "Pastoral notes",
                            "${pastoral.length}",
                            context.g.mutedText,
                          ),
                          _sectionCaption(
                            "Not urgent. Worth raising next time you speak.",
                          ),
                          ...pastoral.map((d) =>
                              _entry(d.id, d.data() as Map<String, dynamic>)),
                        ],
                      ],
                    ],
                  );
                },
              ),
        );
      },
    );
  }

  Widget _sectionHeader(String title, String count, Color colour) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: colour,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colour.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              count,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colour,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCaption(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: context.g.mutedText),
      ),
    );
  }

  Widget _summaryCard(int total, int acute, int pastoral) {
    final clear = total == 0;
    return GuideSummaryBanner(
      tone: clear
          ? GuideTone.good
          : acute > 0
              ? GuideTone.bad
              : GuideTone.warn,
      icon: clear ? Icons.check_circle_outline : Icons.flag_outlined,
      title: clear ? "Nothing urgent" : "$total needing attention",
      lines: [
        if (pastoral > 0)
          "$pastoral pastoral note${pastoral == 1 ? '' : 's'} below",
        _isHod
            ? "All students (HOD view)"
            : "Your students · "
                "${AdminProfileProvider.current?.displayName ?? _guide ?? ''}",
      ],
      emphasis: acute > 0 ? "$acute needing urgent attention" : null,
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
          "No student messages have been flagged.",
          textAlign: TextAlign.center,
          style: TextStyle(color: context.g.mutedText, fontSize: 14),
        ),
      ),
    );
  }

  Widget _entry(String docId, Map<String, dynamic> data) {
    // Missing `kind` means a record written before pastoral notes existed —
    // always a distress record, never demoted.
    final isPastoral = data['kind'] == 'pastoral';
    final acute = !isPastoral && data['acuteRisk'] == true;
    final reviewed = data['reviewed'] == true;
    final pastoralReason = (data['pastoralReason'] ?? '').toString();
    final studentName = (data['studentName'] ?? 'Unknown student').toString();
    final studentUid = (data['studentUid'] ?? '').toString();
    // The current owner is the server-stamped `scopeGuide`; unstamped records
    // fall back to the historic `guideId`.
    final guideId = (data['scopeGuide'] ?? data['guideId'] ?? '').toString();
    final guideName =
        AdminProfileProvider.current?.adminById(guideId)?.displayName ??
            guideId;
    final text = (data['text'] ?? '').toString();
    final when = data['createdAt'];
    final messageId = (data['messageId'] ?? '').toString();

    final whenText = when is Timestamp ?
        DateFormat('dd MMM yyyy, hh:mm a').format(when.toDate()) :
        "just now";

    final selected = _selectedIds.contains(docId);

    return selectableCard(
      context: context,
      selected: selected,
      selectionMode: _selectionMode,
      onTap: () {
        if (_selectionMode) {
          _toggleSelection(docId);
        }
      },
      onLongPress: () => _enterSelectionMode(docId),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.g.surface,
        // Aligned to 16 + a shadow (Part 3 — same radius and elevation
        // treatment AssociationManager's `_shell` and InteractionLogger's
        // `_logCard` already use, so all three read as one design system).
        // The colour-coded border for acute/pastoral/normal is unchanged —
        // it's a real safety-relevant signal, not just decoration.
        borderRadius: BorderRadius.circular(16),
        border: acute ?
            Border.all(color: context.g.danger, width: 2) :
            isPastoral ?
                Border.all(color: context.g.chipBackground) :
                Border.all(color: context.g.border),
        boxShadow: context.g.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  acute ?
                      Icons.warning_amber_rounded :
                      isPastoral ?
                          Icons.chat_bubble_outline :
                          Icons.flag_outlined,
                  size: 18,
                  color: acute ?
                      context.g.danger :
                      isPastoral ?
                          context.g.mutedText :
                          context.g.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    studentName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (reviewed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: context.g.success.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "Reviewed",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.g.success,
                      ),
                    ),
                  ),
              ],
            ),

            if (isPastoral && pastoralReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.g.chipBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  pastoralReason,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.g.mutedText,
                  ),
                ),
              ),
            ],

            if (acute) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.g.danger.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Possible acute risk — please reach out today",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.g.danger,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 10),
            Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),

            const SizedBox(height: 10),
            GuideMetaWrap(
              children: [
                GuideMeta(whenText, icon: Icons.schedule),
                if (_showsGuideLabel && guideId.isNotEmpty)
                  GuideMeta(guideName, icon: Icons.person_pin),
              ],
            ),

            const Divider(height: 22),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => _markReviewed(docId, !reviewed),
                  icon: Icon(
                    reviewed ? Icons.undo : Icons.check,
                    size: 16,
                  ),
                  label: Text(
                    reviewed ? "Mark unreviewed" : "Mark reviewed",
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: studentUid.isEmpty ?
                      null :
                      () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StudentChatTranscriptPage(
                                studentUid: studentUid,
                                studentName: studentName,
                                messageId: messageId,
                                flaggedCreatedAt:
                                    when is Timestamp ? when : null,
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.forum_outlined, size: 16),
                  label: const Text(
                    "View exchange",
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// The exchange containing ONE flagged message — not the student's wider
/// chat history.
///
/// ---------------------------------------------------------------------------
/// Investigation (Part 2 item 1) — what this screen showed before this task
/// ---------------------------------------------------------------------------
/// An unfiltered `.snapshots()` over the ENTIRE
/// `studentChats/{studentUid}/messages` subcollection — every message the
/// student has ever sent or received through the assistant, for their
/// whole lifetime of use, with no date or session bound at all. A guide
/// opening one flagged message from one bad day could read a student's
/// entire chat history, philosophical questions and all. FOLK_HANDOFF.md
/// Section 7 does call for a guide-visible *chat*, not guide-visible
/// excerpts, but "the chat around this flagged message" is not the same
/// thing as "every chat this student has ever had" — that's the gap this
/// task closes.
///
/// ---------------------------------------------------------------------------
/// Definition (Part 2 item 2) — "that exchange" = the flagged message's
/// own day-session
/// ---------------------------------------------------------------------------
/// `chat.js`'s Stage 6 (2026-08-24) already buckets every message with a
/// `sessionDate` (`dd-MM-yyyy`, IST) — the exact field the Student app's
/// own `AssistantScreen._loadHistory()` already uses to load "just today"
/// instead of the whole transcript. Reusing that same boundary here means
/// a guide sees precisely the conversation the student was having on the
/// day the flagged message was sent — real context for judging it, without
/// reaching into a different day's, possibly unrelated, conversation.
///
/// [messageId] (from the flagged record) is resolved to its OWN
/// `sessionDate` by reading that one message document — not by
/// reformatting `createdAt` client-side, which risks drift right at a
/// midnight-IST boundary. [flaggedCreatedAt] is a fallback ONLY, used if
/// the message doc or its `sessionDate` is missing (a malformed/legacy
/// record) — and even then the fallback is still same-calendar-day
/// scoped, never the unscoped full history. If NEITHER can be resolved,
/// this screen shows an explicit "could not determine" message rather
/// than falling back to showing everything (Part 2 item 3 — this is a
/// privacy tightening; failing open would defeat the entire point).
class StudentChatTranscriptPage extends StatelessWidget {
  final String studentUid;
  final String studentName;
  final String messageId;
  final Timestamp? flaggedCreatedAt;

  const StudentChatTranscriptPage({
    super.key,
    required this.studentUid,
    required this.studentName,
    required this.messageId,
    this.flaggedCreatedAt,
  });

  Future<String?> _resolveSessionDate() async {
    if (messageId.isNotEmpty) {
      try {
        final snap = await GuideDb.instance
            .collection('studentChats')
            .doc(studentUid)
            .collection('messages')
            .doc(messageId)
            .get();
        final sessionDate = (snap.data()?['sessionDate'] as String?)?.trim();
        if (sessionDate != null && sessionDate.isNotEmpty) return sessionDate;
      } catch (_) {
        // Fall through to the createdAt-based fallback below.
      }
    }

    final ts = flaggedCreatedAt;
    if (ts != null) {
      return DateFormat('dd-MM-yyyy').format(ts.toDate());
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: GuideAppBar(
            title: Text(
              studentName,
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
              ),
            )),
          body: FutureBuilder<String?>(
            future: _resolveSessionDate(),
            builder: (context, sessionSnap) {
              if (sessionSnap.connectionState == ConnectionState.waiting) {
                return const GuideWait();
              }

              final sessionDate = sessionSnap.data;
              if (sessionDate == null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      "Could not determine which conversation this "
                      "message belongs to.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.g.mutedText),
                    ),
                  ),
                );
              }

              return StreamBuilder<QuerySnapshot>(
                stream: GuideDb.instance
                    .collection('studentChats')
                    .doc(studentUid)
                    .collection('messages')
                    .where('sessionDate', isEqualTo: sessionDate)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const GuideWait();
                  }

                  final docs = (snapshot.data?.docs ?? []).toList()
                    ..sort((a, b) {
                      final ta = (a.data() as Map<String, dynamic>)['createdAt'];
                      final tb = (b.data() as Map<String, dynamic>)['createdAt'];
                      if (ta is! Timestamp) return -1;
                      if (tb is! Timestamp) return 1;
                      return ta.compareTo(tb); // oldest first, like a chat
                    });

                  if (docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          "No conversation recorded for this exchange.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.g.mutedText),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final m = docs[i].data() as Map<String, dynamic>;
                      return _bubble(context, m);
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _bubble(BuildContext context, Map<String, dynamic> m) {
    final fromStudent = m['role'] == 'student';
    final flagged = m['flagged'] == true;
    final acute = m['acuteRisk'] == true;
    final when = m['createdAt'];

    return Align(
      alignment: fromStudent ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.84,
        ),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: fromStudent ? context.g.surface : context.g.brass.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(14),
          border: flagged ?
              Border.all(
                  color: acute ? context.g.danger : context.g.warning,
                  width: 2) :
              Border.all(color: context.g.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  fromStudent ? studentName : "Assistant",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: context.g.mutedText,
                  ),
                ),
                if (flagged) ...[
                  const SizedBox(width: 8),
                  Icon(
                    acute ? Icons.warning_amber_rounded : Icons.flag,
                    size: 12,
                    color: acute ? context.g.danger : context.g.warning,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 5),
            Text(
              (m['text'] ?? '').toString(),
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
            if (when is Timestamp) ...[
              const SizedBox(height: 6),
              Text(
                DateFormat('dd MMM, hh:mm a').format(when.toDate()),
                style: TextStyle(fontSize: 9, color: context.g.mutedText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
