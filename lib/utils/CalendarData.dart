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
}

class FirestoreCalendarData implements CalendarData {
  const FirestoreCalendarData();

  @override
  Future<List<CalendarEvent>> events(String guideId) => visibleEventsFor(guideId);

  @override
  Future<List<CalendarTextBlock>> textBlocks(String guideId) => visibleTextBlocksFor(guideId);
}
