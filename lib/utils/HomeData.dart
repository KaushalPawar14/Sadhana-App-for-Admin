import 'package:flutter/material.dart';

import 'CalendarQueries.dart';
import 'GoalCompoundQueries.dart';
import 'StudentScope.dart';
import 'UnseenFeatureBadge.dart';
import 'GuideDb.dart';

/// The data behind the Home dashboard. Each member is an existing source the app
/// already reads elsewhere (see `Home/FolkBoysEntry.dart`'s header), scoped to the
/// signed-in admin exactly as it is there. Behind an interface only so a widget
/// test can hand in plain values instead of Firestore.
abstract class HomeData {
  /// Replaced by tests; the app always uses the Firestore-backed one.
  static HomeData instance = const FirestoreHomeData();

  /// This guide's compound targets (`guideTargets/{guide}/targets`).
  Stream<List<CompoundTarget>> targets(String guide);

  /// How many students the signed-in admin's roster has.
  Stream<int> studentCount();

  /// The calendar events this guide may see.
  Future<List<CalendarEvent>> events(String guide);

  /// Wraps the Calendar tile with its "a mandatory event landed since you last
  /// looked" dot.
  Widget calendarBadge({required Widget child});
}

class FirestoreHomeData implements HomeData {
  const FirestoreHomeData();

  @override
  Stream<List<CompoundTarget>> targets(String guide) =>
      compoundTargetsStream(guide);

  @override
  Stream<int> studentCount() =>
      StudentScope.current().studentsStream().map((snap) => snap.docs.length);

  @override
  Future<List<CalendarEvent>> events(String guide) => visibleEventsFor(guide);

  @override
  Widget calendarBadge({required Widget child}) => UnseenFeatureBadge(
        featureKey: 'calendarEvents',
        dotOffset: const Offset(10, 10),
        // The tile sits in a square pair: it fills the cell, so both tiles stay equal.
        fillParent: true,
        latestQuery: (g) => GuideDb.instance
            .collection('calendarEvents')
            .where('scope', isEqualTo: kScopeMandatory)
            .snapshots(),
        child: child,
      );
}
