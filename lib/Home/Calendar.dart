import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/ColorProvider.dart';
import '../utils/CompetitionScore.dart';
import '../utils/SadhanaReportSource.dart';
import '../utils/ScorecardPoints.dart';
import '../Pages/AllGraph.dart' show GraphicalAnalysisSection;
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideWait.dart';

class CalendarPage extends StatefulWidget {
  final String username;
  final String role;

  /// The student's Firebase Auth uid.
  ///
  /// Optional and nullable, so the existing call site keeps working if it ever
  /// cannot supply one. ⚠️ **Badges and Book Progress need it**: the sadhana
  /// collections this screen was built around are keyed by *name*, but
  /// `users/{uid}`, `booksRead.uid` and `bookmarks/{uid}_{bookKey}` are all
  /// keyed by uid. Without it those two panels explain themselves rather than
  /// silently showing nothing.
  final String? studentUid;

  CalendarPage({
    required this.username,
    required this.role,
    this.studentUid,
  });

  @override
  _CalendarPageState createState() => _CalendarPageState();
}

/// Which section is showing.
///
/// Declaration order is the display order: Calendar, Books, Points, Badges,
/// Scores. `scores` added this task — see `_scoresPanel`'s own doc comment
/// for what it shows and how it relates to the pre-existing `points`.
enum _Tab { calendar, badges, scores }

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Map<String, dynamic>? _selectedDayData;
  bool _loadingDayData = false;
  bool _datePressed = false;

  /// The calendar opens first — it is the reason this screen exists, and it was
  /// the permanently-visible section before this restructure.
  ///
  /// ⚠️ `_selectedDay`, `_selectedDayData` and `_datePressed` are State fields,
  /// so they survive a tab switch: leaving the Calendar tab and coming back
  /// keeps the selected day and its detail rather than resetting to "Select a
  /// date". That is deliberate.
  _Tab _tab = _Tab.calendar;

  // Master Task 2026-09-11 — merged across both residence collections so
  // history filed before a residence switch still shows here. See
  // utils/SadhanaReportSource.dart's own header for the one-per-date rule.
  Stream<Set<String>> _availableDatesStream() {
    return mergedAvailableDatesStream(widget.username);
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';

  Color _getDayColor(DateTime day, Set<String> availableDates) {
    String formattedDate = _formatDate(day);
    if (_selectedDay != null && isSameDay(day, _selectedDay)) return context.g.brass;
    if (availableDates.contains(formattedDate)) return context.g.success;
    return context.g.danger;
  }

  Widget _dayCellWithColor(DateTime day, Color color, double size) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 200),
      width: size,
      height: size,
      margin: EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: context.g.surface,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.4,
        ),
      ),
    );
  }

  Future<void> _fetchSelectedDayData(DateTime selectedDay) async {
    setState(() {
      _loadingDayData = true;
      _selectedDayData = null;
      _datePressed = true;
    });

    try {
      String formattedDate = _formatDate(selectedDay);
      final data = await fetchMergedDateReport(widget.username, formattedDate);

      setState(() {
        _selectedDayData = data ?? {};
        _loadingDayData = false;
      });
    } catch (e) {
      print('Error fetching day data: $e');
      setState(() {
        _selectedDayData = {};
        _loadingDayData = false;
      });
    }
  }

  Widget _infoRow(String label, String value, Color color, [double? progress]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, color: context.g.text)),
          if (progress != null)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: progress),
              duration: Duration(milliseconds: 800),
              builder: (context, valueAnim, child) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: valueAnim,
                    color: color,
                    backgroundColor: context.g.chipBackground,
                    minHeight: 8,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  /// The four-tab selector.
  ///
  /// **A horizontally-scrollable chip row, not `TabBar(isScrollable: true)`.**
  /// Two reasons, one structural and one stylistic:
  ///
  ///  * **Structural.** `TabBar` pairs with `TabBarView`, which needs a bounded
  ///    viewport height. This screen's body is a `SingleChildScrollView` with
  ///    unbounded height and four sections of wildly different lengths — a
  ///    month grid, a list that grows with every book a student starts, and two
  ///    short stat lists. Any fixed height either clips the longest or leaves
  ///    dead space under the shortest. Using `TabBar` *without* `TabBarView`
  ///    would work but then needs a `TabController` and a listener purely to
  ///    drive a `setState` this already does in one line.
  ///  * **Stylistic.** The chip row is the pattern this screen established when
  ///    Points/Badges/Books first arrived, so extending it to four keeps one
  ///    idiom rather than introducing Material tab styling alongside it.
  ///
  /// Scrollable rather than four `Expanded` chips: at four labels, equal
  /// division gets cramped on a narrow phone, and a horizontal scroll degrades
  /// gracefully instead of truncating text. `shrinkWrap`-style centring is not
  /// used — the row starts at the left edge so Calendar, the default, is always
  /// the first thing visible.
  Widget _tabRow(ColorProvider colorProvider) {
    Widget chip(String label, IconData icon, _Tab value) {
      final selected = _tab == value;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: selected
              ? context.g.brass
              : context.g.mutedText.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _tab = value),
            child: Padding(
              // Wider horizontal padding than the old equal-width chips, since
              // these size to their own content now.
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(
                children: [
                  Icon(icon,
                      size: 16,
                      color:
                          selected ? context.g.onPrimary : colorProvider.secondColor),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color:
                          selected ? context.g.onPrimary : colorProvider.secondColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
      child: Row(
        children: [
          chip('Calendar', Icons.calendar_month_outlined, _Tab.calendar),
          chip('Scores', Icons.leaderboard_outlined, _Tab.scores),
          chip('Badges', Icons.military_tech_outlined, _Tab.badges),
        ],
      ),
    );
  }

  /// The calendar and its selected-day detail — now one swappable section
  /// rather than a permanently-mounted header.
  ///
  /// ⚠️ Everything inside is **unchanged**: the same `_availableDatesStream()`,
  /// the same `TableCalendar` configuration, the same `onDaySelected` calling
  /// `_fetchSelectedDayData`, and the same divider + `_selectedDayInfo()` below
  /// it. Only its position in the tree moved.
  ///
  /// `TableCalendar` needs a bounded width but sizes its own height from the
  /// month grid, which is exactly what it did before — it sat in this same
  /// `Column` inside this same `SingleChildScrollView`. Being swapped in and out
  /// changes nothing about that; it simply mounts later.
  Widget _calendarSection(ColorProvider colorProvider, double daySize) {
    return Column(
      children: [
        // StreamBuilder for fast real-time date loading
        StreamBuilder<Set<String>>(
          stream: _availableDatesStream(),
          builder: (context, snapshot) {
            final availableDates = snapshot.data ?? {};
            return Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: TableCalendar(
                firstDay: DateTime(
                    DateTime.now().year, DateTime.now().month - 1, 1),
                lastDay: DateTime.now(),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) =>
                    _selectedDay != null && isSameDay(day, _selectedDay),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                  _fetchSelectedDayData(selectedDay);
                },
                headerStyle: HeaderStyle(
                  titleCentered: true,
                  formatButtonVisible: false,
                  leftChevronIcon: Icon(Icons.chevron_left,
                      color: colorProvider.secondColor),
                  rightChevronIcon: Icon(Icons.chevron_right,
                      color: colorProvider.secondColor),
                  titleTextStyle: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorProvider.secondColor),
                  headerPadding: EdgeInsets.symmetric(vertical: 4),
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: TextStyle(
                      color: colorProvider.secondColor,
                      fontWeight: FontWeight.w500),
                  weekendStyle: TextStyle(
                      color: colorProvider.secondColor,
                      fontWeight: FontWeight.w500),
                ),
                calendarStyle: CalendarStyle(
                  isTodayHighlighted: false,
                  cellMargin: EdgeInsets.zero,
                ),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focusedDay) =>
                      _dayCellWithColor(
                          day, _getDayColor(day, availableDates), daySize),
                  todayBuilder: (context, day, focusedDay) =>
                      _dayCellWithColor(
                          day, _getDayColor(day, availableDates), daySize),
                  selectedBuilder: (context, day, focusedDay) =>
                      _dayCellWithColor(
                          day, _getDayColor(day, availableDates), daySize),
                ),
              ),
            );
          },
        ),
        Divider(thickness: 1.5, color: context.g.border),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _selectedDayInfo(),
        ),
      ],
    );
  }

  /// Shown when a panel needs the uid and none was supplied.
  Widget _needsUid(ColorProvider colorProvider, String what) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        "$what could not be loaded for this student.",
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: context.g.mutedText),
      ),
    );
  }

  /// Weekly and monthly badge counts.
  ///
  /// Moved from `Profile.dart`'s `BadgesSection` on 2026-08-14. Same four
  /// fields on the same `users/{uid}` document (`weekly-winner`,
  /// `monthly-gold`, `monthly-silver`, `monthly-bronze`) — the profile page
  /// passed them in from a stream it already had, and this screen has no such
  /// stream, so it opens its own on that one document. **No field, collection
  /// or meaning changed; only where it is rendered.**
  Widget _badgesPanel(ColorProvider colorProvider) {
    final uid = widget.studentUid;
    if (uid == null || uid.isEmpty) return _needsUid(colorProvider, "Badges");

    return StreamBuilder<DocumentSnapshot>(
      stream: GuideDb.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: const GuideWait(compact: true),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;
        int count(dynamic v) => v is num ? v.toInt() : 0;

        final weekly = count(data?['weekly-winner']);
        final gold = count(data?['monthly-gold']);
        final silver = count(data?['monthly-silver']);
        final bronze = count(data?['monthly-bronze']);
        final total = weekly + gold + silver + bronze;

        return Padding(
          padding: const EdgeInsets.fromLTRB(3, 12, 3, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (total == 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No badges won yet 🏅',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.g.mutedText),
                  ),
                )
              else ...[
                _infoRow('Weekly Wins', '$weekly 🏆', context.g.warning),
                _infoRow('Monthly Gold', '$gold 🥇', context.g.warning),
                _infoRow('Monthly Silver', '$silver 🥈', context.g.mutedText),
                _infoRow('Monthly Bronze', '$bronze 🥉', Colors.brown.shade400),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Which books this student has started, and where they have read to.
  ///
  /// Moved from `Profile.dart`'s `BookProgressSection` on 2026-08-14. **The
  /// reads are unchanged** — `booksRead where uid ==` for the list, and
  /// `bookmarks/{uid}_{bookKey}` per book for the reading position — only the
  /// rendering is this screen's own rather than the profile card shell.
  ///
  /// ⚠️ Because the presentation had to change, those two queries now also
  /// appear here while `BookProgressSection` still holds the originals. That
  /// duplication is the cost of the visual requirement and is flagged in the
  /// progress file: if `BookProgressSection` is deleted at the next cleanup,
  /// this becomes the single definition again.

  /// Lifetime scorecard totals for this student.
  ///
  /// Moved here from `Profile.dart`'s "Total Points" section on 2026-08-14.
  /// Reads the same document — `scorecard/{name}` — which works unchanged in
  /// this context because that collection is keyed by the student's **name**,
  /// and this screen already has `widget.username`. No new query shape, no uid
  /// lookup needed.
  ///
  /// Rendered in **this screen's** visual language (the bold-coloured label
  /// over a plain value used by `_infoRow`), not the profile page's card shell,
  /// so it reads as part of this screen rather than transplanted into it.
  ///
  /// ⚠️ The "total" is the arithmetic sum of four differently-united counters
  /// — japa rounds + reading minutes + classes + services. That was already
  /// true on the profile page and is carried over unchanged, but it is not a
  /// weighted score: the app's real weighted points live in
  /// `competition/{name}.weekly.total_score`.
  Widget _totalPointsSection(ColorProvider colorProvider) {
    final name = widget.username.trim();
    if (name.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: GuideDb.instance
          .collection('scorecard')
          .doc(name)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: const GuideWait(compact: true),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;
        if (data == null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No scorecard yet 🗒️',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: context.g.mutedText),
              textAlign: TextAlign.center,
            ),
          );
        }

        // Delegates to `utils/ScorecardPoints.dart` — the same arithmetic that
        // used to be inline here, moved out on 2026-08-21 so the Guide
        // Assignment board's card face reads the identical figure instead of
        // carrying a second copy of this formula. Values are unchanged.
        final totals = ScorecardTotals.fromData(data);

        final chant = totals.chant;
        final book = totals.book;
        final sbClass = totals.sbClass;
        final service = totals.service;
        final total = totals.total;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Total Points',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorProvider.secondColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$total',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: context.g.brass,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // Same label/value rhythm as _infoRow, so these read as siblings
              // of the per-day rows below rather than a foreign card.
              _infoRow('Chanting Rounds', '$chant 📿', context.g.brass),
              _infoRow('Book Reading', '$book 📖', context.g.warning),
              _infoRow('Bhagavatam Classes', '$sbClass 🎧',
                  context.g.brass),
              _infoRow('Services Done', '$service 🙏', context.g.success),
            ],
          ),
        );
      },
    );
  }

  /// The Scores tab (this task) — every real score figure a guide might mean
  /// by "the score", clearly distinguished and never combined into one
  /// number:
  ///  * The real, weighted weekly and monthly ranking scores
  ///    (`competition/{name}`, via `utils/CompetitionScore.dart` — extracted
  ///    in an earlier task, extended this task to also read `monthly.*`).
  ///  * Total Points — the unweighted activity sum this screen's own
  ///    pre-existing `points` tab already shows (`scorecard/{name}`, via
  ///    `utils/ScorecardPoints.dart`), explicitly labelled as a raw count,
  ///    not a ranking.
  ///
  /// Reuses `_infoRow`'s label/value visual rhythm (via [_scoreHeader], a
  /// thin wrapper matching `_totalPointsSection`'s own header-row shape) and
  /// this screen's existing "missing document -> null -> dash" convention —
  /// no new computation, no new caveat wording beyond what was already
  /// established for these exact figures on `Pages/StudentProfilePage.dart`
  /// before this task removed it from there.
  ///
  /// ⚠️ **This duplicates the pre-existing `points` tab's own figure** —
  /// Total Points is shown a second time here, deliberately, so a guide
  /// comparing "the real ranking score" against "the raw activity count" can
  /// see both without switching tabs. Kept, not folded, per this task's
  /// explicit instruction not to remove `points` without the product owner's
  /// say-so. Flagged in this task's own report as an open question: fold
  /// `points` into this tab, or keep both as separate entry points to the
  /// same number.
  Widget _scoresPanel(ColorProvider colorProvider) {
    final name = widget.username.trim();
    if (name.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: GuideDb.instance
          .collection('competition')
          .doc(name)
          .snapshots(),
      builder: (context, competitionSnap) {
        if (competitionSnap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: const GuideWait(compact: true),
          );
        }

        final competitionData =
            competitionSnap.data?.data() as Map<String, dynamic>?;
        final competition = CompetitionTotals.fromSnapshotData(competitionData);

        return StreamBuilder<DocumentSnapshot>(
          stream: GuideDb.instance
              .collection('scorecard')
              .doc(name)
              .snapshots(),
          builder: (context, scorecardSnap) {
            if (scorecardSnap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child:
                    const GuideWait(compact: true),
              );
            }

            final scorecardData =
                scorecardSnap.data?.data() as Map<String, dynamic>?;
            final scorecard = ScorecardTotals.fromSnapshotData(scorecardData);

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _scoreHeader(
                    colorProvider,
                    label: "This Week's Ranking Score",
                    value: competition == null
                        ? '—'
                        : competition.weeklyTotalScore.toStringAsFixed(1),
                    valueColor: context.g.warning,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    competition == null
                        ? "No competition record yet for this name."
                        : "${competition.weeklyDaysCount} day"
                            "${competition.weeklyDaysCount == 1 ? '' : 's'} "
                            "reported this week. Japa timing, temple "
                            "attendance and sleep are all factored in. "
                            "⚠️ Resets lazily — whenever any student's app "
                            "first opens after the week turns over, not on "
                            "a fixed schedule.",
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.g.mutedText,
                      height: 1.35,
                    ),
                  ),
                  const Divider(height: 28),
                  _scoreHeader(
                    colorProvider,
                    label: "This Month's Ranking Score",
                    value: competition == null
                        ? '—'
                        : competition.monthlyTotalScore.toStringAsFixed(1),
                    valueColor: context.g.warning,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    competition == null
                        ? "No competition record yet for this name."
                        : "${competition.monthlyDaysCount} day"
                            "${competition.monthlyDaysCount == 1 ? '' : 's'} "
                            "reported this month. Same weighting as the "
                            "weekly score. ⚠️ Resets lazily too, on its own "
                            "monthly cadence, independent of the weekly "
                            "reset.",
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.g.mutedText,
                      height: 1.35,
                    ),
                  ),
                  const Divider(height: 28),
                  _scoreHeader(
                    colorProvider,
                    label: "Total Points — raw activity count, not a ranking",
                    value: scorecard == null ? '—' : '${scorecard.total}',
                    valueColor: context.g.brass,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Adds unrelated units together — japa rounds + reading "
                    "minutes + Bhagavatam classes + services done — with no "
                    "weighting between them. A lifetime activity tally, not "
                    "a comparison between students.",
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.g.mutedText,
                      height: 1.35,
                    ),
                  ),
                  // Graphical analysis — moved here from the old Folk
                  // Analysis tab's "Graphical Analysis" tile (a roster
                  // picker that then pushed this exact per-student content;
                  // see `Pages/AllGraph.dart`'s own header for the full
                  // reasoning). Placed BELOW the score cards, in its own
                  // section, deliberately not beside them — phone screens
                  // are too narrow for side-by-side charts and score cards,
                  // and this Column is already a single vertical flow, so a
                  // Row here would force everything below the fixed-width
                  // point to squeeze or wrap awkwardly. `Divider` matches
                  // the same separator already used between the three score
                  // blocks above, so this reads as a fourth block, not a
                  // bolted-on afterthought.
                  const Divider(height: 28),
                  Text(
                    "Graphical Analysis",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorProvider.secondColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GraphicalAnalysisSection(
                    username: widget.username,
                    role: widget.role,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _scoreHeader(
    ColorProvider colorProvider, {
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorProvider.secondColor,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _selectedDayInfo() {
    if (!_datePressed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Select a date to see Sadhana 📖',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: context.g.mutedText),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_loadingDayData) return const GuideWait();

    if (_selectedDayData == null || _selectedDayData!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'No data found for this date ❌',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: context.g.mutedText),
          ),
        ),
      );
    }

    Map<String, dynamic> data = _selectedDayData!;
    List<Widget> rows = [];

    void add(String label, String value, Color color, [double? progress]) {
      rows.add(_infoRow(label, value, color, progress));
    }

    if (data.containsKey('chantRounds'))
      add('Chanting Rounds', '${data['chantRounds']} 📿', context.g.brass);
    if (data.containsKey('bookReading'))
      add('Book Reading', '${data['bookReading']} 📖', context.g.warning);
    if (data.containsKey('classHearing')) {
      double progress = data['classHearing'] == 2
          ? 1.0
          : data['classHearing'] == 1
          ? 0.5
          : 0.0;
      String val = data['classHearing'] == 2
          ? "Fully ✅"
          : data['classHearing'] == 1
          ? "Partial ⚠️"
          : "Missed ❌";
      add('Class Hearing', val, context.g.success, progress);
    }
    if (data.containsKey('dailyServices')) {
      double progress = data['dailyServices'] == 2
          ? 1.0
          : data['dailyServices'] == 1
          ? 0.5
          : 0.0;
      String val = data['dailyServices'] == 2
          ? "Fully ✅"
          : data['dailyServices'] == 1
          ? "Partial ⚠️"
          : "Missed ❌";
      add('Daily Services', val, context.g.danger, progress);
    }
    if (data.containsKey('templeEntry')) {
      add('Temple Entry', '${data['templeEntry']} ⛪', context.g.mutedText);
    }
    if (data.containsKey('finishTiming')) {
      add('Finish Timing', '${data['finishTiming']} ⏰', context.g.success);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [context.g.onPrimary, context.g.chipBackground],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: context.g.mutedText.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: Offset(0, 6))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final daySize = screenWidth * 0.11;

    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return GuideScaffold(
          appBar: GuideAppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(widget.username,
                style: TextStyle(color: colorProvider.secondColor))),
          // Four equal sections, one at a time. The tab row stays put; only
          // what sits under it swaps. No navigation — every tab is a widget
          // swap inside this one screen.
          body: SingleChildScrollView(
            child: Column(
              children: [
                _tabRow(colorProvider),
                switch (_tab) {
                  _Tab.calendar => _calendarSection(colorProvider, daySize),
                  _Tab.scores => _scoresPanel(colorProvider),
                  _Tab.badges => _badgesPanel(colorProvider),
                },
              ],
            ),
          ),
        );
      },
    );
  }
}