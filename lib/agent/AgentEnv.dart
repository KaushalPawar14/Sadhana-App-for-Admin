import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../actions/PriorityActions.dart';
import '../theme/ThemeModeController.dart';
import '../utils/AdminProfile.dart';
import '../utils/GuideDb.dart';
import '../utils/StudentScope.dart';

/// Something the agent could not do, in words a guide can act on.
///
/// Never a stack trace, never a bare error code: the message goes back to the model, which tells
/// the guide.
class AgentFailure implements Exception {
  AgentFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a tool needs to know about the guide it is working for, and how to reach their data.
///
/// ---------------------------------------------------------------------------
/// Scope is here, once
/// ---------------------------------------------------------------------------
/// Every read the agent makes about a student goes through [students] or [scope], which are
/// [StudentScope] of the SIGNED-IN admin: HOD all; Guide own + team + unassigned boys; Male Enabler
/// own + unassigned boys; Female Enabler own + unassigned girls; category separation as built. They
/// run under the guide's own sign-in, so the security rules apply on top. There is no
/// "everything" accessor in this class, so no tool can forget a filter.
///
/// A student outside the scope is simply not there: [student] says "I can't find that student among
/// yours", the same sentence as for a name that does not exist, so nothing about them leaks — not
/// that they exist, not how many there are.
class AgentEnv {
  AgentEnv({
    AdminProfile? profile,
    FirebaseFirestore? db,
    DateTime Function()? clock,
    this.themes,
    this.signOut,
  })  : _profile = profile,
        _db = db,
        _clock = clock;

  final AdminProfile? _profile;
  final FirebaseFirestore? _db;
  final DateTime Function()? _clock;

  /// The phone's appearance setting, for `appearance_set`.
  final ThemeModeController? themes;

  /// Signs the guide out of this phone, for `sign_out`.
  final Future<void> Function()? signOut;

  AdminProfile get me => _profile ?? AdminProfileProvider.require();
  FirebaseFirestore get db => _db ?? GuideDb.instance;
  DateTime get now => (_clock ?? DateTime.now)();
  StudentScope get scope => StudentScope(me);

  // ---------------------------------------------------------------------------
  // Students in scope
  // ---------------------------------------------------------------------------
  Map<String, Map<String, dynamic>>? _students;
  DateTime? _studentsAt;
  PriorityList? _priority;
  DateTime? _priorityAt;

  /// Forget what was read, so the next look sees the changes just made.
  void invalidate() {
    _students = null;
    _studentsAt = null;
    _priority = null;
    _priorityAt = null;
  }

  /// The students THIS admin may see: uid → their `users` document. Read once and kept for a
  /// minute, so a plan touching twenty students reads the roster once.
  Future<Map<String, Map<String, dynamic>>> students() async {
    final at = _studentsAt;
    if (_students != null && at != null && now.difference(at) < const Duration(minutes: 1)) {
      return _students!;
    }
    final snap = await scope.studentsGet();
    final out = <String, Map<String, dynamic>>{};
    for (final d in snap.docs) {
      final data = d.data();
      if ((data['name'] ?? '').toString().trim().isEmpty) continue;
      out[d.id] = data;
    }
    _students = out;
    _studentsAt = now;
    return out;
  }

  /// One student of this admin's, or a failure that says no more than "not among yours".
  Future<Map<String, dynamic>> student(String uid) async {
    final all = await students();
    final s = all[uid];
    if (s == null) throw AgentFailure("I can't find that student among your students.");
    return s;
  }

  /// The students' priority list for this admin: the same computation the screen shows.
  Future<PriorityList> priority() async {
    final at = _priorityAt;
    if (_priority != null && at != null && now.difference(at) < const Duration(minutes: 1)) {
      return _priority!;
    }
    _priority = await loadPriorityList();
    _priorityAt = now;
    return _priority!;
  }

  // ---------------------------------------------------------------------------
  // Words
  // ---------------------------------------------------------------------------
  /// The guide's name for an admin id, falling back to the id.
  String adminName(String id) {
    if (id.isEmpty) return '';
    return me.adminById(id)?.displayName ?? id;
  }

  /// "Stay at FOLK" etc. as the app says it.
  static String residenceOf(Map<String, dynamic> student) => (student['role'] ?? '').toString();
}

/// A real calendar day from the agent's `YYYY-MM-DD`.
DateTime agentDay(Object? value) {
  final s = (value ?? '').toString();
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) throw AgentFailure('That date ("$s") is not a date I can read.');
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// A moment from the agent's `YYYY-MM-DD` and optional `HH:mm`; [fallback] when no time was given.
DateTime agentWhen(Object? date, Object? time, {TimeOfDay fallback = const TimeOfDay(hour: 18, minute: 0)}) {
  final day = agentDay(date);
  final t = (time ?? '').toString();
  final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(t);
  final hour = m == null ? fallback.hour : int.parse(m[1]!);
  final minute = m == null ? fallback.minute : int.parse(m[2]!);
  return DateTime(day.year, day.month, day.day, hour, minute);
}

/// "2026-10-26" for a moment, the way the agent speaks.
String agentDateOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A Firestore timestamp (or a DateTime) as `YYYY-MM-DD HH:mm`, or null.
String? agentStamp(Object? v) {
  DateTime? d;
  if (v is Timestamp) d = v.toDate();
  if (v is DateTime) d = v;
  if (d == null) return null;
  return '${agentDateOf(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
