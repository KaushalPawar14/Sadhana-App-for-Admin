import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Services/GeminiService.dart';
import '../Services/UpdateFCM.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentScope.dart';
import '../theme/GuideTheme.dart';
import '../utils/GuideDb.dart';

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

  /// `collection where <uidField> == this student`, plus the scope filter the
  /// security rules need (built from the `users` map this page already holds).
  Query<Map<String, dynamic>> _scoped(String collection, String uidField) =>
      StudentScope.current().constrainForStudent(
        _firestore
            .collection(collection)
            .where(uidField, isEqualTo: widget.studentUid),
        StudentRef.fromUser(widget.studentUid, widget.profileData),
      );

  // ---------------------------------------------------------------------------
  // Gathering
  // ---------------------------------------------------------------------------

  /// Assembles the evidence block sent to Gemini.
  ///
  /// Reads only collections this profile page already displays — `scorecard`
  /// and `booksRead` — plus the two Phase 5 collections. No new ABCDE
  /// collection is introduced, and none of these reads happen until the guide
  /// presses the button.
  Future<String> _gatherContext() async {
    final lines = <String>[];

    final role = (widget.profileData['role'] ?? '').toString();
    final guideId = (widget.profileData['guideId'] ?? '').toString();
    if (role.isNotEmpty) lines.add("Residence: $role");
    if (guideId.isNotEmpty) lines.add("Assigned guide: $guideId");

    // --- Sadhana counters (as shown in the Total Points section) ------------
    try {
      final scorecard =
          await _firestore.collection('scorecard').doc(widget.studentName).get();
      final s = scorecard.data();
      if (s != null) {
        lines.add(
          "Lifetime sadhana counters — chanting rounds: ${s['totalChantRounds'] ?? 0}, "
          "book reading: ${s['totalBookRead'] ?? 0}, "
          "Bhagavatam classes: ${s['totalSBClass'] ?? 0}, "
          "services done: ${s['totalServiceDone'] ?? 0}",
        );
      }
    } catch (_) {
      // A missing scorecard is normal for a new student.
    }

    // --- Book progress (as shown in the Book Progress section) --------------
    try {
      final books = await _scoped('booksRead', 'uid').get();

      if (books.docs.isNotEmpty) {
        final current = books.docs
            .map((d) => d.data())
            .where((d) => d['isCurrentBook'] == true)
            .map((d) => (d['bookTitle'] ?? '').toString())
            .where((t) => t.isNotEmpty)
            .toList();

        lines.add("Books started: ${books.docs.length}");
        if (current.isNotEmpty) {
          lines.add("Currently reading: ${current.join(', ')}");
        }
      }
    } catch (_) {
      // Ignore — the suggestion is still useful without book data.
    }

    // --- Association: meetings with the guide -------------------------------
    try {
      final meetings = await _scoped('associations', 'studentUid').get();

      if (meetings.docs.isEmpty) {
        lines.add("Association: no meetings requested or held yet.");
      } else {
        final byStatus = <String, int>{};
        DateTime? mostRecentHeld;

        for (final doc in meetings.docs) {
          final data = doc.data();
          final status = (data['status'] ?? 'unknown').toString();
          byStatus[status] = (byStatus[status] ?? 0) + 1;

          // A meeting counts as "held" once it is confirmed or completed.
          if (status == 'confirmed' || status == 'completed') {
            final when = data['confirmedDate'] ?? data['preferredDate'];
            if (when is Timestamp) {
              final date = when.toDate();
              if (mostRecentHeld == null || date.isAfter(mostRecentHeld)) {
                mostRecentHeld = date;
              }
            }
          }
        }

        final counts = byStatus.entries
            .map((e) => "${e.value} ${e.key}")
            .join(', ');

        lines.add(
          "Association: ${meetings.docs.length} meeting records ($counts).",
        );
        if (mostRecentHeld != null) {
          lines.add(
            "- most recent confirmed or completed meeting: "
            "${DateFormat('dd MMM yyyy').format(mostRecentHeld)}",
          );
        } else {
          lines.add("- no meeting has been confirmed or completed yet");
        }
      }
    } catch (_) {
      // Ignore — proceed without association data.
    }

    // --- Expeditions --------------------------------------------------------
    //
    // Reflection *text* is never sent. Only counts and a coarse length band,
    // because a reflection can contain personal disclosure the student wrote
    // for their guide, not for an API.
    try {
      final registrations = await _scoped('expeditionRegistrations', 'studentUid').get();

      if (registrations.docs.isEmpty) {
        lines.add("Expeditions: none registered for yet.");
      } else {
        var reflected = 0;
        var brief = 0;
        var moderate = 0;
        var detailed = 0;

        for (final doc in registrations.docs) {
          final data = doc.data();
          if (data['hasReflected'] != true) continue;
          reflected++;

          final words = (data['reflectionText'] ?? '')
              .toString()
              .trim()
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .length;

          if (words >= 100) {
            detailed++;
          } else if (words >= 30) {
            moderate++;
          } else {
            brief++;
          }
        }

        lines.add(
          "Expeditions: registered for ${registrations.docs.length}, "
          "$reflected with a reflection submitted.",
        );
        if (reflected > 0) {
          final bands = <String>[];
          if (detailed > 0) bands.add("$detailed detailed (100+ words)");
          if (moderate > 0) bands.add("$moderate moderate (30-99 words)");
          if (brief > 0) bands.add("$brief brief (under 30 words)");
          lines.add(
            "- reflection length, as a rough proxy for how much they engaged: "
            "${bands.join(', ')}. The text itself is private and not included.",
          );
        }
      }
    } catch (_) {
      // Ignore — proceed without expedition data.
    }

    // --- Approved interaction logs ------------------------------------------
    try {
      final logs = await _scoped('interactionLogs', 'studentUid').get();

      final approved = logs.docs
          .map((d) => d.data())
          .where((d) => d['status'] == 'approved')
          .toList()
        ..sort((a, b) {
          final da = a['interactionDate'];
          final db = b['interactionDate'];
          if (da is! Timestamp) return 1;
          if (db is! Timestamp) return -1;
          return db.compareTo(da);
        });

      if (approved.isEmpty) {
        lines.add("No approved interaction logs yet.");
      } else {
        lines.add("");
        lines.add("Approved interactions, most recent first:");

        // Most recent six is plenty of context without bloating the prompt.
        for (final log in approved.take(6)) {
          final summary = log['approvedSummary'] as Map<String, dynamic>? ?? {};
          final when = log['interactionDate'];
          final whenText = when is Timestamp
              ? DateFormat('dd MMM yyyy').format(when.toDate())
              : "date unknown";

          final parts = <String>[];
          void add(String label, Object? value) {
            final text = (value ?? '').toString().trim();
            if (text.isNotEmpty) parts.add("$label: $text");
          }

          final themes = summary['themes'];
          if (themes is List && themes.isNotEmpty) {
            parts.add("themes: ${themes.join(', ')}");
          }
          add("concerns", summary['studentConcerns']);
          add("commitments", summary['commitmentsMade']);
          add("temporary circumstances", summary['temporaryCircumstances']);
          add("ABCDE evidence", summary['abcdeEvidence']);
          add("previous suggested action", summary['recommendedNextAction']);

          final followUp = summary['followUpDate'];
          if (followUp is Timestamp) {
            parts.add(
              "follow-up due: ${DateFormat('dd MMM yyyy').format(followUp.toDate())}",
            );
          }

          lines.add("- $whenText — ${parts.isEmpty ? 'no detail' : parts.join('; ')}");
        }
      }
    } catch (_) {
      // Ignore — proceed with whatever was gathered.
    }

    // --- Most recent LIT reading --------------------------------------------
    //
    // Three separate lines on purpose. Never a sum, average or single figure.
    try {
      final lit = await _scoped('litAssessments', 'studentUid').get();

      final sorted = lit.docs.map((d) => d.data()).toList()
        ..sort((a, b) {
          final da = a['assessedAt'];
          final db = b['assessedAt'];
          if (da is! Timestamp) return 1;
          if (db is! Timestamp) return -1;
          return db.compareTo(da);
        });

      if (sorted.isNotEmpty) {
        final latest = sorted.first;
        final when = latest['assessedAt'];
        final whenText = when is Timestamp
            ? DateFormat('dd MMM yyyy').format(when.toDate())
            : "date unknown";

        lines.add("");
        lines.add(
          "Most recent guide assessment ($whenText, by ${latest['guideId'] ?? 'unknown'}, "
          "confidence ${latest['confidence'] ?? 'unknown'}). These are three "
          "independent readings on a 1-5 scale:",
        );
        lines.add(
          "- L, receptivity and learning relationship: ${latest['L'] ?? 'not set'} out of 5",
        );
        lines.add(
          "- I, interest in Krishna consciousness: ${latest['I'] ?? 'not set'} out of 5",
        );
        lines.add(
          "- T, available time: ${latest['T'] ?? 'not set'} out of 5",
        );

        final evidence = (latest['evidence'] ?? '').toString().trim();
        if (evidence.isNotEmpty) {
          lines.add("- evidence the guide recorded: $evidence");
        }
      }
    } catch (_) {
      // Ignore — a suggestion without a LIT reading is still useful.
    }

    return lines.join('\n');
  }

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------

  Future<void> _generate() async {
    setState(() => _working = true);

    try {
      final guide = await UpdateTokenService().getSavedGuide();
      final context_ = await _gatherContext();

      final result = await GeminiService().suggestNextAction(
        contextText: context_,
        studentName: widget.studentName,
      );

      await _docRef.set({
        'studentUid': widget.studentUid,
        'studentName': widget.studentName,
        'generatedBy': guide ?? '',
        'recommendedNextAction': result['recommendedNextAction'] ?? '',
        'recommendedReasoning': result['recommendedReasoning'] ?? '',
        'generatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      showSnackbar(context, "Suggestion generated", Colors.green,
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
        final action = (data?['recommendedNextAction'] ?? '').toString();
        final reasoning = (data?['recommendedReasoning'] ?? '').toString();
        final generatedAt = data?['generatedAt'];
        final generatedBy = (data?['generatedBy'] ?? '').toString();
        final hasSuggestion = action.isNotEmpty || reasoning.isNotEmpty;

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
                Text(
                  action.isEmpty ? "No action suggested" : action,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (reasoning.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    reasoning,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: context.g.text,
                    ),
                  ),
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
                  "Draws on this student's sadhana counters, book progress, "
                  "approved interaction logs and most recent LIT reading. "
                  "Runs only when you ask.",
                  style: TextStyle(fontSize: 13, color: context.g.mutedText),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: _working
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : OutlinedButton.icon(
                        onPressed: _generate,
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text(
                          hasSuggestion
                              ? "Regenerate suggestion"
                              : "Get suggested next action",
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
              "AI-generated suggestion — guide judgment decides the actual "
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
