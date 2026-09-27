import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../utils/CalendarQueries.dart';
import '../utils/ColorProvider.dart';
import '../utils/GuideRoster.dart';
import '../utils/SeenMarkers.dart';
import '../utils/Snackbar.dart';

/// Guide Calendar — text-to-dates, mandatory + personal layers (Part 5,
/// management UI). GUIDE APP ONLY; the Student app has no read path to
/// either `calendarEvents` or `calendarTextBlocks` anywhere — confirmed by
/// grep, not merely by omission.
///
/// One calendar per person (Part 4 item 4): mandatory and personal events
/// render TOGETHER here, distinguished only by a colored marker dot under
/// each day's number (blue = mandatory, orange = personal) — never by
/// separate views, since the whole point is a guide seeing their real week
/// at a glance.
///
/// `table_calendar` styling deliberately matches `Home/Calendar.dart`'s own
/// conventions (`headerStyle`/`daysOfWeekStyle`, `ColorProvider`-themed) —
/// that screen renders a student's sadhana history and is bounded to the
/// past; this one spans past AND future (a year each way), since a guide's
/// own events are naturally upcoming.
class GuideCalendarPage extends StatefulWidget {
  final String selectedGuide;

  const GuideCalendarPage({super.key, required this.selectedGuide});

  @override
  State<GuideCalendarPage> createState() => _GuideCalendarPageState();
}

class _GuideCalendarPageState extends State<GuideCalendarPage> {
  bool get _isHod => widget.selectedGuide == kHodGuideId;

  bool _loading = true;
  List<CalendarEvent> _events = [];
  List<CalendarTextBlock> _textBlocks = [];

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _loadAll();
    // Master Task 2026-09-10, Part 6 — opening this screen is "seen" for
    // mandatory calendar events.
    SeenMarkers.markSeen(widget.selectedGuide, 'calendarEvents');
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final events = await visibleEventsFor(widget.selectedGuide);
      final blocks = await visibleTextBlocksFor(widget.selectedGuide);
      if (!mounted) return;
      setState(() {
        _events = events;
        _textBlocks = blocks;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showSnackbar(
          context, "Could not load the calendar", Colors.red, Icons.error);
    }
  }

  /// Master Task Part 4 item 2 — range-aware: any day WITHIN a multi-day
  /// event's span returns that event, not just its start day. For a
  /// single-day event this is unchanged (`eventCoversDay` reduces to
  /// `day == eventDate` when there's no `endDate` — see its own doc
  /// comment), so tapping any day within a range shows/edits that event via
  /// the SAME "selected day -> event list below -> tap to edit" flow that
  /// already existed for single-day events; no new auto-open behaviour was
  /// needed.
  List<CalendarEvent> _eventsOn(DateTime day) {
    return eventsCoveringDay(_events, day)
      ..sort((a, b) => a.isMandatory == b.isMandatory
          ? 0
          : (a.isMandatory ? -1 : 1));
  }


  bool get _hasMandatoryBlock => _textBlocks.any((b) => b.isMandatory);

  // ---------------------------------------------------------------------------
  // Add text block -> extract -> MANDATORY preview -> save (Part 3)
  // ---------------------------------------------------------------------------

  /// Add mode when [editingBlock] is null (the FAB's own call site); edit
  /// mode when it's supplied (Part 5 item 6, from a history entry's edit
  /// button).
  ///
  /// Restructure task — the ENTIRE compose→extract→preview→save flow is now
  /// ONE pushed page (`_CalendarTextEntryPage`), not a bottom sheet that
  /// pops itself and pushes a separate preview route. Three real crashes in
  /// a row (duplicate GlobalKey, `debugNeedsLayout`, `_dependents.isEmpty`)
  /// all traced back to the SAME structural cause: a modal-sheet route
  /// being popped and a new page route being pushed across the SAME
  /// Navigator/Overlay in close succession, with per-item
  /// `TextEditingController`s and `EditableText` widgets straddling that
  /// transition. Patching each symptom kept producing a new one because the
  /// transition itself — not any one widget in it — was the problem. Moving
  /// both stages onto ONE page removes the transition: there is exactly one
  /// `Navigator.push` (opening this method) and exactly one `Navigator.pop`
  /// (this method's own return, once saving is fully done) — nothing pops
  /// and pushes in between; moving from "compose" to "preview" is a plain
  /// `setState` inside a single, continuously-mounted route.
  Future<void> _openTextEntryPage({CalendarTextBlock? editingBlock}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _CalendarTextEntryPage(
          editingBlock: editingBlock,
          submittedBy: widget.selectedGuide,
          submittedByIsHod: _isHod,
        ),
      ),
    );
    if (saved == true) {
      await _loadAll();
    }
  }

  // ---------------------------------------------------------------------------
  // Edit a single event in place (Part 5 item 4)
  // ---------------------------------------------------------------------------

  bool _canMutate(CalendarEvent e) => _isHod || !e.isMandatory;

  Future<void> _openEditEventDialog(CalendarEvent event) async {
    if (!_canMutate(event)) return;

    final titleController = TextEditingController(text: event.title);
    final noteController = TextEditingController(text: event.note);
    DateTime date = event.eventDate;
    // Master Task Part 4 item 3 — pre-filled from this event's own current
    // range/type, so a guide never has to go back to the text to fix
    // either.
    DateTime? endDate = event.endDate;
    String type = event.type;
    // Part 8 item 3 — pre-filled from this event's OWN current selection
    // (already defaulted to `kDefaultNotifyOffsets` by
    // `CalendarEvent.fromDoc` if it predates this field).
    List<String> notifyOffsets = List<String>.from(event.notifyOffsets);

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isRange = endDate != null;
            return AlertDialog(
              title: const Text("Edit event"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event, color: Colors.blue),
                      title: Text(isRange
                          ? "${DateFormat('dd MMM yyyy').format(date)} "
                              "(start)"
                          : DateFormat('dd MMM yyyy').format(date)),
                      trailing: const Icon(Icons.edit, size: 18),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: date,
                          firstDate:
                              DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            date = picked;
                            // Keep the range valid by construction if the
                            // start is dragged past the current end,
                            // rather than letting the dialog momentarily
                            // hold an invalid range.
                            if (endDate != null && endDate!.isBefore(date)) {
                              endDate = date;
                            }
                          });
                        }
                      },
                    ),
                    // Master Task Part 4 item 3 — range toggle + end-date
                    // picker, same pattern as the start date above.
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text("Spans multiple days",
                          style: TextStyle(fontSize: 13.5)),
                      value: isRange,
                      onChanged: (v) => setDialogState(() {
                        endDate = v ? date : null;
                      }),
                    ),
                    if (isRange)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            const Icon(Icons.event, color: Colors.transparent),
                        title: Text(
                            "${DateFormat('dd MMM yyyy').format(endDate!)} "
                            "(end)"),
                        trailing: const Icon(Icons.edit, size: 18),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: endDate!,
                            firstDate: date,
                            lastDate:
                                DateTime.now().add(const Duration(days: 730)),
                          );
                          if (picked != null) {
                            setDialogState(() => endDate = picked);
                          }
                        },
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: "Title"),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      minLines: 2,
                      decoration: const InputDecoration(labelText: "Note"),
                    ),
                    const SizedBox(height: 12),
                    _EventTypePicker(
                      selected: type,
                      onChanged: (updated) =>
                          setDialogState(() => type = updated),
                    ),
                    const SizedBox(height: 12),
                    _NotifyOffsetsPicker(
                      selected: notifyOffsets,
                      onChanged: (updated) =>
                          setDialogState(() => notifyOffsets = updated),
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
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) return;

    try {
      await editEvent(
        eventId: event.id,
        eventDate: date,
        endDate: endDate,
        type: type,
        title: titleController.text.trim(),
        note: noteController.text.trim(),
        editedBy: widget.selectedGuide,
        actingIsHod: _isHod,
        notifyOffsets: notifyOffsets,
      );
      await _loadAll();
      if (!mounted) return;
      showSnackbar(context, "Event updated", Colors.green, Icons.check_circle);
    } on InvalidEventRangeError catch (e) {
      if (!mounted) return;
      showSnackbar(context, e.message, Colors.red, Icons.error);
    } on MandatoryEventPermissionError catch (e) {
      if (!mounted) return;
      showSnackbar(context, e.message, Colors.red, Icons.error);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, "Could not save the change", Colors.red, Icons.error);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  /// Day-row-clipping fix — matches `Home/Calendar.dart`'s own approach
  /// exactly, rather than table_calendar's built-in default cell.
  ///
  /// The real cause: table_calendar's own default cell (used whenever no
  /// `defaultBuilder`/`todayBuilder`/`selectedBuilder` is supplied, which
  /// this screen didn't do before this fix) renders the day number with
  /// `calendarStyle.defaultTextStyle`, whose own package default is a bare
  /// `TextStyle()` — no explicit `fontSize` at all. That inherits this
  /// app's OWN ambient Material 3 theme text size (`main.dart`'s
  /// `ThemeData(useMaterial3: true, ...)`, no `textTheme` override), which
  /// is larger than the 52px default row can comfortably fit once its 6px
  /// top+bottom `cellMargin` is subtracted — real vertical clipping of the
  /// glyphs, not a cosmetic sizing choice. `Home/Calendar.dart` never hits
  /// this because it never uses table_calendar's default cell at all — it
  /// supplies its own builders with an EXPLICIT, cell-size-derived
  /// `fontSize` (`size * 0.4`), immune to ambient theme inheritance by
  /// construction. This does the same here, computing the identical
  /// `daySize` ratio (`screenWidth * 0.11`) that screen uses.
  ///
  /// Confirmed independent of the marker dots: table_calendar composes
  /// `markerBuilder`'s returned widget as a SEPARATE sibling in the same
  /// per-day `Stack` regardless of which builder drew the base cell
  /// (`table_calendar.dart`'s own `_buildCell`, read directly) — so the
  /// existing `markerBuilder` below needs no change at all.
  /// table_calendar's own documented default (`rowHeight = 52.0`), never
  /// overridden anywhere in this screen — used as a KNOWN CONSTANT for band
  /// stacking below rather than measured via a `LayoutBuilder`. Confirmed
  /// against the installed package source (`table_calendar.dart`), not
  /// assumed.
  static const double _kCalendarRowHeight = 52.0;

  /// Calendar UI redesign, Part 1 — a range renders as a visually
  /// CONTINUOUS band across its days, not per-cell shading (the previous,
  /// weaker treatment this replaces). Structural alignment, guaranteed
  /// without a device (item 2): every day cell in a row receives the exact
  /// same [cellWidth] (`build()`'s own `(screenWidth - 24) / 7` — 24 being
  /// this screen's own known, fixed horizontal padding: the
  /// `SingleChildScrollView`'s `12` each side; verified against the actual
  /// padding values in `build()`, and `table_calendar`'s own
  /// `tablePadding` defaults to `EdgeInsets.zero`, confirmed from its
  /// source, so no further inset is hiding between the grid and that
  /// figure). A MIDDLE day's band is drawn at the CELL's FULL width (zero
  /// horizontal margin), so two adjacent middle-day bands meet exactly at
  /// the shared cell boundary — neither a gap nor an overlap is possible,
  /// because both cells report the identical `cellWidth` by construction,
  /// not by tuning. A START/END day's band uses HALF that width, measured
  /// from the cell's own centre outward (`EdgeInsetsDirectional` margin of
  /// `cellWidth * 0.5` on the side that doesn't continue) — the exact
  /// geometry table_calendar's OWN built-in range-highlight uses internally
  /// (`table_calendar.dart`'s `_buildCell`, read directly from the
  /// installed package source), adapted here because that built-in
  /// mechanism (`rangeStartDay`/`rangeEndDay`) is a single, interactively-
  /// selected range — this screen needs many simultaneous, persistent,
  /// per-event ranges, which that single-range API cannot express, so the
  /// SAME proven geometry is reproduced by hand for each event.
  ///
  /// Rounding (item 1's "rounded on the first/last day of each week row,
  /// flat where it continues into the next row") reduces to one simple
  /// per-cell rule once you work through what that means at a row
  /// boundary: round the LEFT edge only where nothing continues in from
  /// the left — i.e. only on the event's TRUE start day; round the RIGHT
  /// edge only on its TRUE end day. A day that merely happens to be a
  /// row's first/last day (Sunday/Saturday) while the range continues past
  /// it gets NO rounding on that side, which is exactly "flat where it
  /// continues into the next row" — the row-boundary framing in the
  /// requirement describes the visual RESULT of this rule, not a separate
  /// computation.
  ///
  /// Contrast (item 3): band colours ([kRangeColorByType]) and the day
  /// number's colour on top of one ([kRangeBandTextColor]) are both FIXED,
  /// independent of [ColorProvider]'s light/dark state — see that
  /// constant's own doc comment for the actual measured contrast ratios.
  Widget _dayCell(
    DateTime day,
    double cellWidth, {
    bool selected = false,
    bool isToday = false,
  }) {
    final ranges = _events.where((e) => e.isMultiDay && eventCoversDay(e, day)).toList()
      ..sort((a, b) {
        final byStart = a.eventDate.compareTo(b.eventDate);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    final hasRange = ranges.isNotEmpty;
    final circleSize = cellWidth * 0.8;

    final circle = Container(
      width: circleSize,
      height: circleSize,
      decoration: BoxDecoration(
        color: selected
            ? Colors.indigo.shade400
            : (isToday && !hasRange ? Colors.indigo.shade100 : null),
        shape: BoxShape.circle,
        // "Today" still needs to read clearly when it also falls inside a
        // range — an outline rather than a filled tint, so the band colour
        // underneath stays visible instead of being muddied by two
        // overlapping fills.
        border: isToday && !selected && hasRange
            ? Border.all(color: Colors.indigo.shade400, width: 1.6)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: selected
              ? Colors.white
              : hasRange
                  ? kRangeBandTextColor
                  : Colors.black87,
          fontWeight: selected || isToday ? FontWeight.w700 : FontWeight.w500,
          fontSize: circleSize * 0.42,
        ),
      ),
    );

    if (!hasRange) {
      return Center(child: circle);
    }

    // Part 2 item 2 — overlapping ranges: stacked thin bands (see
    // `_rangeBand`'s own doc comment for why, over a horizontal split).
    // Capped at 3 simultaneous bands for legibility; any further overlap
    // is surfaced as a small "+N" badge rather than silently dropped.
    final shown = ranges.take(3).toList();
    const bandZoneHeight = 40.0; // comfortably inside the 52.0 row height
    final bandHeight = bandZoneHeight / shown.length;
    final bandTop = (_kCalendarRowHeight - bandZoneHeight) / 2;

    return SizedBox(
      width: cellWidth,
      height: _kCalendarRowHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              top: bandTop + i * bandHeight,
              left: 0,
              right: 0,
              height: bandHeight,
              child: _rangeBand(shown[i], day, cellWidth, bandHeight),
            ),
          circle,
          if (ranges.length > shown.length)
            Positioned(
              right: cellWidth * 0.02,
              bottom: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '+${ranges.length - shown.length}',
                  style: const TextStyle(
                      fontSize: 8, color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One event's own band segment for [day] — see `_dayCell`'s own doc
  /// comment for the full alignment/rounding reasoning; this is just the
  /// per-event geometry that makes it work.
  Widget _rangeBand(
      CalendarEvent event, DateTime day, double cellWidth, double bandHeight) {
    final isStart = isSameDay(day, event.eventDate);
    final isEnd = isSameDay(day, event.effectiveEndDate);
    // A cap radius of half the band's OWN height — a true semicircle end,
    // scaling correctly whether this is the only band in the cell or one
    // of several thin stacked ones.
    final capRadius = Radius.circular(bandHeight / 2);

    return Container(
      margin: EdgeInsetsDirectional.only(
        start: isStart ? cellWidth * 0.5 : 0,
        end: isEnd ? cellWidth * 0.5 : 0,
      ),
      decoration: BoxDecoration(
        // Range-extraction bug fix task, Part 4 — colour by TYPE now, not
        // per-event id, so the colour itself carries meaning (exam/
        // festival/program/other). Two overlapping ranges of the SAME
        // type look identical in colour — the stacked-band treatment
        // above (capped at 3, "+N" beyond that — see `_dayCell`) is what
        // keeps THOSE separable, unchanged by this switch.
        color: rangeColorForType(event.type),
        borderRadius: BorderRadius.horizontal(
          left: isStart ? capRadius : Radius.zero,
          right: isEnd ? capRadius : Radius.zero,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Same ratio `Home/Calendar.dart` uses for its own day cells — kept
    // for the days-of-week header sizing only (`daysOfWeekHeight`/its own
    // font size below), unrelated to and unchanged by this task.
    final daySize = MediaQuery.of(context).size.width * 0.11;
    // Calendar UI redesign, Part 1 item 2 — the TRUE per-day-column width,
    // used for range-band alignment. `24` is this screen's own known
    // horizontal padding around the calendar (`SingleChildScrollView`'s
    // `12` each side, below) plus `table_calendar`'s own `tablePadding`
    // default of `EdgeInsets.zero` (confirmed from the installed package
    // source) — not a guess. See `_dayCell`'s own doc comment for why this
    // is what guarantees adjacent cells' bands meet with no gap.
    final cellWidth = (MediaQuery.of(context).size.width - 24) / 7;

    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            backgroundColor: colorProvider.color,
            elevation: 0,
            iconTheme: IconThemeData(color: colorProvider.secondColor),
            title: Text("Calendar",
                style: TextStyle(
                    color: colorProvider.secondColor,
                    fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: Icon(Icons.history, color: colorProvider.secondColor),
                tooltip: "Text history",
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _TextBlockHistoryPage(
                        selectedGuide: widget.selectedGuide,
                        isHod: _isHod,
                        textBlocks: _textBlocks,
                        events: _events,
                        onChanged: _loadAll,
                        onEditRequested: (b) =>
                            _openTextEntryPage(editingBlock: b),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: Colors.blue,
            onPressed: _openTextEntryPage,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text("Add text", style: TextStyle(color: Colors.white)),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Part 5 item 5 — empty state.
                      if (!_hasMandatoryBlock && !_isHod)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            "Your HOD hasn't set up the shared calendar yet. "
                            "You can still add your own personal events "
                            "below.",
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      _legend(colorProvider),
                      // Part 4 item 2 — same 12px step used between the
                      // calendar card and the today panel below, rather
                      // than a smaller, one-off value here.
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: TableCalendar<CalendarEvent>(
                          firstDay:
                              DateTime.now().subtract(const Duration(days: 365)),
                          lastDay:
                              DateTime.now().add(const Duration(days: 365)),
                          focusedDay: _focusedDay,
                          selectedDayPredicate: (day) =>
                              _selectedDay != null && isSameDay(day, _selectedDay),
                          onDaySelected: (selectedDay, focusedDay) {
                            setState(() {
                              _selectedDay = selectedDay;
                              _focusedDay = focusedDay;
                            });
                          },
                          onPageChanged: (focusedDay) {
                            _focusedDay = focusedDay;
                          },
                          eventLoader: _eventsOn,
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
                            headerPadding: const EdgeInsets.symmetric(vertical: 4),
                          ),
                          daysOfWeekStyle: DaysOfWeekStyle(
                            weekdayStyle: TextStyle(
                                color: colorProvider.secondColor,
                                fontWeight: FontWeight.w500),
                            weekendStyle: TextStyle(
                                color: colorProvider.secondColor,
                                fontWeight: FontWeight.w500),
                          ),
                          // Weekday header clipping fix (Part 3) — same bug
                          // class, same fix shape as `_dayCell` below: the
                          // package's own default dow text (used above via
                          // `daysOfWeekStyle`) has no explicit fontSize, so
                          // it inherits this app's Material 3 theme font,
                          // too tall for the 16.0-default `daysOfWeekHeight`
                          // it's boxed into (`calendar_core.dart` wraps the
                          // dow builder's returned widget in
                          // `SizedBox(height: dowHeight)`). Both
                          // `daysOfWeekHeight` below and this builder's
                          // `fontSize` are derived from the SAME `daySize`
                          // the day cells already use, so header and grid
                          // scale together at any calendar size instead of
                          // being two independently-tuned numbers.
                          daysOfWeekHeight: daySize * 0.6,
                          calendarStyle: const CalendarStyle(
                            // Matches `Home/Calendar.dart`'s own value —
                            // moot for the three states below (a custom
                            // `defaultBuilder`/`todayBuilder`/`selectedBuilder`
                            // bypasses `cellMargin` entirely, per
                            // `cell_content.dart`'s own logic), kept for
                            // consistency rather than left at the
                            // package's differing default.
                            cellMargin: EdgeInsets.zero,
                            markersMaxCount: 2,
                            markerDecoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                            markerSizeScale: 0.16,
                          ),
                          calendarBuilders: CalendarBuilders(
                            dowBuilder: (context, day) {
                              // Replicates the package's own default dow
                              // rendering (`table_calendar.dart`'s
                              // `dowBuilder` fallback) exactly — same
                              // `DateFormat.E` label — only adding the
                              // explicit, daySize-derived `fontSize`
                              // neither `weekdayStyle` nor `weekendStyle`
                              // above sets. Both styles above are already
                              // identical in this file (same color, same
                              // weight), so no weekend/weekday branch is
                              // needed here to match them.
                              final weekdayString =
                                  DateFormat.E().format(day);
                              return Center(
                                child: ExcludeSemantics(
                                  child: Text(
                                    weekdayString,
                                    style: TextStyle(
                                      color: colorProvider.secondColor,
                                      fontWeight: FontWeight.w500,
                                      fontSize: daySize * 0.32,
                                    ),
                                  ),
                                ),
                              );
                            },
                            defaultBuilder: (context, day, focusedDay) =>
                                _dayCell(day, cellWidth),
                            todayBuilder: (context, day, focusedDay) =>
                                _dayCell(day, cellWidth, isToday: true),
                            selectedBuilder: (context, day, focusedDay) =>
                                _dayCell(day, cellWidth, selected: true),
                            // Part 2 item 3 — single-day events keep the
                            // dot treatment; a multi-day event now has its
                            // own band instead (drawn in `_dayCell`), so it
                            // is excluded here to avoid showing both at
                            // once for the same event.
                            markerBuilder: (context, day, dayEvents) {
                              final singleDay =
                                  dayEvents.where((e) => !e.isMultiDay);
                              final hasMandatory =
                                  singleDay.any((e) => e.isMandatory);
                              final hasPersonal =
                                  singleDay.any((e) => !e.isMandatory);
                              if (!hasMandatory && !hasPersonal) return null;
                              return Positioned(
                                bottom: 2,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (hasMandatory) _dot(Colors.indigo),
                                    if (hasMandatory && hasPersonal)
                                      const SizedBox(width: 3),
                                    if (hasPersonal) _dot(Colors.orange),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _todayPanel(),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _dot(Color color) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  /// Part 2 item 3 — explains bands as well as dots. `Wrap`, not `Row`, so
  /// the added third entry can never overflow horizontally on a narrow
  /// phone (Part 5 item 4) — it simply wraps to a second line instead.
  Widget _legend(ColorProvider colorProvider) {
    Widget entry(Widget swatch, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          swatch,
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: 12, color: colorProvider.secondColor)),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          entry(_dot(Colors.indigo), "Mandatory"),
          entry(_dot(Colors.orange), "Personal"),
          // Range-extraction bug fix task, Part 4 item 4 — one swatch per
          // TYPE now, replacing the old single "own colour per range"
          // line, since colour now means type rather than event identity.
          for (final type in kEventTypes)
            entry(_bandSwatch(rangeColorForType(type)), kEventTypeLabels[type]!),
        ],
      ),
    );
  }

  Widget _bandSwatch(Color color) => Container(
        width: 16,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      );

  /// Calendar UI redesign, Part 3 — the "today panel." Shows what needs
  /// doing on the SELECTED day (item 2), defaulting to today (`initState`
  /// sets `_selectedDay = DateTime.now()`); tapping another date on the
  /// calendar above updates `_selectedDay` (`onDaySelected`, unchanged)
  /// and this panel rebuilds for it. The heading states which day is
  /// shown unambiguously — "Today" specifically when it is, never "Today"
  /// for some other date (item 2).
  ///
  /// Content, in order (item 3): calendar events on that day — including
  /// any range covering it, via the already range-aware `_eventsOn`.
  ///
  /// Master Task Part 5 item 1 — the missing-reports section that used to
  /// live here has been removed; that surface moved to its own
  /// "Submissions" tile on the Other Tasks tab (`BoysDetails.dart`), which
  /// opens the two-group `SubmissionStatusPage` instead. This panel is
  /// calendar events only again.
  ///
  /// A calm, explicit empty state when nothing is due at all (item 5).
  Widget _todayPanel() {
    final day = _selectedDay;
    if (day == null) return const SizedBox.shrink();

    final events = _eventsOn(day);
    final isToday = isSameDay(day, DateTime.now());
    final nothingDue = events.isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Part 4 item 1 — a real step up from body text (size AND
          // weight), not a colour change.
          Text(
            isToday ? "Today" : DateFormat('EEEE, dd MMM').format(day),
            style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Colors.black87),
          ),
          if (!isToday) ...[
            const SizedBox(height: 2),
            Text(
              DateFormat('dd MMM yyyy').format(day),
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 16),
          if (nothingDue)
            _emptyDayState()
          else ...[
            _panelSubHeader("EVENTS"),
            const SizedBox(height: 8),
            ...events.map((e) => _eventTile(e)),
          ],
        ],
      ),
    );
  }

  Widget _panelSubHeader(String text) {
    return Text(
      text,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: Colors.grey.shade600),
    );
  }

  Widget _emptyDayState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Text("Nothing due",
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _eventTile(CalendarEvent e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: e.isMandatory ? Colors.indigo.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(e.isMandatory ? Icons.campaign : Icons.person,
              size: 16,
              color: e.isMandatory ? Colors.indigo : Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(e.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13.5)),
                    ),
                    // Master Task Part 2 — the type badge; Part 4 — the
                    // range span, so a guide sees both without opening the
                    // edit dialog.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        kEventTypeLabels[e.type] ?? e.type,
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (e.isMultiDay) ...[
                  const SizedBox(height: 2),
                  Text(
                    "${DateFormat('dd MMM').format(e.eventDate)} – "
                    "${DateFormat('dd MMM yyyy').format(e.effectiveEndDate)}",
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700),
                  ),
                ],
                if (e.note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(e.note,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ],
              ],
            ),
          ),
          if (_canMutate(e))
            IconButton(
              icon: const Icon(Icons.edit, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _openEditEventDialog(e),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Text entry + preview — ONE page, ONE route (restructure task)
// -----------------------------------------------------------------------------
//
// Replaces the old bottom-sheet-that-pops-then-pushes-a-preview-page
// structure entirely. See `_openTextEntryPage`'s own doc comment (above, in
// `_GuideCalendarPageState`) for why: three real crashes in a row all traced
// to that SAME pop-then-push transition, not to any one widget in it.
//
// This page has exactly two internal stages (`_Stage.compose`,
// `_Stage.preview`), switched with a plain `setState` — never a
// `Navigator.pop`/`push`. The ONLY `Navigator.pop` in this whole class is at
// the very end of `_save()`, once saving has fully succeeded, popping THIS
// page back to whoever pushed it (`_GuideCalendarPageState._openTextEntryPage`,
// which awaits exactly that one pop). Confirmed by construction: grep this
// class for `Navigator.` — the sole hit is that one `Navigator.pop` in
// `_save()`. Nothing between tapping "Extract dates" and the preview UI
// appearing ever touches the Navigator at all.
class _CalendarTextEntryPage extends StatefulWidget {
  final CalendarTextBlock? editingBlock;
  final String submittedBy;
  final bool submittedByIsHod;

  const _CalendarTextEntryPage({
    required this.editingBlock,
    required this.submittedBy,
    required this.submittedByIsHod,
  });

  @override
  State<_CalendarTextEntryPage> createState() =>
      _CalendarTextEntryPageState();
}

enum _Stage { compose, preview }

class _CalendarTextEntryPageState extends State<_CalendarTextEntryPage> {
  bool get _isEditing => widget.editingBlock != null;

  _Stage _stage = _Stage.compose;

  // ---- compose-stage state ----
  late final TextEditingController _textController;
  late String _scope;
  bool _busy = false;

  // ---- preview-stage state (populated once extraction succeeds) ----
  List<ParsedCalendarEvent> _events = [];
  List<TextEditingController> _titleControllers = [];
  List<TextEditingController> _noteControllers = [];
  bool _saving = false;
  // Part 8 item 3 — the preview's ONE shared notify-offsets control; applied
  // to every `ParsedCalendarEvent` in `_events` whenever it changes. Each
  // event still carries its own `notifyOffsets` (set to
  // `kDefaultNotifyOffsets` by its own constructor default when first
  // parsed), so this just starts them all in sync.
  List<String> _sharedNotifyOffsets = List<String>.from(kDefaultNotifyOffsets);

  @override
  void initState() {
    super.initState();
    _textController =
        TextEditingController(text: widget.editingBlock?.rawText);
    _scope = widget.editingBlock?.scope ?? kScopePersonal;
  }

  @override
  void dispose() {
    _textController.dispose();
    _disposePreviewControllers();
    super.dispose();
  }

  void _disposePreviewControllers() {
    for (final c in _titleControllers) {
      c.dispose();
    }
    for (final c in _noteControllers) {
      c.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Compose stage
  // ---------------------------------------------------------------------------

  Future<void> _extract() async {
    // Duplicate-GlobalKey crash fix, still relevant here — re-entrancy
    // guard. The button below is `onPressed: _busy ? null : _extract`,
    // which only disables on the NEXT rebuild, leaving a narrow window for
    // a rapid double-tap to invoke `_extract()` twice concurrently.
    if (_busy) return;

    final raw = _textController.text.trim();
    if (raw.isEmpty) {
      showSnackbar(context, "Paste some text first", Colors.orange, Icons.info);
      return;
    }

    // Loading-indicator visibility fix — unfocus explicitly, in its own
    // uncontested step, before the busy-state rebuild that shows the
    // spinner, so keyboard-dismissal (its own multi-frame animation) isn't
    // competing with that rebuild for the same frames.
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    List<ParsedCalendarEvent> parsed;
    try {
      parsed = await extractCalendarEventsFromText(raw);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnackbar(
          context,
          "Could not extract dates — the request may have timed out. "
          "Please try again.",
          Colors.red,
          Icons.error);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (parsed.isEmpty) {
      showSnackbar(context,
          "No dates found in that text — try adding a clearer date",
          Colors.orange, Icons.info);
      return;
    }

    // Move to the preview stage — a plain `setState`, not a route change.
    // This is the transition that used to be `Navigator.pop(sheetContext)`
    // followed by `Navigator.push(...)`; now it is nothing more than
    // rebuilding this same, continuously-mounted page with new state.
    _disposePreviewControllers();
    final events = parsed;
    setState(() {
      _events = events;
      _titleControllers =
          events.map((e) => TextEditingController(text: e.title)).toList();
      _noteControllers =
          events.map((e) => TextEditingController(text: e.note)).toList();
      _stage = _Stage.preview;
    });
  }

  Widget _buildComposeStage() {
    final editingBlock = widget.editingBlock;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing
                  ? "Edit the text below and re-extract — this REPLACES "
                      "this block's existing events with the newly parsed "
                      "ones; nothing is duplicated."
                  : "Paste text with dates and titles — AI will pull out "
                      "the events. You'll see exactly what was parsed "
                      "before anything is saved.",
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            // Scope picker only in ADD mode — an edit keeps the block's
            // existing scope fixed ([updateTextBlockWithEvents] re-reads
            // scope fresh from Firestore regardless, so this is a
            // display-only lock, not the real enforcement).
            if (editingBlock != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: editingBlock.isMandatory
                      ? Colors.indigo.shade50
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  editingBlock.isMandatory
                      ? "Editing a MANDATORY block — visible to every guide."
                      : "Editing a personal block — only you can see it.",
                  style: const TextStyle(fontSize: 12),
                ),
              )
            else if (widget.submittedByIsHod) ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: kScopeMandatory,
                      label: Text("Mandatory (all guides)"),
                      icon: Icon(Icons.campaign, size: 16)),
                  ButtonSegment(
                      value: kScopePersonal,
                      label: Text("Personal (only me)"),
                      icon: Icon(Icons.person, size: 16)),
                ],
                selected: {_scope},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() => _scope = s.first),
              ),
              const SizedBox(height: 12),
            ] else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  "This will be saved to your own personal calendar — only "
                  "you will see it.",
                  style: TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              enabled: !_busy,
              maxLines: 10,
              minLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText:
                    "e.g. Janmashtami on 15th August — students fasting "
                    "till midnight, busy from 4pm. Guru Purnima 19th "
                    "July...",
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Center(
                  child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              ))
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _extract,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text("Extract dates"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Preview stage
  // ---------------------------------------------------------------------------

  Future<void> _pickDate(int index) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _events[index].date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() {
        _events[index].date = picked;
        // Keep the range valid by construction if the start is dragged
        // past the current end.
        final end = _events[index].endDate;
        if (end != null && end.isBefore(picked)) {
          _events[index].endDate = picked;
        }
      });
    }
  }

  /// Master Task Part 1 item 3 — end-date picker for the preview's own
  /// range toggle, same "keep it valid by construction" reasoning as
  /// [_pickDate] above.
  Future<void> _pickEndDate(int index) async {
    final start = _events[index].date;
    final picked = await showDatePicker(
      context: context,
      initialDate: _events[index].endDate ?? start,
      firstDate: start,
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => _events[index].endDate = picked);
    }
  }

  void _toggleRange(int index, bool isRange) {
    setState(() {
      _events[index].endDate = isRange ? _events[index].date : null;
    });
  }

  Future<void> _save() async {
    // Same re-entrancy guard as `_extract()` above — the "Save to
    // calendar" button relies on `onPressed: _saving ? null : _save`,
    // which only disables on the NEXT rebuild.
    if (_saving) return;
    final toSave = _events.where((e) => e.include).toList();
    if (toSave.isEmpty) {
      showSnackbar(context, "Nothing selected to save", Colors.orange, Icons.info);
      return;
    }
    setState(() => _saving = true);
    try {
      final rawText = _textController.text.trim();
      final editingBlock = widget.editingBlock;
      if (editingBlock != null) {
        // Edit flow (Part 5 item 6) — REPLACES the block's existing events
        // rather than creating a second block/set; see
        // [updateTextBlockWithEvents]'s own doc comment for the atomicity
        // guarantee against orphaned events.
        await updateTextBlockWithEvents(
          blockId: editingBlock.id,
          rawText: rawText,
          editedBy: widget.submittedBy,
          actingIsHod: widget.submittedByIsHod,
          parsedEvents: _events,
        );
      } else {
        await saveTextBlockWithEvents(
          rawText: rawText,
          submittedBy: widget.submittedBy,
          submittedByIsHod: widget.submittedByIsHod,
          scope: _scope,
          ownerGuideId: _scope == kScopeMandatory ? null : widget.submittedBy,
          parsedEvents: _events,
        );
      }
      // The ONE Navigator.pop in this entire page — this route's own,
      // popping back to `_openTextEntryPage`'s caller, once saving is
      // fully done. Nothing is popped or pushed at any other point.
      if (!mounted) return;
      Navigator.pop(context, true);
    } on MandatoryEventPermissionError catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      showSnackbar(context, e.message, Colors.red, Icons.error);
    } catch (_) {
      setState(() => _saving = false);
      if (!mounted) return;
      showSnackbar(context, "Could not save", Colors.red, Icons.error);
    }
  }

  Widget _buildPreviewStage() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.blue.shade50,
          padding: const EdgeInsets.all(12),
          child: const Text(
            "Check every date, title and note below before saving — a "
            "misread date becomes a wrong reminder weeks from now with no "
            "way to trace it back.",
            style: TextStyle(fontSize: 12.5),
          ),
        ),
        // Part 8 item 3 — ONE shared control for the whole paste, rather
        // than needing per-event edits afterward (per-event fine-tuning is
        // still available later from the calendar view's own edit dialog).
        // Applies immediately to every event currently in `_events`.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: _NotifyOffsetsPicker(
            selected: _sharedNotifyOffsets,
            onChanged: (updated) {
              setState(() {
                _sharedNotifyOffsets = updated;
                for (final e in _events) {
                  e.notifyOffsets = List<String>.from(updated);
                }
              });
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: _events.length,
            itemBuilder: (context, i) {
              final e = _events[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: e.include,
                            onChanged: (v) =>
                                setState(() => e.include = v ?? true),
                          ),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () => _pickDate(i),
                              icon: const Icon(Icons.event, size: 16),
                              label: Text(
                                  DateFormat('dd MMM yyyy').format(e.date)),
                            ),
                          ),
                        ],
                      ),
                      // Master Task Part 1/4 — range toggle + end-date
                      // picker, same shape as the calendar view's own edit
                      // dialog, so a multi-day event never needs a
                      // round-trip through the raw text to fix.
                      Row(
                        children: [
                          const SizedBox(width: 48),
                          Expanded(
                            child: Row(
                              children: [
                                Text("Spans multiple days",
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.grey.shade700)),
                                const Spacer(),
                                Switch(
                                  value: e.endDate != null,
                                  onChanged: (v) => _toggleRange(i, v),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (e.endDate != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 48),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _pickEndDate(i),
                              icon: const Icon(Icons.event, size: 16),
                              label: Text("ends "
                                  "${DateFormat('dd MMM yyyy').format(e.endDate!)}"),
                            ),
                          ),
                        ),
                      TextField(
                        controller: _titleControllers[i],
                        decoration: const InputDecoration(labelText: "Title"),
                        onChanged: (v) => e.title = v,
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _noteControllers[i],
                        maxLines: 2,
                        minLines: 1,
                        decoration: const InputDecoration(labelText: "Note"),
                        onChanged: (v) => e.note = v,
                      ),
                      const SizedBox(height: 8),
                      // Master Task Part 2 item 4 — AI's inferred guess,
                      // correctable right here before saving.
                      _EventTypePicker(
                        selected: e.type,
                        onChanged: (updated) =>
                            setState(() => e.type = updated),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(_saving
                  ? "Saving…"
                  : _isEditing
                      ? "Update calendar"
                      : "Save to calendar"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_stage == _Stage.compose
            ? (_isEditing ? "Edit calendar text" : "Add calendar text")
            : (_isEditing ? "Confirm updated events" : "Confirm parsed events")),
      ),
      body: _stage == _Stage.compose
          ? _buildComposeStage()
          : _buildPreviewStage(),
    );
  }
}

// -----------------------------------------------------------------------------
// Text block history (Part 5 item 2) + delete-cascades-events (Part 5 item 3)
// -----------------------------------------------------------------------------

class _TextBlockHistoryPage extends StatelessWidget {
  final String selectedGuide;
  final bool isHod;
  final List<CalendarTextBlock> textBlocks;
  final List<CalendarEvent> events;
  final Future<void> Function() onChanged;
  // Part 5 item 6 — opens the SAME add/extract/preview sheet as the FAB,
  // pre-filled for editing this block. Defined on `_GuideCalendarPageState`
  // (owns `_openTextEntryPage`), threaded in here as a callback since this
  // page itself only holds a snapshot of data, not the parent's state.
  final Future<void> Function(CalendarTextBlock) onEditRequested;

  const _TextBlockHistoryPage({
    required this.selectedGuide,
    required this.isHod,
    required this.textBlocks,
    required this.events,
    required this.onChanged,
    required this.onEditRequested,
  });

  int _eventCountFor(String blockId) =>
      events.where((e) => e.sourceTextBlockId == blockId).length;

  // Part 5 item 6 (4) — the SAME choke point already governs both delete
  // and edit: a mandatory block only the HOD may touch, a personal block
  // only its owner (enforced upstream by [visibleTextBlocksFor] never even
  // returning another guide's personal block to this list in the first
  // place). [_assertCanMutate] inside [updateTextBlockWithEvents] is the
  // real, server-trusted enforcement; this just hides the button to match.
  bool _canMutate(CalendarTextBlock b) => isHod || !b.isMandatory;

  Future<void> _confirmAndDelete(BuildContext context, CalendarTextBlock b) async {
    final count = _eventCountFor(b.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete this text block?"),
        content: Text(
          count == 0
              ? "This text block created no events. Delete it?"
              : "This will also delete the $count event"
                  "${count == 1 ? '' : 's'} it created. This cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await deleteTextBlockAndItsEvents(blockId: b.id, actingIsHod: isHod);
      await onChanged();
      if (context.mounted) {
        showSnackbar(context, "Deleted", Colors.green, Icons.check_circle);
      }
    } on MandatoryEventPermissionError catch (e) {
      if (context.mounted) {
        showSnackbar(context, e.message, Colors.red, Icons.error);
      }
    } catch (_) {
      if (context.mounted) {
        showSnackbar(context, "Could not delete", Colors.red, Icons.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Text history")),
      body: textBlocks.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  "No calendar text submitted yet.",
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: textBlocks.length,
              itemBuilder: (context, i) {
                final b = textBlocks[i];
                final count = _eventCountFor(b.id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: b.isMandatory
                                    ? Colors.indigo.shade50
                                    : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                b.isMandatory ? "Mandatory" : "Personal",
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: b.isMandatory
                                      ? Colors.indigo
                                      : Colors.orange.shade800,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (_canMutate(b))
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    size: 18, color: Colors.blue),
                                tooltip: "Edit and re-extract",
                                onPressed: () => onEditRequested(b),
                              ),
                            if (_canMutate(b))
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: Colors.red),
                                onPressed: () => _confirmAndDelete(context, b),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(b.rawText, style: const TextStyle(fontSize: 13.5)),
                        const SizedBox(height: 8),
                        Text(
                          "${b.submittedBy} · "
                          "${b.submittedAt == null ? '' : DateFormat('dd MMM yyyy, HH:mm').format(b.submittedAt!)}"
                          " · $count event${count == 1 ? '' : 's'}"
                          "${b.editedAt == null ? '' : ' · edited ${DateFormat('dd MMM yyyy, HH:mm').format(b.editedAt!)}'}",
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Notify-offsets picker (Part 8) — shared by the calendar view's per-event
// edit dialog and the preview screen's shared "applies to every event"
// control, so the two never drift out of sync with each other's wording or
// snap-back-to-default behaviour.
// -----------------------------------------------------------------------------

class _NotifyOffsetsPicker extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const _NotifyOffsetsPicker({
    required this.selected,
    required this.onChanged,
  });

  // Part 8 item 2 — toggling the last checked option off snaps back to
  // [kDefaultNotifyOffsets] rather than leaving nothing visibly selected:
  // what's checked here is always exactly what will be saved, so the
  // default is never an invisible fallback the guide can't see.
  void _toggle(String key, bool checked) {
    final updated = List<String>.from(selected);
    if (checked) {
      if (!updated.contains(key)) updated.add(key);
    } else {
      updated.remove(key);
    }
    onChanged(
        updated.isEmpty ? List<String>.from(kDefaultNotifyOffsets) : updated);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text("Notify",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: kNotifyOffsetLabels.entries.map((entry) {
            final isSelected = selected.contains(entry.key);
            return FilterChip(
              label: Text(entry.value, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              selected: isSelected,
              onSelected: (v) => _toggle(entry.key, v),
            );
          }).toList(),
        ),
        const SizedBox(height: 2),
        Text(
          "Default: 1 week before, if nothing is selected.",
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Event type picker (Master Task Part 2) — shared by the preview screen's
// per-event card and the calendar view's edit dialog. A single choice
// (unlike the notify-offsets picker, which is multi-select) since an event
// has exactly one type.
// -----------------------------------------------------------------------------

class _EventTypePicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _EventTypePicker({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text("Type",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: kEventTypeLabels.entries.map((entry) {
            return ChoiceChip(
              label: Text(entry.value, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              selected: selected == entry.key,
              onSelected: (_) => onChanged(entry.key),
            );
          }).toList(),
        ),
      ],
    );
  }
}
