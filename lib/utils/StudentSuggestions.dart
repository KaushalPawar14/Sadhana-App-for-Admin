/// Master 1 B — the suggestions a guide gets for one student.
///
/// The old shape was a single "recommended next action" with a paragraph of
/// reasoning. One suggestion makes the guide take it or leave it; three to
/// five let him pick the one that fits the boy in front of him, which is the
/// whole point of asking.
///
/// Each one has to answer three questions or it is not worth showing:
/// WHAT to do, WHY it follows from this student's own record, and what the
/// first concrete step is — what to say or do, when, and how much. The server
/// drops any that cannot (`functions/gemini.js`, `normaliseSuggestions`), so
/// anything that arrives here is already meant to be actionable.
library;

/// One suggestion: what, why, and the first step.
class StudentSuggestion {
  /// What the guide should do, in a few words.
  final String action;

  /// Why it follows from this student's evidence. May be empty if the model
  /// gave none — the suggestion is still usable without it.
  final String why;

  /// The concrete first step: what to say or do, when, how much.
  final String next;

  const StudentSuggestion({
    required this.action,
    this.why = '',
    required this.next,
  });

  static StudentSuggestion? from(Object? raw) {
    if (raw is! Map) return null;
    final action = (raw['action'] ?? '').toString().trim();
    final next = (raw['next'] ?? '').toString().trim();
    // Without both of these it is the generic advice the prompt forbids.
    if (action.isEmpty || next.isEmpty) return null;
    return StudentSuggestion(
      action: action,
      why: (raw['why'] ?? '').toString().trim(),
      next: next,
    );
  }

  Map<String, dynamic> toMap() => {'action': action, 'why': why, 'next': next};
}

/// Every usable suggestion in [raw], in order.
///
/// Anything malformed is dropped rather than rendered as a blank line — a
/// card with an empty bullet reads as a bug in the app rather than a thin
/// record for the student.
List<StudentSuggestion> parseSuggestions(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .map(StudentSuggestion.from)
      .whereType<StudentSuggestion>()
      .toList();
}

/// The suggestions to show for a cached document, falling back to the single
/// action a document written before this change carries.
///
/// A guide who has not pressed Refresh since the upgrade should still see
/// what he generated last month, not an empty card.
List<StudentSuggestion> suggestionsOf(Map<String, dynamic>? data) {
  if (data == null) return const [];
  final parsed = parseSuggestions(data['suggestions']);
  if (parsed.isNotEmpty) return parsed;

  final action = (data['recommendedNextAction'] ?? '').toString().trim();
  if (action.isEmpty) return const [];
  return [
    StudentSuggestion(
      action: action,
      why: (data['recommendedReasoning'] ?? '').toString().trim(),
      // An old document has no separate next step; the action was the step.
      next: action,
    ),
  ];
}
