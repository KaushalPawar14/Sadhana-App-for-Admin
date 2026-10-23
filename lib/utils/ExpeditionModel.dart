import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'AdminProfile.dart';

/// Trips (expeditions): the plain rules, kept out of the screens so they can be tested alone.
///
/// A trip is for ONE gender (`targetGender`). It is ACTIVE until the end of its trip date; the day after,
/// the server marks it `archived: true` and it lives under History, read only (`functions/expeditions.js`).
/// Each registration carries the student's `attendance`: pending (the default), partial or full.

const String kAttendancePending = 'pending';
const String kAttendancePartial = 'partial';
const String kAttendanceFull = 'full';
const List<String> kAttendanceValues = [kAttendancePending, kAttendancePartial, kAttendanceFull];

/// A registration's attendance; anything missing or unknown reads as pending.
String attendanceOf(Map<String, dynamic> registration) {
  final v = (registration['attendance'] ?? '').toString();
  return kAttendanceValues.contains(v) ? v : kAttendancePending;
}

String attendanceLabel(String attendance) {
  switch (attendance) {
    case kAttendancePartial:
      return 'Partially completed';
    case kAttendanceFull:
      return 'Fully completed';
    default:
      return 'Pending';
  }
}

/// How many students are in each state.
class AttendanceSummary {
  const AttendanceSummary({this.pending = 0, this.partial = 0, this.full = 0});

  final int pending;
  final int partial;
  final int full;

  int get total => pending + partial + full;
}

AttendanceSummary summariseAttendance(Iterable<Map<String, dynamic>> registrations) {
  var pending = 0, partial = 0, full = 0;
  for (final r in registrations) {
    switch (attendanceOf(r)) {
      case kAttendancePartial:
        partial++;
      case kAttendanceFull:
        full++;
      default:
        pending++;
    }
  }
  return AttendanceSummary(pending: pending, partial: partial, full: full);
}

/// The gender a trip made by this admin is for: a Guide or Male Enabler makes boys' trips, a Female Enabler
/// girls'. A HOD chooses (null = not decided yet).
String? tripTargetGenderFor(AdminProfile profile) {
  if (profile.isHod) return null;
  return profile.isFemaleEnabler ? 'female' : 'male';
}

String targetGenderLabel(String? targetGender) {
  switch (targetGender) {
    case 'male':
      return 'Boys';
    case 'female':
      return 'Girls';
    default:
      return '';
  }
}

bool tripArchived(Map<String, dynamic> trip) => trip['archived'] == true;

String tripDateText(Object? value) =>
    value is Timestamp ? DateFormat('dd MMM yyyy').format(value.toDate()) : 'Not set';

/// The longest a trip may run. A fortnight is a long trip; this only stops a typo (a year, not a day).
const int kMaxTripDays = 60;

/// A trip's last day: its end date, or — for a trip made before end dates existed — its one date. An end
/// before the start is ignored, matching the server, so a hand-edited trip never shows as ending before
/// it begins.
DateTime? tripEndOf(Map<String, dynamic> trip) {
  final start = trip['tripDate'];
  final end = trip['endDate'];
  final s = start is Timestamp ? start.toDate() : null;
  final e = end is Timestamp ? end.toDate() : null;
  if (e != null && (s == null || !DateTime(e.year, e.month, e.day).isBefore(DateTime(s.year, s.month, s.day)))) {
    return e;
  }
  return s;
}

/// "25 Aug 2026" for a one-day trip, "18 Oct – 20 Oct 2026" for a longer one, "Not set" with no date.
String tripDatesText(Map<String, dynamic> trip) {
  final start = trip['tripDate'];
  final end = tripEndOf(trip);
  if (start is! Timestamp || end == null) return tripDateText(start);
  final s = start.toDate();
  final sameDay = s.year == end.year && s.month == end.month && s.day == end.day;
  if (sameDay) return tripDateText(start);
  final full = DateFormat('dd MMM yyyy');
  return s.year == end.year
      ? '${DateFormat('dd MMM').format(s)} – ${full.format(end)}'
      : '${full.format(s)} – ${full.format(end)}';
}

/// Why a trip's dates cannot be saved, or null if they are fine.
String? tripDatesProblem(DateTime? start, DateTime? end) {
  if (start == null) return 'Choose the trip start date';
  if (end == null) return 'Choose the trip end date';
  final s = DateTime(start.year, start.month, start.day);
  final e = DateTime(end.year, end.month, end.day);
  if (e.isBefore(s)) return 'The end date cannot be before the start date';
  final days = DateTime.utc(e.year, e.month, e.day).difference(DateTime.utc(s.year, s.month, s.day)).inDays + 1;
  if (days > kMaxTripDays) return 'A trip can run for at most $kMaxTripDays days';
  return null;
}

/// A History card's title: the place and the date, e.g. "Vrindavan · 25 Aug 2026" (or the span, for a longer
/// trip). With no place, the trip's own title stands in for it.
String historyTitle(Map<String, dynamic> trip) {
  final place = (trip['location'] ?? '').toString().trim();
  final name = place.isNotEmpty ? place : (trip['title'] ?? 'Trip').toString().trim();
  return '$name · ${tripDatesText(trip)}';
}

/// Newest trip date first (History); a trip with no date goes last.
int newestFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
  final da = a['tripDate'];
  final db = b['tripDate'];
  if (da is! Timestamp) return db is Timestamp ? 1 : 0;
  if (db is! Timestamp) return -1;
  return db.compareTo(da);
}

/// Soonest first (the active list).
int soonestFirst(Map<String, dynamic> a, Map<String, dynamic> b) => -newestFirst(a, b);
