/// Guide Calendar — text-to-dates, mandatory + personal layers.
///
/// ---------------------------------------------------------------------------
/// Schema (Rule 12)
/// ---------------------------------------------------------------------------
/// The TEXT BLOCK is the unit of authorship; every event is DERIVED from one
/// and always traces back to it (`sourceTextBlockId`) — deleting a block
/// deletes every event it produced (see [deleteTextBlockAndItsEvents]).
///
///   calendarTextBlocks/{autoId}
///     rawText          String    — kept FOREVER, never deleted (Part 5 item
///                                  2's history view needs it) — unlike
///                                  `interactionLogs.rawDictation`, which IS
///                                  deleted after extraction: that's private
///                                  student dictation; this is a guide's own
///                                  scheduling note, nothing to purge.
///     submittedBy       String    guide name
///     submittedAt       Timestamp
///     scope             'mandatory' | 'personal'
///     ownerGuideId      String?   null when scope == 'mandatory'
///     editedAt          Timestamp?  set only once this block's rawText has
///                                  been edited since first submitted (Part
///                                  5 item 6, [updateTextBlockWithEvents]) —
///                                  absent on a block never edited. `scope`/
///                                  `ownerGuideId` are NEVER changed by an
///                                  edit — only `rawText` and the derived
///                                  events can change.
///     editedBy          String?   ditto — the guide who made the edit.
///
///   calendarEvents/{autoId}
///     eventDate         Timestamp — SORTABLE (see the note below on why NOT
///                                  dd-MM-yyyy). UNCHANGED in name and
///                                  meaning (Master Task Part 1, Rule 3) —
///                                  still "the event's date"; for a range,
///                                  specifically the START.
///     endDate           Timestamp?  — additive (Master Task Part 1), Rule
///                                  3. `null`/absent means a single-day
///                                  event — exactly what every event
///                                  written before this task already looks
///                                  like, so nothing existing changes
///                                  behaviour. When present, the event spans
///                                  `eventDate` to `endDate` INCLUSIVE of
///                                  both. Never precedes `eventDate` —
///                                  enforced both server-side
///                                  ([validateExtractedEvents] in
///                                  `functions/calendarEvents.js`, for
///                                  AI-extracted events) and client-side
///                                  (this file's own [_assertValidRange], for
///                                  manually-set ranges from the calendar
///                                  view's edit dialog or the preview
///                                  screen).
///     type              String    — additive (Master Task Part 2), Rule 3.
///                                  One of [kEventTypes]
///                                  (exam/festival/program/other). An event
///                                  written before this field existed simply
///                                  lacks it and reads back as
///                                  [kDefaultEventType] ("other") — see
///                                  [CalendarEvent.fromDoc].
///     title             String
///     note              String    optional, may be ''
///     sourceTextBlockId String    -> calendarTextBlocks doc id
///     scope             'mandatory' | 'personal'   denormalized from the
///                                  block, so every query below needs no join
///     ownerGuideId      String?   ditto
///     createdAt         Timestamp
///     editedAt          Timestamp?
///     editedBy          String?
///     notifyOffsets     `List<String>`  — additive (Part 8), Rule 3. Any
///                                  combination of [kNotifyOffsetOnDay] /
///                                  [kNotifyOffsetOneDayBefore] /
///                                  [kNotifyOffsetOneWeekBefore] /
///                                  [kNotifyOffsetOneMonthBefore]. Every
///                                  write from this file sets it explicitly
///                                  (never omits it, never writes an empty
///                                  list — see [kDefaultNotifyOffsets]); an
///                                  event written before this field existed
///                                  simply lacks it, and the Cloud Function
///                                  (`functions/calendarEvents.js`,
///                                  `DEFAULT_NOTIFY_OFFSETS`) treats a
///                                  missing/empty list as
///                                  `['oneWeekBefore']` — byte-for-byte the
///                                  only behaviour that existed before this
///                                  field, so no existing event's behaviour
///                                  changes. For a RANGE (Master Task Part
///                                  3), every offset still anchors to
///                                  `eventDate` (the START) — the exact same
///                                  arithmetic already used for a single-day
///                                  event, completely untouched by this
///                                  task; a range needed NO changes to the
///                                  offset-matching code at all, only to the
///                                  data model.
///
///   calendarEventTypeDescriptions/{typeKey}
///     — additive (Master Task Part 2), Rule 12: the CRITICAL requirement is
///     that a type's MEANING (what it implies for a guide's week) is
///     editable by a guide/HOD with no redeploy, because that meaning is
///     what the AI prompt reads (`upcomingEventsSection` in
///     `functions/goals.js`). A value hardcoded in Dart or JS cannot satisfy
///     "editable... at any time" — it has to live in Firestore. One tiny doc
///     per type in [kEventTypes], `typeKey` being the type string itself
///     (e.g. `calendarEventTypeDescriptions/exam`).
///     description       String    — what this type means for a guide's
///                                  week; fed verbatim into the AI prompt.
///     updatedAt         Timestamp?
///     updatedBy         String?
///     Seeded with [kDefaultTypeDescriptions] on first use by
///     [ensureEventTypeDescriptionsSeeded] — called once when the "manage
///     type meanings" UI opens. The Cloud Function side NEVER writes this
///     collection, only reads it with the SAME defaults as an in-memory
///     fallback (`functions/calendarEvents.js`'s own
///     `DEFAULT_TYPE_DESCRIPTIONS`, kept textually in sync with
///     [kDefaultTypeDescriptions] deliberately), so a prompt build is never
///     blocked on seeding having already happened.
///
/// ---------------------------------------------------------------------------
/// Top-level collection, not a subcollection of the text block
/// ---------------------------------------------------------------------------
/// Range queries by date are the dominant access pattern here — the week-
/// ahead notification (Part 6) and the AI-context feed (Part 7) both ask
/// "what's coming up in the next N days," and the calendar view (Part 5)
/// wants every visible event across every month at once. A flat top-level
/// collection answers all three with a plain equality-filtered fetch plus
/// date-window narrowing in Dart — this project's own established
/// convention (e.g. `computeStudentBuckets`'s "no composite index"
/// discipline) of never combining a range/inequality filter with a second
/// field's filter, to avoid ever needing a Firestore composite index.
/// Nesting events under their text block would only complicate that — a
/// collection-group query buys nothing a flat collection doesn't already
/// give for free, and cascading delete (Part 5 item 3) is already a single
/// `where('sourceTextBlockId','==',id)` query regardless of nesting.
///
/// ---------------------------------------------------------------------------
/// Why Timestamp, not dd-MM-yyyy or even yyyy-MM-dd
/// ---------------------------------------------------------------------------
/// `dd-MM-yyyy` (used elsewhere in this project, e.g. sadhana date docs) is
/// NOT lexicographically sortable — "05-12-2026" < "09-01-2026" as strings,
/// even though January is earlier. A calendar's core operation — "events in
/// the next 7 days" — is a range query, which a non-sortable format cannot
/// support as a real Firestore query at all. Firestore Timestamp is natively
/// sortable and range-comparable, and matches this project's own convention
/// for "when will/did a thing happen" fields that get range-queried
/// (`interactionLogs.interactionDate`, `associations.preferredDate`,
/// `litAssessments.assessedAt`) — as opposed to `booksRead`'s yyyy-MM-dd
/// strings, a deliberate, scoped choice made there because that feature
/// does pure-Dart arithmetic with no Firestore range query ever needed.
///
/// ---------------------------------------------------------------------------
/// Enforcement — Part 4 item 1, "enforce in code," not just by hiding a button
/// ---------------------------------------------------------------------------
/// [_assertCanMutate] is the ONE place that decides whether an identity may
/// touch a scope. Every write path in this file that can touch a mandatory
/// item — create, edit, delete — calls it, checking freshly-read data (never
/// a value trusted from the caller), so a UI bug that forgot to hide a
/// button still cannot produce a write.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'AdminProfile.dart';
import 'GuideDb.dart';

/// Own local copy — matches `GoalCompoundQueries.dart`'s own
/// `kFunctionsRegion` constant, not shared, per this project's established
/// per-file convention for small constants like this one.
const String kCalendarFunctionsRegion = 'asia-south1';

const String kScopeMandatory = 'mandatory';

/// [CalendarEvent.source] of a guide's own event.
const String kSourceManual = 'manual';
const String kScopePersonal = 'personal';

/// Part 8 — the four selectable per-event notification offsets. Keys are
/// exactly what `calendarEvents.notifyOffsets` stores and what
/// `functions/calendarEvents.js`'s `NOTIFY_OFFSET_DAYS` uses — kept in sync
/// deliberately, same reasoning as this project's other Dart/JS constant
/// pairs.
const String kNotifyOffsetOnDay = 'onDay';
const String kNotifyOffsetOneDayBefore = 'oneDayBefore';
const String kNotifyOffsetOneWeekBefore = 'oneWeekBefore';
const String kNotifyOffsetOneMonthBefore = 'oneMonthBefore';

/// Display order + labels for the four offsets above — one place both the
/// calendar-view edit dialog and the preview screen's shared picker read
/// from, so the two never drift out of sync with each other's wording.
const Map<String, String> kNotifyOffsetLabels = {
  kNotifyOffsetOnDay: 'On the day',
  kNotifyOffsetOneDayBefore: '1 day before',
  kNotifyOffsetOneWeekBefore: '1 week before',
  kNotifyOffsetOneMonthBefore: '1 month before',
};

/// Part 8 item 2 — the default when a guide selects nothing, so an event
/// never silently fails to notify at all. `saveTextBlockWithEvents` and
/// `updateTextBlockWithEvents` fall back to this whenever an event's own
/// `notifyOffsets` ends up empty at save time.
const List<String> kDefaultNotifyOffsets = [kNotifyOffsetOneWeekBefore];

/// Master Task Part 2 — the four event types. Keys match
/// `functions/calendarEvents.js`'s `EVENT_TYPES` exactly — kept in sync
/// deliberately, same Dart/JS constant-pair convention as the notify
/// offsets above.
const String kEventTypeExam = 'exam';
const String kEventTypeFestival = 'festival';
const String kEventTypeProgram = 'program';
const String kEventTypeOther = 'other';
const List<String> kEventTypes = [
  kEventTypeExam,
  kEventTypeFestival,
  kEventTypeProgram,
  kEventTypeOther,
];
const String kDefaultEventType = kEventTypeOther;

/// Display labels — one place the type dropdown/chips in both the calendar
/// view's edit dialog and the preview screen read from.
const Map<String, String> kEventTypeLabels = {
  kEventTypeExam: 'Exam',
  kEventTypeFestival: 'Festival',
  kEventTypeProgram: 'Program',
  kEventTypeOther: 'Other',
};

/// Seeded into `calendarEventTypeDescriptions` on first use
/// ([ensureEventTypeDescriptionsSeeded]) — kept textually in sync with
/// `functions/calendarEvents.js`'s own `DEFAULT_TYPE_DESCRIPTIONS`
/// deliberately (see this file's schema doc comment on that collection).
const Map<String, String> kDefaultTypeDescriptions = {
  kEventTypeExam:
      'Students are unavailable or highly distracted — expect little to '
      'no academic/service progress this week. Avoid assigning new '
      'commitments; check in gently instead.',
  kEventTypeFestival:
      'A community celebration — students are often busy with event '
      'duties, travel, or extended family time. Progress may slow, but '
      'this is a normal, expected dip, not a concern.',
  kEventTypeProgram:
      "A scheduled program or camp — students' usual routine is disrupted "
      'by structured activities. Availability varies; check what the '
      'program actually involves before assuming a full loss of time.',
  kEventTypeOther:
      'A general calendar note without a specific known pattern — use '
      'the note field for details; no fixed assumption about availability.',
};

/// (Range-band and dot colours now come from the theme: `GuideColors.eventColor` /
/// `eventBand`, chosen per event by `guideEventTypeOf` in `widgets/GuideCalendar.dart`.)

/// Master Task Part 1 item 3 — thrown when a range's `endDate` precedes its
/// `eventDate`. Client-side counterpart to the server-side check in
/// `functions/calendarEvents.js`'s `validateExtractedEvents` (which guards
/// the AI-extraction path); this one guards every write path in THIS file
/// (manual entry/editing never goes through that Cloud Function at all).
class InvalidEventRangeError implements Exception {
  final String message;
  InvalidEventRangeError(this.message);
  @override
  String toString() => message;
}

void _assertValidRange(DateTime start, DateTime? end) {
  if (end == null) return;
  if (end.isBefore(DateTime(start.year, start.month, start.day))) {
    throw InvalidEventRangeError(
      'The end date cannot be before the start date.',
    );
  }
}

/// Thrown when a non-HOD guide attempts to create, edit or delete a
/// mandatory event or text block.
class MandatoryEventPermissionError implements Exception {
  final String message;
  MandatoryEventPermissionError(this.message);
  @override
  String toString() => message;
}

/// Hierarchy: the caller's `actingIsHod` flag is additionally confirmed
/// against the signed-in admin's ROLE — only a HOD (any of several; no id is
/// special) may touch mandatory events.
void _assertCanMutate({required String scope, required bool actingIsHod}) {
  if (scope == kScopeMandatory &&
      !(actingIsHod && AdminProfileProvider.viewerIsHod)) {
    throw MandatoryEventPermissionError(
      'Only the HOD can create, edit or delete a mandatory calendar event.',
    );
  }
}

class CalendarTextBlock {
  final String id;
  final String rawText;
  final String submittedBy;
  final DateTime? submittedAt;
  final String scope;
  final String? ownerGuideId;
  final DateTime? editedAt;
  final String? editedBy;

  CalendarTextBlock({
    required this.id,
    required this.rawText,
    required this.submittedBy,
    required this.submittedAt,
    required this.scope,
    required this.ownerGuideId,
    this.editedAt,
    this.editedBy,
  });

  bool get isMandatory => scope == kScopeMandatory;

  factory CalendarTextBlock.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return CalendarTextBlock(
      id: doc.id,
      rawText: (d['rawText'] ?? '').toString(),
      submittedBy: (d['submittedBy'] ?? '').toString(),
      submittedAt: (d['submittedAt'] as Timestamp?)?.toDate(),
      scope: (d['scope'] ?? kScopePersonal).toString(),
      ownerGuideId: d['ownerGuideId'] as String?,
      editedAt: (d['editedAt'] as Timestamp?)?.toDate(),
      editedBy: d['editedBy'] as String?,
    );
  }
}

class CalendarEvent {
  final String id;
  final DateTime eventDate;
  final DateTime? endDate;
  final String type;
  final String title;
  final String note;
  final String sourceTextBlockId;
  final String scope;
  final String? ownerGuideId;
  final List<String> notifyOffsets;

  /// Where the event comes from: [kSourceManual] (the guide's own, in `calendarEvents`: editable) or one of the automatic
  /// kinds (`target`, `phase`, `followUp`, `interaction`, `meeting`, `trip`, `competition`: read from the source data, read-only
  /// here; a tap opens the screen where that item is edited). [refId] is the source document's id; [studentUid] / [studentName] /
  /// [guideId] say whose it is, for the screen it opens.
  final String source;
  final String refId;
  final String studentUid;
  final String studentName;
  final String guideId;

  CalendarEvent({
    required this.id,
    required this.eventDate,
    required this.endDate,
    required this.type,
    required this.title,
    required this.note,
    required this.sourceTextBlockId,
    required this.scope,
    required this.ownerGuideId,
    required this.notifyOffsets,
    this.source = kSourceManual,
    this.refId = '',
    this.studentUid = '',
    this.studentName = '',
    this.guideId = '',
  });

  bool get isMandatory => scope == kScopeMandatory;

  /// True for an event the app derives from its own data (not one a guide wrote): never edited here.
  bool get isAutomatic => source != kSourceManual;

  /// Master Task Part 1 — true once this event has a real `endDate`. A
  /// single-day event (`endDate == null`) is never a range.
  bool get isMultiDay => endDate != null;

  /// The date range's real end for inclusive day-matching — `endDate` if
  /// set, else `eventDate` itself. Used by [eventCoversDay] so a
  /// single-day event's "does this day match" check reduces to EXACTLY
  /// what it always was: `day == eventDate`.
  DateTime get effectiveEndDate => endDate ?? eventDate;

  factory CalendarEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final ts = d['eventDate'];
    final endTs = d['endDate'];
    final rawOffsets = d['notifyOffsets'];
    final rawType = (d['type'] ?? '').toString();
    return CalendarEvent(
      id: doc.id,
      eventDate: ts is Timestamp ? ts.toDate() : DateTime.now(),
      endDate: endTs is Timestamp ? endTs.toDate() : null,
      // An event written before this field existed reads as "other" —
      // Rule 3, same reasoning as `notifyOffsets`'s own read-time default.
      type: kEventTypes.contains(rawType) ? rawType : kDefaultEventType,
      title: (d['title'] ?? '').toString(),
      note: (d['note'] ?? '').toString(),
      sourceTextBlockId: (d['sourceTextBlockId'] ?? '').toString(),
      scope: (d['scope'] ?? kScopePersonal).toString(),
      ownerGuideId: d['ownerGuideId'] as String?,
      // Same read-time default as the Cloud Function's own
      // `DEFAULT_NOTIFY_OFFSETS` — an event written before this field
      // existed reads back as "1 week before," matching its only real
      // behaviour before this task.
      notifyOffsets: rawOffsets is List && rawOffsets.isNotEmpty
          ? rawOffsets.map((e) => e.toString()).toList()
          : List<String>.from(kDefaultNotifyOffsets),
    );
  }
}

/// Master Task Part 4 item 2 — does [event] cover [day]? Inclusive of both
/// ends. For a single-day event (`effectiveEndDate == eventDate`) this
/// reduces to EXACTLY `day == eventDate` — the only check that existed
/// before ranges, unchanged (Rule 3). Dates are compared by calendar day
/// only (year/month/day), matching every other day-comparison already in
/// this file's callers.
bool eventCoversDay(CalendarEvent event, DateTime day) {
  final key = DateTime(day.year, day.month, day.day);
  final start = DateTime(
      event.eventDate.year, event.eventDate.month, event.eventDate.day);
  final end = DateTime(event.effectiveEndDate.year,
      event.effectiveEndDate.month, event.effectiveEndDate.day);
  return !key.isBefore(start) && !key.isAfter(end);
}

/// Every event in [events] that covers [day] — the range-aware
/// generalisation of "events on this exact day," used by both the calendar
/// view (tapping any day within a range shows/edits that event — Master
/// Task Part 4 item 2) and Weekly Planning's "happening now" section.
List<CalendarEvent> eventsCoveringDay(List<CalendarEvent> events, DateTime day) {
  return events.where((e) => eventCoversDay(e, day)).toList();
}

/// Master Task Part 5 item 2 — events whose range covers TODAY (or a
/// single-day event today).
List<CalendarEvent> eventsHappeningNow(List<CalendarEvent> events,
    {DateTime? today}) {
  return eventsCoveringDay(events, today ?? DateTime.now());
}

/// Master Task Part 5 item 2 — events STARTING within the next [days] days
/// (today exclusive — an event starting today is "happening now," not
/// "coming up"; see [eventsHappeningNow]).
List<CalendarEvent> eventsComingUp(List<CalendarEvent> events, {int days = 7}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final horizon = today.add(Duration(days: days));
  return events.where((e) {
    final start =
        DateTime(e.eventDate.year, e.eventDate.month, e.eventDate.day);
    return start.isAfter(today) && !start.isAfter(horizon);
  }).toList()
    ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
}

/// Every event visible to [guideId] — every mandatory event, plus this
/// guide's own personal ones. The HOD sees their own personal events
/// alongside the mandatory ones too (Part 4 item 3) — nothing here
/// special-cases the HOD; they are simply the guide whose own
/// `ownerGuideId` matches.
///
/// Two plain equality-filtered queries, merged in Dart — never a range
/// filter combined with a second field, so no composite index is ever
/// needed (see this file's header).
Future<List<CalendarEvent>> visibleEventsFor(String guideId) async {
  final col = GuideDb.instance.collection('calendarEvents');
  final results = await Future.wait([
    col.where('scope', isEqualTo: kScopeMandatory).get(),
    col
        .where('scope', isEqualTo: kScopePersonal)
        .where('ownerGuideId', isEqualTo: guideId)
        .get(),
  ]);
  return [
    for (final snap in results)
      for (final doc in snap.docs) CalendarEvent.fromDoc(doc),
  ];
}

/// Same visibility rule as [visibleEventsFor], narrowed to the next [days]
/// days from now — the shape Part 6 (week-ahead notification) and Part 7
/// (AI context) both need. Narrowing happens in Dart, not as a Firestore
/// range filter (see this file's header).
Future<List<CalendarEvent>> upcomingEventsFor(
  String guideId, {
  int days = 7,
}) async {
  final all = await visibleEventsFor(guideId);
  final now = DateTime.now();
  final horizon = now.add(Duration(days: days));
  return all
      .where((e) => e.eventDate.isAfter(now) && e.eventDate.isBefore(horizon))
      .toList()
    ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
}

/// Every text block [guideId] can see in history (Part 5 item 2): every
/// mandatory block (any guide can READ what the HOD posted, even though
/// only the HOD can edit/delete it — Part 4 item 1), plus this guide's own
/// personal blocks. Newest first.
Future<List<CalendarTextBlock>> visibleTextBlocksFor(String guideId) async {
  final col = GuideDb.instance.collection('calendarTextBlocks');
  final results = await Future.wait([
    col.where('scope', isEqualTo: kScopeMandatory).get(),
    col
        .where('scope', isEqualTo: kScopePersonal)
        .where('ownerGuideId', isEqualTo: guideId)
        .get(),
  ]);
  final blocks = [
    for (final snap in results)
      for (final doc in snap.docs) CalendarTextBlock.fromDoc(doc),
  ];
  blocks.sort((a, b) {
    final ad = a.submittedAt;
    final bd = b.submittedAt;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return bd.compareTo(ad);
  });
  return blocks;
}

/// One parsed candidate event, before the guide has confirmed anything —
/// Part 3 item 2's MANDATORY preview operates on a list of these, never on
/// anything already written to Firestore. `include` lets the guide drop a
/// misparsed candidate from the preview without discarding the rest.
class ParsedCalendarEvent {
  DateTime date;
  // Master Task Part 1 — null means single-day, same meaning as
  // `CalendarEvent.endDate`. Settable in the preview (a "Range" toggle next
  // to the date button) or the calendar view's edit dialog.
  DateTime? endDate;
  // Master Task Part 2 — defaults to `kDefaultEventType` ("other"); the AI
  // extraction sets its own inferred guess, and the guide can correct it in
  // the preview or later from the calendar view.
  String type;
  String title;
  String note;
  bool include;
  // Part 8 item 3 — settable in the preview screen before saving (a shared
  // control applied to every event in the paste at once) and later, per
  // event, from the calendar view's edit dialog. Always a FRESH, mutable
  // list (never the same shared list instance across events) — toggling one
  // event's offsets must never accidentally toggle another's.
  List<String> notifyOffsets;

  ParsedCalendarEvent({
    required this.date,
    this.endDate,
    String? type,
    required this.title,
    required this.note,
    this.include = true,
    List<String>? notifyOffsets,
  })  : type = (type != null && kEventTypes.contains(type))
            ? type
            : kDefaultEventType,
        notifyOffsets = notifyOffsets ?? List<String>.from(kDefaultNotifyOffsets);
}

/// Calls the `extractCalendarEvents` Cloud Function (Part 3) — writes
/// NOTHING. Returns candidates for the guide to review, edit and confirm;
/// [saveTextBlockWithEvents] above is the only thing in this file that
/// actually writes to Firestore.
Future<List<ParsedCalendarEvent>> extractCalendarEventsFromText(
    String rawText) async {
  final callable =
      FirebaseFunctions.instanceFor(region: kCalendarFunctionsRegion)
          .httpsCallable('extractCalendarEvents');
  final result = await callable.call<Map<String, dynamic>>({
    'rawText': rawText,
  });

  final data = Map<String, dynamic>.from(result.data as Map);
  final rawEvents = (data['events'] as List<dynamic>? ?? []);

  return rawEvents.map((e) {
    final map = Map<String, dynamic>.from(e as Map);
    final dateStr = (map['date'] ?? '').toString();
    final parsed = DateTime.tryParse(dateStr) ?? DateTime.now();
    // Master Task Part 1 — `endDate` is only ever present when the server
    // already validated it as a real, well-formed date that doesn't
    // precede `date` (`validateExtractedEvents` in
    // `functions/calendarEvents.js`); still parsed defensively here rather
    // than trusted blindly.
    final endDateRaw = map['endDate'];
    final endDateParsed = endDateRaw is String && endDateRaw.isNotEmpty
        ? DateTime.tryParse(endDateRaw)
        : null;
    return ParsedCalendarEvent(
      date: DateTime(parsed.year, parsed.month, parsed.day),
      endDate: endDateParsed == null
          ? null
          : DateTime(
              endDateParsed.year, endDateParsed.month, endDateParsed.day),
      // Master Task Part 2 item 4 — the server already coerces an
      // unrecognised type to "other" (`DEFAULT_EVENT_TYPE`), so this only
      // needs its own defensive fallback for a genuinely missing field.
      type: (map['type'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      note: (map['note'] ?? '').toString(),
    );
  }).toList();
}

/// Writes a text block plus every event parsed from it, in ONE batch — a
/// block and its events either all land or none do, so a preview the guide
/// already confirmed can never end up with some events saved and some
/// silently dropped by a mid-write failure.
///
/// Every event's `scope`/`ownerGuideId` is derived from THIS function's own
/// [scope]/[ownerGuideId] parameters, never from anything per-event — Part
/// 4's whole two-layer model depends on a block and its events never
/// disagreeing about which layer they belong to.
Future<void> saveTextBlockWithEvents({
  required String rawText,
  required String submittedBy,
  required bool submittedByIsHod,
  required String scope,
  required String? ownerGuideId,
  required List<ParsedCalendarEvent> parsedEvents,
}) async {
  _assertCanMutate(scope: scope, actingIsHod: submittedByIsHod);

  final db = GuideDb.instance;
  final blockRef = db.collection('calendarTextBlocks').doc();
  final batch = db.batch();

  batch.set(blockRef, {
    'rawText': rawText,
    'submittedBy': submittedBy,
    'submittedAt': FieldValue.serverTimestamp(),
    'scope': scope,
    'ownerGuideId': ownerGuideId,
  });

  for (final e in parsedEvents.where((e) => e.include)) {
    _assertValidRange(e.date, e.endDate);
    final eventRef = db.collection('calendarEvents').doc();
    batch.set(eventRef, {
      'eventDate': Timestamp.fromDate(e.date),
      'endDate': e.endDate == null ? null : Timestamp.fromDate(e.endDate!),
      'type': e.type,
      'title': e.title,
      'note': e.note,
      'sourceTextBlockId': blockRef.id,
      'scope': scope,
      'ownerGuideId': ownerGuideId,
      'createdAt': FieldValue.serverTimestamp(),
      'editedAt': null,
      'editedBy': null,
      // Part 8 item 2 — never write an empty list; an event whose selection
      // was toggled down to nothing falls back to the same default the
      // Cloud Function would otherwise apply, so what's saved always
      // matches what the UI showed as selected.
      'notifyOffsets': e.notifyOffsets.isNotEmpty
          ? e.notifyOffsets
          : kDefaultNotifyOffsets,
    });
  }

  await batch.commit();
}

/// Part 5 item 6 — edits a text block's raw text and REPLACES its existing
/// events with a freshly re-extracted set, rather than adding a second set
/// alongside the old one. The text block keeps its identity (same doc id,
/// same `sourceTextBlockId` every event it ever produces carries) — only
/// `rawText` changes (plus `editedAt`/`editedBy`), and `scope`/`ownerGuideId`
/// are re-read fresh from Firestore and reused UNCHANGED (never taken from
/// the caller) so an edit can never move a block into the other layer.
///
/// Delete-old-events + write-new-events + update-the-block-doc all happen in
/// ONE batch, same atomicity guarantee [saveTextBlockWithEvents] already
/// relies on: a batch either commits entirely or not at all, so there is no
/// possible intermediate state where the old events are gone but the new
/// ones never landed (or vice versa) — a failure here leaves the ORIGINAL
/// rawText and ORIGINAL events completely untouched, by construction, not
/// merely in the common case. This is what makes editing update rather than
/// duplicate: nothing outside this one commit ever sees a mix of old and
/// new events for the same block.
Future<void> updateTextBlockWithEvents({
  required String blockId,
  required String rawText,
  required String editedBy,
  required bool actingIsHod,
  required List<ParsedCalendarEvent> parsedEvents,
}) async {
  final db = GuideDb.instance;
  final blockRef = db.collection('calendarTextBlocks').doc(blockId);
  final blockSnap = await blockRef.get();
  if (!blockSnap.exists) {
    throw StateError('This text block no longer exists.');
  }

  final blockData = blockSnap.data() ?? {};
  final scope = (blockData['scope'] ?? kScopePersonal).toString();
  final ownerGuideId = blockData['ownerGuideId'] as String?;
  _assertCanMutate(scope: scope, actingIsHod: actingIsHod);

  final oldEventsSnap =
      await _eventsOfBlock(db, blockId, scope, ownerGuideId);

  final batch = db.batch();

  batch.update(blockRef, {
    'rawText': rawText,
    'editedAt': FieldValue.serverTimestamp(),
    'editedBy': editedBy,
  });

  for (final doc in oldEventsSnap.docs) {
    batch.delete(doc.reference);
  }

  for (final e in parsedEvents.where((e) => e.include)) {
    _assertValidRange(e.date, e.endDate);
    final eventRef = db.collection('calendarEvents').doc();
    batch.set(eventRef, {
      'eventDate': Timestamp.fromDate(e.date),
      'endDate': e.endDate == null ? null : Timestamp.fromDate(e.endDate!),
      'type': e.type,
      'title': e.title,
      'note': e.note,
      'sourceTextBlockId': blockId,
      'scope': scope,
      'ownerGuideId': ownerGuideId,
      'createdAt': FieldValue.serverTimestamp(),
      'editedAt': null,
      'editedBy': null,
      'notifyOffsets': e.notifyOffsets.isNotEmpty
          ? e.notifyOffsets
          : kDefaultNotifyOffsets,
    });
  }

  await batch.commit();
}

/// The events one text block produced. Hierarchy: the `scope` (and, for a
/// personal block, `ownerGuideId`) equality filters are what let the security
/// rules prove the read — mandatory events are readable by every admin,
/// personal ones only by their owner.
Future<QuerySnapshot<Map<String, dynamic>>> _eventsOfBlock(
  FirebaseFirestore db,
  String blockId,
  String scope,
  String? ownerGuideId,
) {
  var q = db
      .collection('calendarEvents')
      .where('sourceTextBlockId', isEqualTo: blockId)
      .where('scope', isEqualTo: scope);
  if (scope != kScopeMandatory) {
    q = q.where('ownerGuideId', isEqualTo: ownerGuideId);
  }
  return q.get();
}

/// Part 5 item 3 — deletes a text block and EVERY event it produced, in one
/// batch. Returns the count of events that were deleted, so the caller can
/// show "this will delete N events" before committing — this function
/// itself does not prompt; the confirmation UI is the caller's job.
///
/// Re-reads the block's OWN `scope` fresh before doing anything (never
/// trusts a scope the caller might already have in memory), so
/// [_assertCanMutate] is checking real, current data.
Future<int> deleteTextBlockAndItsEvents({
  required String blockId,
  required bool actingIsHod,
}) async {
  final db = GuideDb.instance;
  final blockRef = db.collection('calendarTextBlocks').doc(blockId);
  final blockSnap = await blockRef.get();
  if (!blockSnap.exists) return 0;

  final scope = (blockSnap.data()?['scope'] ?? kScopePersonal).toString();
  final ownerGuideId = blockSnap.data()?['ownerGuideId'] as String?;
  _assertCanMutate(scope: scope, actingIsHod: actingIsHod);

  final eventsSnap = await _eventsOfBlock(db, blockId, scope, ownerGuideId);

  final batch = db.batch();
  for (final doc in eventsSnap.docs) {
    batch.delete(doc.reference);
  }
  batch.delete(blockRef);
  await batch.commit();
  return eventsSnap.docs.length;
}

/// Part 5 item 4 — edits a single event in place (date, end date, type,
/// title, note, and — Part 8 item 3 — its notification offsets), without
/// touching the source text block's `rawText` at all: a correction here is
/// a one-off fix to the derived event, not a rewrite of the original
/// authored text — re-pasting is how you change the text; this is how you
/// fix one date/type/title/note/offsets without re-pasting anything.
///
/// Re-reads the event's OWN `scope` fresh before doing anything, same
/// reasoning as [deleteTextBlockAndItsEvents]. Validates the range the same
/// way the create paths do ([_assertValidRange]) — this is the ONLY place a
/// guide can turn a single-day event into a range or back, from the
/// calendar view (Master Task Part 4 item 3).
Future<void> editEvent({
  required String eventId,
  required DateTime eventDate,
  DateTime? endDate,
  required String type,
  required String title,
  required String note,
  required String editedBy,
  required bool actingIsHod,
  required List<String> notifyOffsets,
}) async {
  _assertValidRange(eventDate, endDate);

  final db = GuideDb.instance;
  final ref = db.collection('calendarEvents').doc(eventId);
  final snap = await ref.get();
  if (!snap.exists) return;

  final scope = (snap.data()?['scope'] ?? kScopePersonal).toString();
  _assertCanMutate(scope: scope, actingIsHod: actingIsHod);

  await ref.update({
    'eventDate': Timestamp.fromDate(eventDate),
    'endDate': endDate == null ? null : Timestamp.fromDate(endDate),
    'type': kEventTypes.contains(type) ? type : kDefaultEventType,
    'title': title,
    'note': note,
    'editedAt': FieldValue.serverTimestamp(),
    'editedBy': editedBy,
    // Part 8 item 2 — same never-write-empty rule as the create paths.
    'notifyOffsets':
        notifyOffsets.isNotEmpty ? notifyOffsets : kDefaultNotifyOffsets,
  });
}

// -----------------------------------------------------------------------------
// Event type descriptions (Master Task Part 2) — editable meanings, seeded
// on first use, read by both the "manage type meanings" UI and (server-side,
// `functions/calendarEvents.js`'s `fetchTypeDescriptions`) the AI prompt.
// -----------------------------------------------------------------------------

class CalendarEventTypeDescription {
  final String type;
  final String description;
  final DateTime? updatedAt;
  final String? updatedBy;

  CalendarEventTypeDescription({
    required this.type,
    required this.description,
    required this.updatedAt,
    required this.updatedBy,
  });

  factory CalendarEventTypeDescription.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return CalendarEventTypeDescription(
      type: doc.id,
      description: (d['description'] ?? '').toString(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      updatedBy: d['updatedBy'] as String?,
    );
  }
}

/// Writes [kDefaultTypeDescriptions] for any of [kEventTypes] that doesn't
/// have a doc yet — "seed sensible defaults on first use" (Master Task Part
/// 2 item 3). Safe to call every time the "manage type meanings" screen
/// opens: an already-seeded (or guide-edited) doc is left completely
/// untouched, since this only ever creates what's MISSING, never overwrites
/// what's there.
Future<void> ensureEventTypeDescriptionsSeeded() async {
  final col =
      GuideDb.instance.collection('calendarEventTypeDescriptions');
  final existing = await col.get();
  final existingIds = existing.docs.map((d) => d.id).toSet();

  final batch = GuideDb.instance.batch();
  var needsCommit = false;
  for (final type in kEventTypes) {
    if (existingIds.contains(type)) continue;
    batch.set(col.doc(type), {
      'description': kDefaultTypeDescriptions[type],
      'updatedAt': null,
      'updatedBy': null,
    });
    needsCommit = true;
  }
  if (needsCommit) await batch.commit();
}

/// Every type's current description, defaulting to [kDefaultTypeDescriptions]
/// for any type whose doc is missing — the same in-memory-fallback
/// reasoning as the Cloud Function's own `fetchTypeDescriptions`, so a
/// caller here never needs to await [ensureEventTypeDescriptionsSeeded]
/// first just to get a sensible value.
Future<Map<String, CalendarEventTypeDescription>>
    fetchEventTypeDescriptions() async {
  final snap = await GuideDb.instance
      .collection('calendarEventTypeDescriptions')
      .get();
  final byType = <String, CalendarEventTypeDescription>{
    for (final doc in snap.docs)
      if (kEventTypes.contains(doc.id)) doc.id: CalendarEventTypeDescription.fromDoc(doc),
  };
  for (final type in kEventTypes) {
    byType.putIfAbsent(
        type,
        () => CalendarEventTypeDescription(
              type: type,
              description: kDefaultTypeDescriptions[type] ?? '',
              updatedAt: null,
              updatedBy: null,
            ));
  }
  return byType;
}

/// Part 2 item 2 — the guide/HOD can change a type's meaning at any time,
/// with no redeploy: this is the ONE write path for that.
Future<void> updateEventTypeDescription({
  required String type,
  required String description,
  required String updatedBy,
}) async {
  if (!kEventTypes.contains(type)) {
    throw ArgumentError('Unknown event type: $type');
  }
  await GuideDb.instance
      .collection('calendarEventTypeDescriptions')
      .doc(type)
      .set({
    'description': description,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': updatedBy,
  }, SetOptions(merge: true));
}
