import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/AbcdeActivity.dart';
import '../utils/SadhanaReportSource.dart';
import '../utils/ServiceAssignments.dart';
import '../utils/StudentScope.dart';
import '../theme/GuideTheme.dart';

/// Phase 8 — the ABCDE activity card.
///
/// One card, five labelled rows, so a guide can look once and get a read on a
/// student's trajectory instead of opening five screens.
///
/// ⚠️ **ACTIVITY DATA ONLY. This card never touches LIT (Rule 10).** It does
/// not read `litAssessments`, does not display L, I or T, and does not reuse
/// `HolisticSuggestion._gatherContext()` — that method reads `litAssessments`
/// at its line 289, so reusing it would drag LIT into an activity card. The
/// reads below are written fresh for exactly that reason.
///
/// ⚠️ **NOTHING IS AGGREGATED.** There is no total, no percentage, no badge, no
/// score and no ordering of dimensions by "health". Five dimensions stay five
/// dimensions; the guide compares them, the card does not.
///
/// READS (all existing collections, nothing new):
///   A  associations                where studentUid ==
///   B  booksRead                   where uid ==        (+ 1 bookmark doc)
///   B/C sadhana-reports AND hostel-sadhana/{name}/dates, merged by date —
///      Master Task 2026-09-11: a residence switch never moves a student's
///      past reports, so both collections are read and merged rather than
///      picking one by current residence (`utils/SadhanaReportSource.dart`).
///   C  users/{uid}.lifetimeRounds  — passed in, already streamed by the page
///   D  serviceAssignments where studentUid == (Service Bank task, replaces
///      the old `studentServices/{uid}` count) + scorecard/{name} (unrelated,
///      unchanged — see that task's Part 1 for why these two are separate)
///   E  expeditionRegistrations     where studentUid ==
class AbcdeActivityCard extends StatefulWidget {
  final String studentUid;
  final String studentName;

  /// `Stay at FOLK`, `Stay at Hostel` or `Stay at Localite` — kept for API
  /// parity with the caller. No longer used to pick which sadhana
  /// collection to read (Master Task 2026-09-11): B/C now reads and merges
  /// both, since a residence switch never moves a student's past reports
  /// out of the collection they were actually filed in.
  final String role;

  /// From the `users/{uid}` document the profile page already streams, so the
  /// honest lifetime figure costs no extra read.
  final int lifetimeRounds;

  const AbcdeActivityCard({
    super.key,
    required this.studentUid,
    required this.studentName,
    required this.role,
    required this.lifetimeRounds,
  });

  @override
  State<AbcdeActivityCard> createState() => _AbcdeActivityCardState();
}

class _AbcdeActivityCardState extends State<AbcdeActivityCard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// The student's current assignment, fetched once from their `users` doc
  /// (the caller only hands us a uid + name). Lets every history read below
  /// carry the scope filter the security rules can prove.
  Future<StudentRef>? _refFuture;
  Future<StudentRef> _studentRef() => _refFuture ??= _firestore
      .collection('users')
      .doc(widget.studentUid)
      .get()
      .then(StudentRef.fromDoc);

  /// `collection where <uidField> == this student`, plus the scope constraint.
  Future<Query<Map<String, dynamic>>> _scopedFor(
      String collection, String uidField) async {
    final ref = await _studentRef();
    return StudentScope.current().constrainForStudent(
        _firestore
            .collection(collection)
            .where(uidField, isEqualTo: widget.studentUid),
        ref);
  }

  bool _loading = true;
  bool _failed = false;

  /// Disclosure toggle for the two sparklines.
  ///
  /// ⚠️ This is a **reveal**, not a lazy fetch. The C bracket is specified to
  /// load on view and is computed from the same 30-day series the sparklines
  /// draw, so the subcollection read has already happened by the time this
  /// button exists. Hiding the fetch behind the tap would mean either reading
  /// twice or showing no bracket, so the tap controls pixels only — stated
  /// plainly here because "behind a tap" usually implies deferred cost.
  bool _showTrend = false;

  // C
  List<int> _chantSeries = const [];
  TrendReading _chantTrend =
      const TrendReading(recentAvg: 0, priorAvg: 0, direction: 'steady');
  String _bracket = 'Below F2';
  double _chantAvg = 0;

  // B
  List<int> _readingSeries = const [];
  TrendReading _readingTrend =
      const TrendReading(recentAvg: 0, priorAvg: 0, direction: 'steady');
  String _currentBook = '';
  String _currentBookLevel = '';
  int? _currentChapter;
  int _booksStarted = 0;

  /// Report-availability state, kept separate from "recorded zero".
  bool _hasAnyReports = false;
  int _reportDaysInWindow = 0;

  // A
  int? _daysSinceLastMeeting;
  DateTime? _nextMeeting;
  final Map<String, int> _statusCounts90d = {};

  // D
  int _assignedActiveServices = 0;
  int _completedServices = 0;
  int _competentServices = 0;
  int _lifetimeServiceDone = 0;

  // E
  int _tripsRegistered = 0;
  int _reflectionsSubmitted = 0;
  DateTime? _mostRecentTrip;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    try {
      // Fired together rather than sequentially — five independent reads should
      // not cost five round trips in series.
      final results = await Future.wait([
        _loadDailySeries(),
        _loadAssociation(),
        _loadBooks(),
        _loadService(),
        _loadExpeditions(),
      ]);
      // ignore: unused_local_variable
      final _ = results;

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// One read of the date subcollection yields BOTH the chanting and the
  /// reading series — the single most expensive read on this card, paid once.
  ///
  /// ⚠️ The whole subcollection is fetched because document ids are
  /// `dd-MM-yyyy`, which does not sort chronologically, so Firestore cannot
  /// range-query them. This grows with the student's history (a pre-existing
  /// characteristic of this data model, already logged as a known issue).
  Future<void> _loadDailySeries() async {
    if (widget.studentName.isEmpty) return;

    // Master Task 2026-09-11 — merged across both residence collections so
    // history filed before a residence switch still counts here. See
    // utils/SadhanaReportSource.dart's own header for the one-per-date rule.
    final merged = await fetchMergedDateReports(widget.studentName);

    final chantByDoc = <String, int>{};
    final readingByDoc = <String, int>{};

    for (final entry in merged.entries) {
      final data = entry.value;
      chantByDoc[entry.key] = _asInt(data['chantRounds']);
      readingByDoc[entry.key] = _asInt(data['bookReading']);
    }

    final now = DateTime.now();
    final chantSeries = dailySeries(valueByDocId: chantByDoc, now: now);
    final readingSeries = dailySeries(valueByDocId: readingByDoc, now: now);

    // How many days in the window actually have a report, as opposed to being
    // filled with a structural zero. A bracket derived from absent data would
    // read as a judgement about the student's chanting when it is really a
    // statement about missing paperwork.
    final lastDay = latestDayWithPossibleData(now);
    final windowDays = <String>{
      for (int i = 0; i < 30; i++)
        sadhanaDateKey(lastDay.subtract(Duration(days: i)))
    };
    var inWindow = 0;
    for (final id in chantByDoc.keys) {
      final keyDate = parseSadhanaDateKey(id);
      if (keyDate == null) continue;
      final actual = sadhanaDateKey(keyDate.subtract(const Duration(days: 1)));
      if (windowDays.contains(actual)) inWindow++;
    }

    final avg = averagePerDay(chantSeries);

    if (!mounted) return;
    setState(() {
      _chantSeries = chantSeries;
      _readingSeries = readingSeries;
      _chantAvg = avg;
      _bracket = chantingBracketFor(avg);
      _chantTrend = trendFromSeries(chantSeries);
      _readingTrend = trendFromSeries(readingSeries);
      _hasAnyReports = hasAnyReports(chantByDoc);
      _reportDaysInWindow = inWindow;
    });
  }

  Future<void> _loadAssociation() async {
    final snapshot = await (await _scopedFor('associations', 'studentUid')).get();

    final now = DateTime.now();
    final ninetyDaysAgo = now.subtract(const Duration(days: 90));

    DateTime? lastHeld;
    DateTime? nextUpcoming;
    final counts = <String, int>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = (data['status'] ?? 'unknown').toString();

      // `confirmedDate` takes precedence over `preferredDate` — the same
      // precedence `associationOverdueSince()` uses, so this card and the
      // overdue dashboard cannot disagree about which date matters.
      final rawDate = data['confirmedDate'] ?? data['preferredDate'];
      final when = rawDate is Timestamp ? rawDate.toDate() : null;

      if (when != null && when.isAfter(ninetyDaysAgo) && !when.isAfter(now)) {
        counts[status] = (counts[status] ?? 0) + 1;
      }

      if (status == 'confirmed' || status == 'completed') {
        if (when != null && !when.isAfter(now)) {
          if (lastHeld == null || when.isAfter(lastHeld)) lastHeld = when;
        }
        if (when != null && when.isAfter(now)) {
          if (nextUpcoming == null || when.isBefore(nextUpcoming)) {
            nextUpcoming = when;
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _daysSinceLastMeeting =
          lastHeld == null ? null : wholeDaysBetween(lastHeld, now);
      _nextMeeting = nextUpcoming;
      _statusCounts90d
        ..clear()
        ..addAll(counts);
    });
  }

  Future<void> _loadBooks() async {
    final snapshot = await (await _scopedFor('booksRead', 'uid')).get();

    String title = '';
    String level = '';
    String bookKey = '';

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['isCurrentBook'] == true) {
        title = (data['bookTitle'] ?? '').toString();
        level = (data['level'] ?? '').toString();
        bookKey = (data['bookKey'] ?? '').toString();
        break;
      }
    }

    int? chapter;
    if (bookKey.isNotEmpty) {
      // One extra doc get, only when there is a current book to locate.
      final bookmark = await _firestore
          .collection('bookmarks')
          .doc('${widget.studentUid}_$bookKey')
          .get();
      final raw = bookmark.data()?['chapterIndex'];
      if (raw is num) chapter = raw.toInt() + 1; // stored 0-based
    }

    if (!mounted) return;
    setState(() {
      _booksStarted = snapshot.docs.length;
      _currentBook = title;
      _currentBookLevel = level;
      _currentChapter = chapter;
    });
  }

  /// Service Bank task, Part 6 item 1 — reads the new `serviceAssignments`
  /// (real status + competence now exist), reusing [ServiceAssignment.fromDoc]
  /// rather than re-parsing the raw map a second time (Rule 1). Withdrawn
  /// assignments are excluded from the "assigned" count — they are no longer
  /// a live assignment, matching how the Service Bank's own "Assigned" tab
  /// treats them.
  ///
  /// `scorecard.totalServiceDone` is read exactly as before — a genuinely
  /// separate, unrelated counter (see the Service Bank task's own Part 1);
  /// nothing about replacing the assignment system touches it.
  Future<void> _loadService() async {
    final assignmentsSnap =
        await (await _scopedFor('serviceAssignments', 'studentUid')).get();

    var active = 0;
    var completed = 0;
    var competent = 0;
    for (final doc in assignmentsSnap.docs) {
      final a = ServiceAssignment.fromDoc(doc.id, doc.data());
      if (a.isWithdrawn) continue;
      active++;
      if (a.status == kStatusCompleted) completed++;
      if (a.competence?.level == kCompetenceYes) competent++;
    }

    var lifetime = 0;
    if (widget.studentName.isNotEmpty) {
      final scorecard =
          await _firestore.collection('scorecard').doc(widget.studentName).get();
      lifetime = _asInt(scorecard.data()?['totalServiceDone']);
    }

    if (!mounted) return;
    setState(() {
      _assignedActiveServices = active;
      _completedServices = completed;
      _competentServices = competent;
      _lifetimeServiceDone = lifetime;
    });
  }

  Future<void> _loadExpeditions() async {
    final snapshot = await (await _scopedFor('expeditionRegistrations', 'studentUid')).get();

    var reflected = 0;
    DateTime? mostRecent;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['hasReflected'] == true) reflected++;
      final raw = data['registeredAt'];
      if (raw is Timestamp) {
        final when = raw.toDate();
        if (mostRecent == null || when.isAfter(mostRecent)) mostRecent = when;
      }
    }

    if (!mounted) return;
    setState(() {
      _tripsRegistered = snapshot.docs.length;
      _reflectionsSubmitted = reflected;
      _mostRecentTrip = mostRecent;
    });
  }

  int _asInt(Object? value) => value is num ? value.toInt() : 0;

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------


  Color _directionColour(String direction) {
    switch (direction) {
      case 'improving':
        return context.g.success;
      case 'declining':
        return context.g.warning;
      default:
        return context.g.mutedText;
    }
  }

  IconData _directionIcon(String direction) {
    switch (direction) {
      case 'improving':
        return Icons.trending_up;
      case 'declining':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  /// A direction word never appears alone — the two averages it came from are
  /// always beside it, so a guide can disagree with the label.
  Widget _trendChip(TrendReading trend, String unit) {
    if (!trend.isKnown) {
      return Text(
        "not enough history for a trend",
        style: TextStyle(fontSize: 11.5, color: context.g.mutedText),
      );
    }

    return Row(
      children: [
        Icon(_directionIcon(trend.direction),
            size: 14, color: _directionColour(trend.direction)),
        const SizedBox(width: 4),
        Text(
          trend.direction,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: _directionColour(trend.direction),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            "${trend.recentAvg.toStringAsFixed(1)} vs "
            "${trend.priorAvg.toStringAsFixed(1)} $unit/day "
            "(last 14 days vs the 14 before)",
            style: TextStyle(fontSize: 11.5, color: context.g.mutedText),
          ),
        ),
      ],
    );
  }

  Widget _row({
    required String letter,
    required String label,
    required Color colour,
    required List<Widget> lines,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: colour.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: colour,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.g.text,
                  ),
                ),
                const SizedBox(height: 3),
                ...lines,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _value(String text) => Text(
        text,
        style: TextStyle(fontSize: 13.5, color: context.g.text),
      );

  Widget _muted(String text) => Text(
        text,
        style: TextStyle(fontSize: 11.5, color: context.g.mutedText),
      );

  // --- C ---------------------------------------------------------------------

  List<Widget> _chantingLines() {
    // The honest raw number always shows, even with no reports at all.
    //
    // ⚠️ Labelled "in the japa counter", NOT "lifetime", on purpose. Verified
    // against real data on 2026-08-13: a student with 16 rounds/day in their
    // sadhana reports had `lifetimeRounds == 0`, because that field is only
    // incremented by the in-app bead counter (`ChantingScreen`) and is
    // untouched by the sadhana form. Printing it as "0 rounds lifetime" beside
    // "F4 · 6.9 rounds/day" reads as a contradiction and would cost the guide
    // their trust in the whole card. Both numbers are true; they count
    // different things, so they are named differently.
    final lines = <Widget>[
      _value("${widget.lifetimeRounds} rounds banked in the in-app counter"),
    ];

    if (!_hasAnyReports) {
      lines.add(_muted("No sadhana reports submitted yet — "
          "no 30-day average, so no bracket."));
      return lines;
    }

    if (_reportDaysInWindow == 0) {
      lines.add(_muted("No reports in the last 30 days — "
          "earlier history exists, but a bracket now would be misleading."));
      return lines;
    }

    lines.add(const SizedBox(height: 4));

    // Bracket chip and the average it was derived from, side by side — the
    // label never appears without the number behind it.
    lines.add(Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: context.g.brass.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _bracket,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: context.g.brass,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "${_chantAvg.toStringAsFixed(1)} rounds/day over 30 days "
            "· $_reportDaysInWindow of 30 days reported",
            style: TextStyle(fontSize: 11.5, color: context.g.mutedText),
          ),
        ),
      ],
    ));

    // The two figures count different things, so say so when they visibly
    // disagree rather than leaving the guide to reconcile them.
    if (widget.lifetimeRounds == 0 && _chantAvg > 0) {
      lines.add(const SizedBox(height: 3));
      lines.add(_muted("The counter reads 0 because these rounds came from "
          "sadhana reports, not the in-app bead counter."));
    }

    lines.add(const SizedBox(height: 5));
    lines.add(_trendChip(_chantTrend, "rounds"));

    if (_showTrend) {
      lines.add(const SizedBox(height: 8));
      lines.add(_Sparkline(
        series: _chantSeries,
        colour: context.g.brass,
        unitLabel: "rounds",
      ));
    }
    return lines;
  }

  // --- B ---------------------------------------------------------------------

  List<Widget> _bookLines() {
    final lines = <Widget>[];

    if (_currentBook.isEmpty) {
      lines.add(_value(_booksStarted == 0
          ? "No books started yet"
          : "$_booksStarted started · none marked current"));
    } else {
      lines.add(_value(_currentBook));
      lines.add(_muted([
        if (_currentBookLevel.isNotEmpty) _currentBookLevel,
        if (_currentChapter != null)
          "at chapter $_currentChapter"
        else
          "not opened in the reader yet",
        "$_booksStarted started",
      ].join(" · ")));
    }

    if (!_hasAnyReports) {
      lines.add(const SizedBox(height: 4));
      lines.add(_muted("No reports yet, so no reading-minutes trend."));
      return lines;
    }

    lines.add(const SizedBox(height: 5));
    lines.add(_trendChip(_readingTrend, "min"));

    if (_showTrend) {
      lines.add(const SizedBox(height: 8));
      lines.add(_Sparkline(
        series: _readingSeries,
        colour: context.g.eventProgram,
        unitLabel: "min",
      ));
    }
    return lines;
  }

  // --- A ---------------------------------------------------------------------

  List<Widget> _associationLines() {
    final lines = <Widget>[];

    if (_daysSinceLastMeeting == null) {
      lines.add(_value("No meeting held yet"));
    } else if (_daysSinceLastMeeting == 0) {
      lines.add(_value("Last met today"));
    } else {
      lines.add(_value(
          "Last met $_daysSinceLastMeeting day${_daysSinceLastMeeting == 1 ? '' : 's'} ago"));
    }

    if (_statusCounts90d.isEmpty) {
      lines.add(_muted("Nothing in the last 90 days"));
    } else {
      final parts = _statusCounts90d.entries
          .map((e) => "${e.value} ${e.key}")
          .toList()
        ..sort();
      lines.add(_muted("Last 90 days: ${parts.join(', ')}"));
    }

    if (_nextMeeting != null) {
      lines.add(_muted(
          "Next: ${DateFormat('dd MMM yyyy').format(_nextMeeting!)}"));
    }
    return lines;
  }

  // --- D ---------------------------------------------------------------------

  /// Service Bank task, Part 6 item 1 — real completion status now exists
  /// (`_assignedActiveServices`/`_completedServices`/`_competentServices`,
  /// from `serviceAssignments`), so the old "completion is not tracked"
  /// caveat is removed — it would now be false. `_lifetimeServiceDone`
  /// (`scorecard.totalServiceDone`) is shown exactly as before, on its own
  /// line — a separate, unrelated counter, never blended with the
  /// assignment counts above it (matches this card's own standing "never
  /// aggregate" rule: two different D-relevant numbers, shown side by side,
  /// not summed into one).
  List<Widget> _serviceLines() {
    return [
      _value(_assignedActiveServices == 0
          ? "No services assigned"
          : "$_assignedActiveServices service${_assignedActiveServices == 1 ? '' : 's'} assigned "
              "($_completedServices completed, $_competentServices assessed competent)"),
      _muted("$_lifetimeServiceDone lifetime service points"),
    ];
  }

  // --- E ---------------------------------------------------------------------

  List<Widget> _expeditionLines() {
    if (_tripsRegistered == 0) {
      return [_value("No trips registered")];
    }
    return [
      _value(
          "$_tripsRegistered trip${_tripsRegistered == 1 ? '' : 's'} registered"),
      _muted("$_reflectionsSubmitted reflection"
          "${_reflectionsSubmitted == 1 ? '' : 's'} submitted"
          "${_mostRecentTrip == null ? '' : ' · latest ${DateFormat('dd MMM yyyy').format(_mostRecentTrip!)}'}"),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.g.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: context.g.cardShadow,
      ),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      "Some activity data could not be loaded — "
                      "what is shown below may be incomplete.",
                      style: TextStyle(
                          fontSize: 11.5, color: context.g.warning),
                    ),
                  ),
                _row(
                  letter: "A",
                  label: "ASSOCIATION",
                  colour: context.g.warning,
                  lines: _associationLines(),
                ),
                const Divider(height: 1),
                _row(
                  letter: "B",
                  label: "BOOKS",
                  colour: context.g.eventProgram,
                  lines: _bookLines(),
                ),
                const Divider(height: 1),
                _row(
                  letter: "C",
                  label: "CHANTING",
                  colour: context.g.brass,
                  lines: _chantingLines(),
                ),
                const Divider(height: 1),
                _row(
                  letter: "D",
                  label: "DEVOTIONAL SERVICE",
                  colour: context.g.danger,
                  lines: _serviceLines(),
                ),
                const Divider(height: 1),
                _row(
                  letter: "E",
                  label: "EXPEDITIONS",
                  colour: context.g.eventExam,
                  lines: _expeditionLines(),
                ),
                if (_hasAnyReports) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _showTrend = !_showTrend),
                      icon: Icon(
                        _showTrend ? Icons.expand_less : Icons.show_chart,
                        size: 18,
                      ),
                      label: Text(_showTrend
                          ? "Hide 30-day trend"
                          : "Show 30-day trend"),
                      style: TextButton.styleFrom(
                          foregroundColor: context.g.brass),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    "Activity only. These five are shown side by side, never "
                    "combined into a single score.",
                    style:
                        TextStyle(fontSize: 10.5, color: context.g.mutedText),
                  ),
                ),
              ],
            ),
    );
  }
}

/// A minimal 30-point sparkline.
///
/// A `CustomPainter` rather than a charting package: this app has no chart
/// dependency, and one bar strip does not justify adding one.
class _Sparkline extends StatelessWidget {
  final List<int> series;
  final Color colour;
  final String unitLabel;

  const _Sparkline({
    required this.series,
    required this.colour,
    required this.unitLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) return const SizedBox.shrink();

    final peak = series.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 38,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparklinePainter(
                series: series, colour: colour, zeroColour: context.g.chipBackground),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          "30 days to yesterday · peak $peak $unitLabel",
          style: TextStyle(fontSize: 10.5, color: context.g.mutedText),
        ),
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> series;
  final Color colour;
  final Color zeroColour;

  _SparklinePainter({required this.series, required this.colour, required this.zeroColour});

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    final peak = series.reduce((a, b) => a > b ? a : b);

    // An all-zero series draws a flat baseline rather than dividing by zero.
    final scale = peak == 0 ? 0.0 : size.height / peak;

    final barWidth = size.width / series.length;
    final paint = Paint()..color = colour;
    final zeroPaint = Paint()..color = zeroColour;

    for (int i = 0; i < series.length; i++) {
      final value = series[i];
      final barHeight = value * scale;

      // A zero day still gets a 2px stub, so "no practice" is visibly a day
      // rather than a gap the eye skips over.
      final height = value == 0 ? 2.0 : barHeight.clamp(2.0, size.height);

      final left = i * barWidth;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left + barWidth * .18,
            size.height - height,
            barWidth * .64,
            height,
          ),
          const Radius.circular(1.5),
        ),
        value == 0 ? zeroPaint : paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.series != series || old.colour != colour || old.zeroColour != zeroColour;
}
