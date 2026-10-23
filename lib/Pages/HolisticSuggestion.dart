import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../actions/SuggestionActions.dart';
import '../Services/GeminiService.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentSuggestions.dart';
import '../theme/GuideTheme.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideWait.dart';

/// Holistic "suggested next action" (Phase 5, item 1 — final piece).
///
/// Pulls together what this profile page already shows about a student, plus
/// their approved interaction logs and most recent LIT reading, and asks Gemini
/// for ONE current suggested next step with reasoning.
///
/// **On demand only.** Nothing here runs on page view. Gemini is called only
/// when the guide presses the button, and the result is cached in Firestore so
/// reopening the profile costs nothing.
///
/// **Guidance, never a decision** (Section 1). The output carries a permanent
/// disclaimer and is never shown to a student.
///
/// **LIT is passed as three separate readings.** `L`, `I` and `T` go into the
/// prompt as three independent lines and the prompt forbids combining them.
/// Nothing here computes a total, average, level or tier.
class HolisticSuggestionSection extends StatefulWidget {
  final String studentUid;
  final String studentName;

  /// The `users/{uid}` map this page has already streamed. Passed in rather
  /// than re-queried, so opening the profile triggers no extra read.
  final Map<String, dynamic> profileData;

  const HolisticSuggestionSection({
    super.key,
    required this.studentUid,
    required this.studentName,
    required this.profileData,
  });

  @override
  State<HolisticSuggestionSection> createState() =>
      _HolisticSuggestionSectionState();
}

class _HolisticSuggestionSectionState extends State<HolisticSuggestionSection> {
  final FirebaseFirestore _firestore = GuideDb.instance;

  bool _working = false;

  DocumentReference<Map<String, dynamic>> get _docRef =>
      _firestore.collection('holisticSuggestions').doc(widget.studentUid);

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------

  Future<void> _generate() async {
    setState(() => _working = true);

    try {
      // One shared function (actions/SuggestionActions.dart): the AI agent generates suggestions
      // through exactly this.
      final count = await generateStudentSuggestions(
        studentUid: widget.studentUid,
        studentName: widget.studentName,
        profileData: widget.profileData,
      );

      if (!mounted) return;
      showSnackbar(
          context,
          "$count suggestions generated",
          Colors.green,
          Icons.check_circle);
    } on GeminiException catch (e) {
      if (mounted) showSnackbar(context, e.message, Colors.red, Icons.error);
    } catch (e) {
      if (mounted) {
        showSnackbar(context, "Could not generate: $e", Colors.red,
            Icons.error);
      }
    }

    if (mounted) setState(() => _working = false);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _docRef.snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final suggestions = suggestionsOf(data);
        final generatedAt = data?['generatedAt'];
        final generatedBy = (data?['generatedBy'] ?? '').toString();
        final hasSuggestion = suggestions.isNotEmpty;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.g.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: context.g.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasSuggestion) ...[
                for (var i = 0; i < suggestions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  _suggestionTile(i + 1, suggestions[i]),
                ],
                const SizedBox(height: 12),
                _disclaimer(),
                const SizedBox(height: 10),
                if (generatedAt is Timestamp)
                  Text(
                    "Last generated "
                    "${DateFormat('dd MMM yyyy, hh:mm a').format(generatedAt.toDate())}"
                    "${generatedBy.isEmpty ? '' : ' · $generatedBy'}",
                    style: TextStyle(
                      fontSize: 11,
                      color: context.g.mutedText,
                    ),
                  ),
              ] else
                Text(
                  "Three to five things you could do with this student, "
                  "each with why and a first step. Draws on their sadhana "
                  "counters, book progress, approved interaction logs, most "
                  "recent LIT reading and your own active targets. Runs only "
                  "when you ask.",
                  style: TextStyle(fontSize: 13, color: context.g.mutedText),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: _working
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: GuideWait(),
                      )
                    : OutlinedButton.icon(
                        onPressed: _generate,
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text(
                          hasSuggestion
                              ? "Refresh suggestions"
                              : "Generate suggestions",
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.g.brass,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// One suggestion: what to do, why, and the first step.
  ///
  /// The step is the part a guide actually acts on, so it is given its own
  /// labelled line rather than being folded into the reasoning where it
  /// would be easy to skim past.
  Widget _suggestionTile(int number, StudentSuggestion s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            "$number.",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.g.brass,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.action,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              if (s.why.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  s.why,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: context.g.mutedText,
                  ),
                ),
              ],
              const SizedBox(height: 5),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.arrow_right_alt,
                      size: 16, color: context.g.success),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      s.next,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: context.g.text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Section 1 — "AI assists. Guide decides. Always." Stated in the UI, not
  /// just in the docs.
  Widget _disclaimer() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.g.warning.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.g.warning.withValues(alpha: .14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: context.g.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "AI-generated suggestions — guide judgment decides the actual "
              "next step.",
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: context.g.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
