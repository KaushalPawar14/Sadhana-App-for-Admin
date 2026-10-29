import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../actions/SuggestionActions.dart';
import '../Services/GuideAi.dart';
import '../utils/AdminProfile.dart';
import '../utils/SuggestionsReady.dart';
import '../utils/UnseenDot.dart';
import '../utils/Snackbar.dart';
import '../utils/StudentSuggestions.dart';
import '../theme/GuideTheme.dart';
import '../utils/GuideDb.dart';
import '../widgets/AiText.dart';
import '../widgets/GuideWait.dart';

/// Holistic "suggested next action" (Phase 5, item 1 — final piece).
///
/// Three to five specific things the guide could do with this student, each with why and a first
/// step, made by the SERVER (OpenAI, `functions/interactionAI.js`) from everything recorded about the
/// student: sadhana points, books, meetings, expeditions and what they wrote about them, the latest
/// interactions, the latest LIT reading and the guide's own active targets.
///
/// **They arrive by themselves.** Every saved interaction is analysed on the server, which then makes
/// new suggestions for that student and tells their guide ("New suggestions ready for <student>").
/// Until the guide opens them this card says so and the orange dot trail leads here (see
/// `utils/SuggestionsReady.dart`); it clears when the card has been on screen for a moment. The
/// "Refresh suggestions" button is for asking again right now. Nothing runs when the page opens.
///
/// **Guidance, never a decision** (Section 1). The output carries a permanent
/// disclaimer and is never shown to a student.
///
/// **LIT is given as three separate readings.** `L`, `I` and `T` go into the prompt as three independent
/// lines and the prompt forbids combining them. Nothing here computes a total, average, level or tier.
class HolisticSuggestionSection extends StatefulWidget {
  final String studentUid;
  final String studentName;

  const HolisticSuggestionSection({
    super.key,
    required this.studentUid,
    required this.studentName,
  });

  @override
  State<HolisticSuggestionSection> createState() =>
      _HolisticSuggestionSectionState();
}

class _HolisticSuggestionSectionState extends State<HolisticSuggestionSection> {
  final FirebaseFirestore _firestore = GuideDb.instance;

  bool _working = false;

  /// This admin's id (their seen markers are keyed by it); empty when no profile is loaded.
  String get _me => AdminProfileProvider.current?.id ?? '';

  /// Are the suggestions on this card new to this admin (made by the server, not yet opened)?
  late final Stream<bool> _unseenStream = SuggestionsReady.unseenFor(_me, widget.studentUid);
  StreamSubscription<bool>? _unseenSub;
  bool _unseen = false;
  Timer? _openTimer;
  ScrollPosition? _position;

  @override
  void initState() {
    super.initState();
    _unseenSub = _unseenStream.listen((v) {
      if (!mounted) return;
      setState(() => _unseen = v);
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisible());
    }, onError: (_) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _position) {
      _position?.removeListener(_checkVisible);
      _position = p;
      _position?.addListener(_checkVisible);
    }
  }

  @override
  void dispose() {
    _unseenSub?.cancel();
    _openTimer?.cancel();
    _position?.removeListener(_checkVisible);
    super.dispose();
  }

  /// "Opened": more than half of the card has been on screen for a moment. Only then does the dot trail clear.
  void _checkVisible() {
    if (!mounted || !_unseen) {
      _openTimer?.cancel();
      _openTimer = null;
      return;
    }
    try {
      final box = context.findRenderObject();
      final scrollBox = Scrollable.maybeOf(context)?.context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || scrollBox is! RenderBox || !scrollBox.hasSize) return;
      final top = box.localToGlobal(Offset.zero, ancestor: scrollBox).dy;
      final h = box.size.height;
      final shown = math.max(0.0, math.min(top + h, scrollBox.size.height) - math.max(top, 0.0));
      final enough = h > 0 && shown >= math.min(h, scrollBox.size.height) * 0.5;
      if (enough) {
        _openTimer ??= Timer(const Duration(milliseconds: 1200), _opened);
      } else {
        _openTimer?.cancel();
        _openTimer = null;
      }
    } catch (_) {
      // Not laid out yet: the next frame or scroll checks again.
    }
  }

  void _opened() {
    _openTimer = null;
    if (!mounted || !_unseen) return;
    SuggestionsReady.markOpened(_me, widget.studentUid).catchError((_) {});
  }

  DocumentReference<Map<String, dynamic>> get _docRef =>
      _firestore.collection('holisticSuggestions').doc(widget.studentUid);

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------

  Future<void> _generate() async {
    setState(() => _working = true);

    try {
      // One shared function (actions/SuggestionActions.dart): the AI agent generates suggestions
      // through exactly this. The server does the work.
      final count = await generateStudentSuggestions(studentUid: widget.studentUid);

      if (!mounted) return;
      showSnackbar(
          context,
          "$count suggestions generated",
          Colors.green,
          Icons.check_circle);
    } on AiException catch (e) {
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
              if (_unseen && hasSuggestion) ...[
                Row(
                  children: [
                    const UnseenDot(size: 9),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        SuggestionsReady.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: context.g.attention,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
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
                  "counters, book progress, interactions, most recent LIT "
                  "reading and your own active targets. New ones appear here "
                  "by themselves after you save an interaction; tap Generate "
                  "to ask for them now.",
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
              AiText(
                s.action,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              if (s.why.isNotEmpty) ...[
                const SizedBox(height: 4),
                AiText(
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
                    child: AiText(
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
