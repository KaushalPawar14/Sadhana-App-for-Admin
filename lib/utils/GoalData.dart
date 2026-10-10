import 'GoalCompoundQueries.dart';

/// What the Targets screen ("Your targets") reads, behind one interface: the app uses
/// the Firestore-backed one (a pass-through to `compoundTargetsStream`, unchanged); a
/// widget test hands in plain values.
abstract class GoalData {
  static GoalData instance = const FirestoreGoalData();

  /// This guide's compound targets.
  Stream<List<CompoundTarget>> targets(String guideId);
}

class FirestoreGoalData implements GoalData {
  const FirestoreGoalData();

  @override
  Stream<List<CompoundTarget>> targets(String guideId) => compoundTargetsStream(guideId);
}
