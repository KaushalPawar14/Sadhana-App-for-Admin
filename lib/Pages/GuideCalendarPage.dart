import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/Responsive.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/AutoCalendar.dart';
import '../utils/PlanCalendar.dart';
import '../widgets/GuideMeta.dart';
import '../utils/CalendarData.dart';
import '../utils/CalendarQueries.dart';
import '../utils/SeenMarkers.dart';
import '../utils/Snackbar.dart';
import '../widgets/GuideBoard.dart';
import '../widgets/GuideButtons.dart';
import '../widgets/GuideCalendar.dart';
import '../widgets/GuideEntry.dart';
import '../widgets/GuideGhost.dart';
import '../widgets/GuideStates.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/EventAudiencePicker.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideWait.dart';

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
  // Role check (several HODs may exist; no id is special).
  bool get _isHod => AdminProfileProvider.viewerIsHod;

  bool _loading = true;
  bool _loadFailed = false;
  List<CalendarEvent> _manual = [];
  List<CalendarEvent> _auto = [];
  StreamSubscription<List<CalendarEvent>>? _autoSub;
  List<CalendarTextBlock> _textBlocks = [];

  /// A HOD sees his OWN items by default (his plan, his students, his trips, his events); "All guides" adds everyone else's. Everyone else sees his own scope.
  bool _allGuides = false;

  /// The guide's own events plus the automatic ones (live from their sources), filtered for a HOD who has not asked for all guides.
  List<CalendarEvent> get _events {
    final all = [..._manual, ..._auto];
    if (!_isHod || _allGuides) return all;
    return [for (final e in all) if (e.guideId.isEmpty || e.guideId == widget.selectedGuide) e];
  }

  /// How many events of the day the HOD's "My items" view leaves out (other guides').
  int _hiddenOn(DateTime day) => eventsCoveringDay([..._manual, ..._auto], day).length - eventsCoveringDay(_events, day).length;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _autoSub = CalendarData.instance.automaticEvents(widget.selectedGuide).listen((events) {
      if (mounted) setState(() => _auto = events);
    }, onError: (_) {});
    _loadAll();
    // Master Task 2026-09-10, Part 6 — opening this screen is "seen" for
    // mandatory calendar events.
    SeenMarkers.markSeen(widget.selectedGuide, 'calendarEvents');
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final events = await CalendarData.instance.events(widget.selectedGuide);
      final blocks = await CalendarData.instance.textBlocks(widget.selectedGuide);
      if (!mounted) return;
      setState(() {
        _manual = events;
        _textBlocks = blocks;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
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


  @override
  void dispose() {
    _autoSub?.cancel();
    super.dispose();
  }

  /// An automatic event is read-only here: a tap opens the screen where that item is edited.
  void _openSource(CalendarEvent e) {
    final page = autoEventPage(e);
    if (page == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
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
    // who the event is for (empty = everyone): the plans and the assistant apply it to these students only
    var forCategories = List<String>.from(event.forCategories);
    var forStudents = List<String>.from(event.forStudents);

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isRange = endDate != null;
            return GuideDialog(
              title: const Text("Edit event"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.event, color: dialogContext.g.brass),
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
                      title: Text("Spans multiple days",
                          style: dialogContext.gText.body),
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
                    EventAudiencePicker(
                      categories: forCategories,
                      students: forStudents,
                      onChanged: (c, st) => setDialogState(() {
                        forCategories = c;
                        forStudents = st;
                      }),
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
        forCategories: forCategories,
        forStudents: forStudents,
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

  /// The Calendar screen.
  ///
  /// The month grid is still `table_calendar` (month paging, selection, the date
  /// range); only how a day is drawn changed: [GuideDayCell] — a soft band behind a
  /// multi-day exam / festival / programme, one dot per event in its own colour (at
  /// most three, then a "+"), a brass circle on the selected date. A week row
  /// stays compact (about 54-56 dp) and only grows with the text size, never to fit
  /// labels.
  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final g = context.g;
    // a wide window keeps the month at the content width (a phone: the whole width, as before)
    final width = contentWidthOf(context);
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    // The true width of one day column: the page padding on both sides, then the
    // month card's own 10 dp each side (6 card + 4 row padding).
    final cellWidth = (width - 2 * GuideSpace.pagePadding - 20) / 7;
    final rowHeight = guideCalendarRowHeight(context, cellWidth);

    // The month card. It is also the placeholder of the ghost: laid out with no events
    // it has exactly the size the loaded one will have, at any text scale.
    Widget monthCard() =>
                      GuideCard(
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
                        child: TableCalendar<CalendarEvent>(
                          firstDay: DateTime.now().subtract(const Duration(days: 365)),
                          lastDay: DateTime.now().add(const Duration(days: 365)),
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
                          rowHeight: rowHeight,
                          daysOfWeekHeight: 12 * scale + 16,
                          headerStyle: HeaderStyle(
                            titleCentered: true,
                            formatButtonVisible: false,
                            leftChevronIcon:
                                Icon(Icons.chevron_left_rounded, color: g.mutedText),
                            rightChevronIcon:
                                Icon(Icons.chevron_right_rounded, color: g.mutedText),
                            titleTextStyle: t.sectionTitle,
                            headerPadding: const EdgeInsets.only(bottom: 10),
                          ),
                          calendarStyle: const CalendarStyle(cellMargin: EdgeInsets.zero),
                          pageAnimationEnabled: !GuideMotion.reduced(context),
                          pageAnimationDuration: const Duration(milliseconds: 250),
                          pageAnimationCurve: GuideMotion.standard,
                          calendarBuilders: CalendarBuilders(
                            dowBuilder: (context, day) => Center(
                              child: ExcludeSemantics(
                                child: Text(
                                  DateFormat.E().format(day),
                                  style: t.small.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            defaultBuilder: (context, day, focusedDay) => GuideDayCell(
                                day: day, events: _eventsOn(day), cellWidth: cellWidth),
                            todayBuilder: (context, day, focusedDay) => GuideDayCell(
                                day: day,
                                events: _eventsOn(day),
                                cellWidth: cellWidth,
                                isToday: true),
                            selectedBuilder: (context, day, focusedDay) => GuideDayCell(
                                day: day,
                                events: _eventsOn(day),
                                cellWidth: cellWidth,
                                selected: true,
                                isToday: isSameDay(day, DateTime.now())),
                            outsideBuilder: (context, day, focusedDay) => GuideDayCell(
                                day: day,
                                events: _eventsOn(day),
                                cellWidth: cellWidth,
                                outside: true),
                          ),
                        ),
                      );

    return GuideScaffold(
      floatingActionButton: GuideFab(
        label: "Add text",
        icon: Icons.add_rounded,
        onPressed: _openTextEntryPage,
      ),
      body: Column(
        children: [
          GuideTopBar(
            title: "Calendar",
            actions: [
              GuideRoundButton(
                icon: Icons.history_rounded,
                tooltip: "Text history",
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _TextBlockHistoryPage(
                        selectedGuide: widget.selectedGuide,
                        isHod: _isHod,
                        textBlocks: _textBlocks,
                        events: _manual,
                        onChanged: _loadAll,
                        onEditRequested: (b) => _openTextEntryPage(editingBlock: b),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          Expanded(
            child: GuideCrossFade(
              child: _loading || _loadFailed
                ? KeyedSubtree(
                    key: ValueKey(_loadFailed ? 'ghost-error' : 'ghost-loading'),
                    child: _calendarWait(monthCard(), _todayGhost()),
                  )
                : KeyedSubtree(
                    key: const ValueKey('calendar'),
                    child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        GuideSpace.pagePadding, 8, GuideSpace.pagePadding, 110),
                    children: [
                      // Part 5 item 5 — empty state.
                      if (!_hasMandatoryBlock && !_isHod)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: GuideNotice(
                            child: Text(
                              "Your HOD hasn't set up the shared calendar yet. "
                              "You can still add your own personal events below.",
                            ),
                          ),
                        ),
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: GuideCalendarLegend(),
                      ),
                      const SizedBox(height: 12),
                      monthCard(),
                      const SizedBox(height: 16),
                      _todayPanel(),
                    ],
                  ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// While the month loads (or if it failed): the legend stays real; the month card and
  /// the event list are ghosts of themselves; a failure freezes them and offers Retry.
  Widget _calendarWait(Widget monthCard, Widget todayGhost) {
    final t = context.gText;
    final ghost = ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 8, GuideSpace.pagePadding, 110),
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: GuideCalendarLegend(),
        ),
        const SizedBox(height: 12),
        GuideGhostOf(placeholder: monthCard),
        const SizedBox(height: 16),
        todayGhost,
      ],
    );
    if (_loadFailed) {
      return Stack(
        children: [
          GuideGhostArea(pulsing: false, child: ghost),
          Positioned(
            left: GuideSpace.pagePadding,
            right: GuideSpace.pagePadding,
            bottom: 130,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Could not load the calendar. Check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: t.body.copyWith(color: context.g.mutedText, height: 1.5),
                ),
                const SizedBox(height: 12),
                GuideSecondaryButton(label: 'Retry', icon: Icons.refresh_rounded, onPressed: _loadAll),
              ],
            ),
          ),
        ],
      );
    }
    return GuideGhostArea(child: ghost);
  }

  /// The ghost of the selected day's list: a heading and three event rows.
  Widget _todayGhost() {
    final t = context.gText;
    final sample = CalendarEvent(
      id: 'ghost',
      eventDate: DateTime.now(),
      endDate: null,
      type: kEventTypeOther,
      title: 'Sample event',
      note: '',
      sourceTextBlockId: '',
      scope: kScopePersonal,
      ownerGuideId: null,
      notifyOffsets: const [],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Today', style: t.sectionTitle),
        for (var i = 0; i < 3; i++) GuideGhostOf(placeholder: GuideEventRow(event: sample)),
      ],
    );
  }

  /// The selected day's events, defaulting to today (`initState` sets
  /// `_selectedDay = DateTime.now()`); tapping another date updates it. The heading
  /// says "Today" only when it is; an event row opens the same edit dialog the old
  /// pencil icon did (only where the viewer may change it). Calendar events only:
  /// missing reports live under Tasks -> Submissions.
  Widget _todayPanel() {
    final day = _selectedDay;
    if (day == null) return const SizedBox.shrink();

    final t = context.gText;
    final events = _eventsOn(day);
    final isToday = isSameDay(day, DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isHod)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              children: [
                GuideChoiceChip(key: const ValueKey('cal-only-mine'), label: 'My items', selected: !_allGuides, onSelected: (_) => setState(() => _allGuides = false)),
                GuideChoiceChip(key: const ValueKey('cal-all-guides'), label: 'All guides', selected: _allGuides, onSelected: (_) => setState(() => _allGuides = true)),
              ],
            ),
          ),
        // nothing is hidden silently: a HOD's "My items" view says how many items of other guides it leaves out, on every day
        if (_isHod && !_allGuides && _hiddenOn(day) > 0)
          Padding(
            key: const ValueKey('cal-hidden-hint'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${_hiddenOn(day)} item${_hiddenOn(day) == 1 ? '' : 's'} of other guides hidden on this day — tap "All guides" to see ${_hiddenOn(day) == 1 ? 'it' : 'them'}.', style: t.caption),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                isToday ? "Today" : DateFormat('EEE, dd MMM').format(day),
                style: t.sectionTitle,
              ),
            ),
            if (events.isNotEmpty)
              Text("${events.length} event${events.length == 1 ? '' : 's'}", style: t.small),
          ],
        ),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GuideCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 18, color: context.g.mutedText),
                  const SizedBox(width: 10),
                  Expanded(child: Text("Nothing due", style: t.small)),
                ],
              ),
            ),
          )
        else
          // GROUPED LIKE TODAY: Follow-ups, Target tasks, Other tasks, Meetings, Events; what is still to do first, the done ones after; each row opens its screen
          for (final group in kCalendarGroups)
            ...(() {
              final inGroup = [for (final e in events) if (calendarGroupOf(e) == group.$1) e]..sort((a, b) => a.done == b.done ? 0 : (a.done ? 1 : -1));
              if (inGroup.isEmpty) return const <Widget>[];
              return <Widget>[
                Padding(
                  key: ValueKey('cal-group-${group.$1}'),
                  padding: const EdgeInsets.only(top: 14),
                  child: Text('${group.$2} (${inGroup.length})', style: t.bodyStrong.copyWith(color: context.g.agent)),
                ),
                for (var i = 0; i < inGroup.length; i++)
                  GuideEntry(
                    // A new day replays the rise: the key carries the day.
                    key: ValueKey('${DateFormat('yyyyMMdd').format(day)}-${inGroup[i].id}'),
                    index: i,
                    child: GuideEventRow(
                      event: inGroup[i],
                      onTap: inGroup[i].isAutomatic
                          ? (autoEventPage(inGroup[i]) == null ? null : () => _openSource(inGroup[i]))
                          : (_canMutate(inGroup[i]) ? () => _openEditEventDialog(inGroup[i]) : null),
                    ),
                  ),
              ];
            })(),
      ],
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

  /// Who the events of this paste are for (one shared control, like the reminders): empty = everyone.
  List<String> _sharedCategories = [];
  List<String> _sharedStudents = [];

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
              style: context.gText.small,
            ),
            const SizedBox(height: 14),
            // Scope picker only in ADD mode — an edit keeps the block's
            // existing scope fixed ([updateTextBlockWithEvents] re-reads
            // scope fresh from Firestore regardless, so this is a
            // display-only lock, not the real enforcement).
            if (editingBlock != null)
              GuideNotice(
                child: Text(
                  editingBlock.isMandatory
                      ? "Editing a MANDATORY block — visible to every guide."
                      : "Editing a personal block — only you can see it.",
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
              const GuideNotice(
                child: Text(
                  "This will be saved to your own personal calendar — only "
                  "you will see it.",
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
              ),
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Center(
                  child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: GuideBusyDot(),
              ))
            else
              GuidePrimaryButton(
                label: "Extract dates",
                icon: Icons.auto_awesome,
                onPressed: _extract,
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
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: GuideNotice(
            child: Text(
              "Check every date, title and note below before saving — a "
              "misread date becomes a wrong reminder weeks from now with no "
              "way to trace it back.",
            ),
          ),
        ),
        // Part 8 item 3 — ONE shared control for the whole paste, rather
        // than needing per-event edits afterward (per-event fine-tuning is
        // still available later from the calendar view's own edit dialog).
        // Applies immediately to every event currently in `_events`.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: EventAudiencePicker(
            categories: _sharedCategories,
            students: _sharedStudents,
            onChanged: (c, st) {
              setState(() {
                _sharedCategories = c;
                _sharedStudents = st;
                for (final e in _events) {
                  e.forCategories = List<String>.from(c);
                  e.forStudents = List<String>.from(st);
                }
              });
            },
          ),
        ),
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
                                    style: context.gText.small),
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
          child: GuidePrimaryButton(
            label: _saving
                ? "Saving…"
                : _isEditing
                    ? "Update calendar"
                    : "Save to calendar",
            icon: Icons.check_circle_outline,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GuideScaffold(
      appBar: GuideAppBar(
        title: Text(_stage == _Stage.compose
            ? (_isEditing ? "Edit calendar text" : "Add calendar text")
            : (_isEditing ? "Confirm updated events" : "Confirm parsed events"))),
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
      builder: (dialogContext) => GuideDialog(
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
            style: ElevatedButton.styleFrom(
                backgroundColor: dialogContext.g.danger, foregroundColor: Colors.white),
            child: const Text("Delete"),
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
    return GuideScaffold(
      appBar: GuideAppBar(title: const Text("Text history")),
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
                            Builder(builder: (context) {
                              final tone = context.g.eventColor(b.isMandatory
                                  ? GuideEventType.mandatory
                                  : GuideEventType.personal);
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: tone.withValues(alpha: .14),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  b.isMandatory ? "Mandatory" : "Personal",
                                  style: context.gText.pill.copyWith(color: context.g.text),
                                ),
                              );
                            }),
                            const Spacer(),
                            if (_canMutate(b))
                              IconButton(
                                icon: Icon(Icons.edit_outlined,
                                    size: 18, color: context.g.brass),
                                tooltip: "Edit and re-extract",
                                onPressed: () => onEditRequested(b),
                              ),
                            if (_canMutate(b))
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    size: 18, color: context.g.danger),
                                tooltip: "Delete",
                                onPressed: () => _confirmAndDelete(context, b),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(b.rawText, style: context.gText.body),
                        const SizedBox(height: 8),
                        Text(
                          "${b.submittedBy} · "
                          "${b.submittedAt == null ? '' : DateFormat('dd MMM yyyy, HH:mm').format(b.submittedAt!)}"
                          " · $count event${count == 1 ? '' : 's'}"
                          "${b.editedAt == null ? '' : ' · edited ${DateFormat('dd MMM yyyy, HH:mm').format(b.editedAt!)}'}",
                          style: context.gText.caption,
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
        Text("Notify", style: context.gText.bodyStrong.copyWith(fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: kNotifyOffsetLabels.entries.map((entry) {
            final isSelected = selected.contains(entry.key);
            return GuideChoiceChip(label: entry.value, selected: isSelected, onSelected: (v) => _toggle(entry.key, v));
          }).toList(),
        ),
        const SizedBox(height: 2),
        Text(
          "Default: 1 week before, if nothing is selected.",
          style: context.gText.caption.copyWith(fontSize: 10.5),
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
        Text("Type", style: context.gText.bodyStrong.copyWith(fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: kEventTypeLabels.entries.map((entry) {
            return GuideChoiceChip(label: entry.value, selected: selected == entry.key, onSelected: (_) => onChanged(entry.key));
          }).toList(),
        ),
      ],
    );
  }
}
