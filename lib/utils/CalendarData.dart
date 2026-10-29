import 'AdminProfile.dart';
import 'AutoCalendar.dart';
import 'CalendarQueries.dart';

/// What the Guide Calendar screen loads, behind one interface: the app uses the
/// Firestore-backed one (a pass-through to `visibleEventsFor` / `visibleTextBlocksFor`
/// in `CalendarQueries.dart`, unchanged); a widget test hands in plain events.
abstract class CalendarData {
  static CalendarData instance = const FirestoreCalendarData();

  /// Every event this guide may see (all mandatory ones plus their own personal ones).
  Future<List<CalendarEvent>> events(String guideId);

  /// The text blocks this guide may see.
  Future<List<CalendarTextBlock>> textBlocks(String guideId);

  /// The automatic events (targets, follow-ups, meetings, trips, competitions, planned interactions), live: a new list every time
  /// a source changes. A fake that does not override it has none.
  Stream<List<CalendarEvent>> automaticEvents(String guideId) => Stream.value(const <CalendarEvent>[]);
}

class FirestoreCalendarData implements CalendarData {
  const FirestoreCalendarData();

  @override
  Future<List<CalendarEvent>> events(String guideId) => visibleEventsFor(guideId);

  @override
  Future<List<CalendarTextBlock>> textBlocks(String guideId) => visibleTextBlocksFor(guideId);

  @override
  Stream<List<CalendarEvent>> automaticEvents(String guideId) {
    final me = AdminProfileProvider.current;
    return me == null ? Stream.value(const <CalendarEvent>[]) : AutoCalendarFeed(me).events();
  }
}
