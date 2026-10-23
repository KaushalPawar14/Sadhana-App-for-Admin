import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../Services/GeminiService.dart';
import '../Services/UpdateFCM.dart';
import '../utils/ExpeditionExperience.dart';
import '../utils/GuideDb.dart';
import '../utils/LeaderboardData.dart' show dottedField;
import '../utils/StudentScope.dart';
import '../utils/StudentSuggestions.dart';

/// AI suggestions for a student, as shared logic with no screen in it: the profile
/// page's "Generate suggestions" button and the AI agent both go through
/// [generateStudentSuggestions].
///
/// **On demand only.** Nothing here runs unless someone asks. The result is cached
/// in `holisticSuggestions/{studentUid}` so reopening the profile costs nothing.
/// **Guidance, never a decision:** it is never shown to a student.

/// Assembles the evidence block sent to Gemini.
///
/// Reads only collections this profile page already displays — `competition`
/// and `booksRead` — plus the two Phase 5 collections. No new ABCDE
/// collection is introduced, and none of these reads happen until the guide
/// presses the button.
/// [guideId] is the SIGNED-IN guide, not the student's assigned one —
/// the targets that belong in the prompt are the goals of whoever is
/// asking, since they are what he is trying to move.
Future<String> gatherSuggestionContext({
  required String studentUid,
  required String studentName,
  required Map<String, dynamic> profileData,
  String? guideId,
}) async {
  final db = GuideDb.instance;

  /// `collection where <uidField> == this student`, plus the scope filter the
  /// security rules need (built from the `users` map the caller already holds).
  Query<Map<String, dynamic>> scoped(String collection, String uidField) =>
      StudentScope.current().constrainForStudent(
        db.collection(collection).where(uidField, isEqualTo: studentUid),
        StudentRef.fromUser(studentUid, profileData),
      );

  final lines = <String>[];

  final role = (profileData['role'] ?? '').toString();
  final assignedGuide = (profileData['guideId'] ?? '').toString();
  if (role.isNotEmpty) lines.add("Residence: $role");
  if (assignedGuide.isNotEmpty) lines.add("Assigned guide: $assignedGuide");

  // --- What this student has committed to -----------------------------
  //
  // A suggestion that asks for more than they already promised, or that
  // ignores a promise they are keeping, is not a useful one.
  final rounds = profileData['commitmentRounds'];
  final reading = profileData['readingCommitmentMinutes'];
  final commitments = <String>[
    if (rounds is num && rounds > 0) "${rounds.toInt()} rounds a day",
    if (reading is num && reading > 0)
      "${reading.toInt()} minutes of reading a day",
  ];
  lines.add(commitments.isEmpty
      ? "Their own commitments: none set yet."
      : "Their own commitments: ${commitments.join('; ')}.");

  // --- Sadhana points of this month (the new point system, `competition/{name}`) ---------
  try {
    final comp = await db.collection('competition').doc(studentName).get();
    final s = comp.data();
    if (s != null) {
      double n(String f) {
        final v = dottedField(s, 'monthly.$f');
        return v is num ? v.toDouble() : 0;
      }

      String p(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
      lines.add(
        "This month's sadhana points — total (with multipliers): ${p(n('total_score'))}; "
        "chanting: ${p(n('pts_chanting'))}, reading: ${p(n('pts_reading'))}, "
        "hearing (Bhagavatam class + extra lecture): ${p(n('pts_hearing'))}, "
        "services: ${p(n('pts_service'))}; days reported: ${p(n('days_count'))}",
      );
    }
  } catch (_) {
    // No competition document yet is normal for a new student.
  }

  // --- Book progress (as shown in the Book Progress section) --------------
  try {
    final books = await scoped('booksRead', 'uid').get();

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
    final meetings = await scoped('associations', 'studentUid').get();

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
  // The registration's reflection *text* is still never sent — only counts
  // and a coarse length band, because a reflection can contain personal
  // disclosure the student wrote for their guide, not for an API.
  //
  // The EXPERIENCE (what they learned, what touched them, what they will
  // change — written after a trip they completed) is different, and is sent:
  // it is the "E" evidence Master 1 B asks for, and the student was told it
  // is written for their guides. Clipped per answer and labelled as the
  // student's own words, so it is weighed rather than obeyed.
  try {
    final registrations = await scoped('expeditionRegistrations', 'studentUid').get();

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

  // --- What they wrote about the trips they completed -----------------------
  try {
    final snap = await scoped('expeditionExperiences', 'studentUid').get();
    lines.addAll(experienceEvidenceLines(
        parseExperiences(snap.docs.map((d) => d.data()))));
  } catch (_) {
    // Ignore — the suggestion is still useful without it.
  }

  // --- Approved interaction logs ------------------------------------------
  try {
    final logs = await scoped('interactionLogs', 'studentUid').get();

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
    final lit = await scoped('litAssessments', 'studentUid').get();

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

  // --- The asking guide's own active targets ---------------------------
  //
  // Master 1 B: "the guide's active targets (the guide's goals and
  // mindset)". A suggestion that also moves a target the guide is
  // already working on is worth more to him than one that does not —
  // the prompt is explicit that this must never be at the student's
  // expense.
  if (guideId != null && guideId.isNotEmpty) {
    try {
      final targets = await db
          .collection('guideTargets')
          .doc(guideId)
          .collection('targets')
          .where('status', isEqualTo: 'active')
          .get();

      if (targets.docs.isNotEmpty) {
        lines.add("");
        lines.add(
          "Your own active targets — the goals you are working toward "
          "with this whole group:",
        );
        for (final doc in targets.docs) {
          final t = doc.data();
          final metric = (t['metric'] ?? '').toString();
          final unit = metric == 'books' ? 'books finished' : 'rounds';
          final students = t['studentCountGoal'];
          final value = t['perStudentValueGoal'];
          final end = t['endDate'];
          final by = end is Timestamp
              ? " by ${DateFormat('dd MMM yyyy').format(end.toDate())}"
              : "";
          final phase = t['currentPhase'];
          final total = t['totalPhases'];
          final where = (phase is num && total is num)
              ? " (on phase ${phase.toInt()} of ${total.toInt()})"
              : "";
          lines.add(
            "- $metric: ${students ?? '?'} students each at "
            "${value ?? '?'} $unit$by$where",
          );
        }
      }
    } catch (_) {
      // A guide with no targets, or a read that failed, simply leaves
      // this out — the suggestion is still useful without it.
    }
  }

  return lines.join('\n');
}

/// Gathers the evidence, asks Gemini for suggestions and caches them for the student.
///
/// [profileData] is the `users/{uid}` map the caller already holds (the profile page
/// has streamed it). Every read inside is scoped to the signed-in admin, so a student
/// outside their reach reads as empty rather than leaking.
///
/// Throws [GeminiException] when the model cannot answer (quota, outage). Returns how
/// many suggestions were saved.
Future<int> generateStudentSuggestions({
  required String studentUid,
  required String studentName,
  required Map<String, dynamic> profileData,
}) async {
  final guide = await UpdateTokenService().getSavedGuide();
  final contextText = await gatherSuggestionContext(
    studentUid: studentUid,
    studentName: studentName,
    profileData: profileData,
    guideId: guide,
  );

  final result = await GeminiService().suggestNextAction(
    contextText: contextText,
    studentName: studentName,
  );

  final suggestions = parseSuggestions(result['suggestions']);

  await GuideDb.instance.collection('holisticSuggestions').doc(studentUid).set({
    'studentUid': studentUid,
    'studentName': studentName,
    'generatedBy': guide ?? '',
    'suggestions': suggestions.map((x) => x.toMap()).toList(),
    // Still written so a Guide app build older than this one keeps showing the card
    // it knows how to read.
    'recommendedNextAction': result['recommendedNextAction'] ?? '',
    'recommendedReasoning': result['recommendedReasoning'] ?? '',
    'generatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  return suggestions.length;
}
