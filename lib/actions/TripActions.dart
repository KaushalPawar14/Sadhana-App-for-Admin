import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/ExpeditionModel.dart';
import '../utils/GuideDb.dart';

/// Trips (Expeditions), as shared writes with no screen in them: the Expeditions
/// screens and the AI agent both create trips, move their status and mark
/// attendance through these.
///
/// Registering for a trip, and writing a reflection or an experience, are the
/// STUDENT'S actions and are not here.

/// A trip's life: upcoming → ongoing → completed. Separate from `archived`, which
/// the server sets the day after the trip's last day.
const List<String> kTripStatuses = ['upcoming', 'ongoing', 'completed'];

/// Creates a trip.
///
/// [start] is `tripDate`, which every older reader uses; [end] is `endDate`, the
/// last day (the same date for a one-day trip). The trip moves to History the day
/// after IT. [targetGender] is who the trip is for: Guides and Male Enablers make
/// boys' trips, Female Enablers girls', and a HOD chooses — the rules refuse any
/// other combination.
///
/// @return the new trip's id
Future<String> createTrip({
  required String createdBy,
  required String title,
  required DateTime start,
  required DateTime end,
  required String targetGender,
  String description = '',
  String location = '',
  DateTime? registrationDeadline,
  int? maxParticipants,
}) async {
  if (title.trim().isEmpty) throw ArgumentError('A trip needs a title');
  final problem = tripDatesProblem(start, end);
  if (problem != null) throw ArgumentError(problem);
  if (targetGender != 'male' && targetGender != 'female') {
    throw ArgumentError('Choose Boys or Girls for this trip');
  }

  final ref = await GuideDb.instance.collection('expeditions').add({
    'title': title.trim(),
    'description': description.trim(),
    'location': location.trim(),
    // The start stays `tripDate`, which every older reader already uses; `endDate`
    // is the last day (the same date for a one-day trip). The trip moves to
    // History the day after IT.
    'tripDate': Timestamp.fromDate(start),
    'endDate': Timestamp.fromDate(end),
    'registrationDeadline': registrationDeadline == null
        ? null
        : Timestamp.fromDate(registrationDeadline),
    'createdBy': createdBy,
    'createdAt': FieldValue.serverTimestamp(),
    'maxParticipants': maxParticipants,
    'status': 'upcoming',
    // Who the trip is for, and where it is in its life: active until the day
    // after the trip's END date, when the server sets `archived: true` and it
    // moves to History.
    'targetGender': targetGender,
    'archived': false,
  });
  return ref.id;
}

/// Moves a trip through upcoming → ongoing → completed.
Future<void> setTripStatus(String tripId, String status) async {
  if (!kTripStatuses.contains(status)) {
    throw ArgumentError('Status must be one of: ${kTripStatuses.join(', ')}');
  }
  await GuideDb.instance
      .collection('expeditions')
      .doc(tripId)
      .update({'status': status});
}

/// Marks a registered student Pending, Partially or Fully completed.
///
/// [registrationId] is the registration's id (`{tripId}_{studentUid}`). Only on a
/// trip still active: the rules freeze a registration the moment its trip moves to
/// History. Marking Partially or Fully completed is also what earns the student the
/// "Share your experience" request the morning after the trip ends.
Future<void> setTripAttendance(String registrationId, String attendance) async {
  if (!kAttendanceValues.contains(attendance)) {
    throw ArgumentError('Attendance must be one of: ${kAttendanceValues.join(', ')}');
  }
  await GuideDb.instance
      .collection('expeditionRegistrations')
      .doc(registrationId)
      .update({'attendance': attendance});
}

/// Changes a trip's details. Only what is given changes; the dates are checked together with the ones already saved. The
/// rules refuse a trip that has moved to History.
Future<void> editTrip(
  String tripId, {
  String? title,
  String? description,
  String? location,
  DateTime? start,
  DateTime? end,
  DateTime? registrationDeadline,
  int? maxParticipants,
}) async {
  final ref = GuideDb.instance.collection('expeditions').doc(tripId);
  final data = (await ref.get()).data();
  if (data == null) throw StateError('That trip no longer exists.');
  final update = <String, dynamic>{};
  if (title != null) {
    if (title.trim().isEmpty) throw ArgumentError('A trip needs a title');
    update['title'] = title.trim();
  }
  if (description != null) update['description'] = description.trim();
  if (location != null) update['location'] = location.trim();
  final oldStart = data['tripDate'];
  final oldEnd = data['endDate'];
  final newStart = start ?? (oldStart is Timestamp ? oldStart.toDate() : null);
  final newEnd = end ?? (oldEnd is Timestamp ? oldEnd.toDate() : newStart);
  if (start != null || end != null) {
    if (newStart == null || newEnd == null) throw ArgumentError('A trip needs a start and an end date');
    final problem = tripDatesProblem(newStart, newEnd);
    if (problem != null) throw ArgumentError(problem);
    if (start != null) update['tripDate'] = Timestamp.fromDate(start);
    if (end != null) update['endDate'] = Timestamp.fromDate(end);
  }
  if (registrationDeadline != null) {
    if (newStart != null && registrationDeadline.isAfter(newStart)) {
      throw ArgumentError('The registration deadline cannot be after the trip starts');
    }
    update['registrationDeadline'] = Timestamp.fromDate(registrationDeadline);
  }
  if (maxParticipants != null) {
    if (maxParticipants <= 0) throw ArgumentError('The most students must be at least 1');
    update['maxParticipants'] = maxParticipants;
  }
  if (update.isEmpty) throw ArgumentError('Nothing to change.');
  await ref.update(update);
}
