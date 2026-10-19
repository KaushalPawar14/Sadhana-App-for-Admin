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

/// A History card's title: the place and the date, e.g. "Vrindavan · 25 Aug 2026". With no place, the trip's
/// own title stands in for it.
String historyTitle(Map<String, dynamic> trip) {
  final place = (trip['location'] ?? '').toString().trim();
  final name = place.isNotEmpty ? place : (trip['title'] ?? 'Trip').toString().trim();
  return '$name · ${tripDateText(trip['tripDate'])}';
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
