import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// A Gemini failure with a message that is safe to show the guide verbatim.
class GeminiException implements Exception {
  final String message;

  const GeminiException(this.message);

  @override
  String toString() => message;
}

/// Structured extraction of a guide's interaction notes.
///
/// The key is loaded from `credentials/gemini-key.json` — the same pattern
/// `AccessToken.dart` uses for `credentials/service-account.json`: gitignored,
/// declared as a Flutter asset, never hardcoded in Dart source.
///
/// This service only ever *extracts*. It does not decide anything, and it is
/// explicitly instructed never to produce L/I/T scores — LIT stays a guide-only
/// judgement, and `possibleLitEvidence` is free text the guide reads and
/// weighs. Nothing this returns is persisted as final: everything lands in
/// `extractedDraft` and waits for the guide to approve it.
class GeminiService {
  static const String _keyAsset = 'credentials/gemini-key.json';
  static const String _defaultModel = 'gemini-2.5-flash';
  static const String _placeholder = 'YOUR_GEMINI_API_KEY';

  /// The keys the model is asked to return, and the ones the UI reads back.
  static const List<String> draftFields = [
    'interactionType',
    'interactionDateTime',
    'durationMinutes',
    'themes',
    'studentConcerns',
    'personalRevelation',
    'commitmentsMade',
    'followUpDate',
    'abcdeEvidence',
    'possibleLitEvidence',
    'temporaryCircumstances',
    'recommendedNextAction',
    'recommendedReasoning',
    'extractionConfidence',
  ];

  Map<String, dynamic>? _cachedConfig;

  Future<Map<String, dynamic>> _loadConfig() async {
    final cached = _cachedConfig;
    if (cached != null) return cached;

    final String raw;
    try {
      raw = await rootBundle.loadString(_keyAsset);
    } catch (_) {
      throw const GeminiException(
        "Gemini key file not bundled. Add credentials/gemini-key.json "
        "(copy gemini-key.json.template), then run flutter pub get and rebuild.",
      );
    }

    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw const GeminiException(
        "credentials/gemini-key.json is not valid JSON.",
      );
    }

    final key = (parsed['apiKey'] ?? '').toString().trim();
    if (key.isEmpty || key == _placeholder) {
      throw const GeminiException(
        "Gemini API key is not set yet. Paste it into "
        "credentials/gemini-key.json and rebuild.",
      );
    }

    _cachedConfig = parsed;
    return parsed;
  }

  /// Sends [rawText] to Gemini and returns the parsed draft map.
  ///
  /// Throws [GeminiException] with a guide-readable message on any failure.
  /// The caller is responsible for having already persisted [rawText] — this
  /// method never writes to Firestore, so a failure here cannot lose notes.
  Future<Map<String, dynamic>> extractInteraction({
    required String rawText,
    required String studentName,
  }) async {
    if (rawText.trim().isEmpty) {
      throw const GeminiException("Nothing to extract — the notes are empty.");
    }

    final config = await _loadConfig();
    final apiKey = (config['apiKey'] ?? '').toString().trim();
    final model = (config['model'] ?? '').toString().trim().isEmpty
        ? _defaultModel
        : (config['model'] as String).trim();

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent?key=$apiKey',
    );

    final body = {
      'contents': [
        {
          'parts': [
            {'text': _buildPrompt(rawText: rawText, studentName: studentName)}
          ]
        }
      ],
      // Ask for JSON directly rather than trying to strip a preamble afterwards.
      'generationConfig': {
        'responseMimeType': 'application/json',
        'temperature': 0.2,
      },
    };

    final http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw GeminiException("Could not reach Gemini: $e");
    }

    if (response.statusCode != 200) {
      throw GeminiException(
        "Gemini returned ${response.statusCode}. ${_errorDetail(response.body)}",
      );
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const GeminiException("Gemini sent a response that was not JSON.");
    }

    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const GeminiException(
        "Gemini returned no result. It may have blocked the content — "
        "try rewording the notes.",
      );
    }

    final parts = candidates.first['content']?['parts'];
    if (parts is! List || parts.isEmpty) {
      throw const GeminiException("Gemini returned an empty result.");
    }

    final text = (parts.first['text'] ?? '').toString();
    if (text.trim().isEmpty) {
      throw const GeminiException("Gemini returned an empty result.");
    }

    final Object? draft;
    try {
      draft = jsonDecode(text);
    } catch (_) {
      throw const GeminiException(
        "Gemini's answer was not valid JSON. Try Extract again.",
      );
    }

    if (draft is! Map<String, dynamic>) {
      throw const GeminiException(
        "Gemini returned the wrong shape. Try Extract again.",
      );
    }

    return _normalise(draft);
  }

  /// Asks for ONE current suggested next action, given a student's history.
  ///
  /// [contextText] is assembled by the caller and must already be free of raw
  /// dictation and of any combined LIT figure — this method neither computes
  /// nor accepts one. Returns `recommendedNextAction` and
  /// `recommendedReasoning`.
  ///
  /// The output is guidance for the guide to weigh, never an instruction and
  /// never something shown to a student.
  Future<Map<String, String>> suggestNextAction({
    required String contextText,
    required String studentName,
  }) async {
    final raw = await _generate(
      _buildSuggestionPrompt(
        contextText: contextText,
        studentName: studentName,
      ),
    );

    return {
      'recommendedNextAction':
          (raw['recommendedNextAction'] ?? '').toString().trim(),
      'recommendedReasoning':
          (raw['recommendedReasoning'] ?? '').toString().trim(),
    };
  }

  String _buildSuggestionPrompt({
    required String contextText,
    required String studentName,
  }) {
    return '''
You are helping a FOLK spiritual guide think about one of their students. The
guide reads what you write and decides for themselves what to actually do. You
are not instructing anyone.

Student: $studentName

The evidence below may cover all five dimensions of FOLK practice, plus the
guide's own private readings and their history of meeting this student:

- A, Association — meetings with the guide
- B, Books — reading progress
- C, Chanting — japa rounds
- D, Devotional service — services performed
- E, Expeditions — pilgrimages and retreats, and reflections afterwards
- L, I and T — the guide's private readings (see the rule below)
- Approved summaries of past interactions

Weigh the whole picture, not whichever dimension happens to have the most data.
A dimension that is absent from the evidence is usually itself informative — a
student with no meetings, or no expedition, may simply have never been invited.
Say when that is what you are reacting to.

Return ONLY a JSON object with exactly these two keys:

- "recommendedNextAction": ONE concrete, realistic next step this guide could
  take with this student in the coming days. A single action, not a list.
- "recommendedReasoning": why that step follows from the evidence below.
  Reference the specific evidence. Two or three sentences.

Hard rules:
- Output JSON only. No markdown, no code fences, no commentary.
- Never invent facts. Work only from the evidence given below. If the evidence
  is thin, say so in the reasoning and suggest something correspondingly small,
  such as making contact to find out more.
- L, I and T are three SEPARATE independent readings. Never add, average,
  combine, or rank them, and never describe the student with a single overall
  score, level, grade or tier of any kind.
- Suggest one action to the GUIDE. Do not write instructions addressed to the
  student, and do not write spiritual instruction — the guide provides that.
- Respect the student's stated circumstances. If they are in exams or unwell,
  a smaller step is the better suggestion.
- Phrase it as a suggestion the guide may reject, not as a directive.

Evidence:
"""
$contextText
"""
''';
  }

  /// Shared request path for every prompt this service sends.
  Future<Map<String, dynamic>> _generate(String prompt) async {
    final config = await _loadConfig();
    final apiKey = (config['apiKey'] ?? '').toString().trim();
    final model = (config['model'] ?? '').toString().trim().isEmpty
        ? _defaultModel
        : (config['model'] as String).trim();

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent?key=$apiKey',
    );

    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'temperature': 0.2,
      },
    };

    final http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw GeminiException("Could not reach Gemini: $e");
    }

    if (response.statusCode != 200) {
      throw GeminiException(
        "Gemini returned ${response.statusCode}. ${_errorDetail(response.body)}",
      );
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const GeminiException("Gemini sent a response that was not JSON.");
    }

    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const GeminiException(
        "Gemini returned no result. It may have blocked the content — "
        "try rewording the notes.",
      );
    }

    final parts = candidates.first['content']?['parts'];
    if (parts is! List || parts.isEmpty) {
      throw const GeminiException("Gemini returned an empty result.");
    }

    final text = (parts.first['text'] ?? '').toString();
    if (text.trim().isEmpty) {
      throw const GeminiException("Gemini returned an empty result.");
    }

    final Object? parsed;
    try {
      parsed = jsonDecode(text);
    } catch (_) {
      throw const GeminiException(
        "Gemini's answer was not valid JSON. Try again.",
      );
    }

    if (parsed is! Map<String, dynamic>) {
      throw const GeminiException(
        "Gemini returned the wrong shape. Try again.",
      );
    }

    return parsed;
  }

  /// Pulls `error.message` out of an API error body when it is there.
  String _errorDetail(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] != null) {
          return error['message'].toString();
        }
      }
    } catch (_) {
      // Fall through to the generic message below.
    }
    return "Check the API key and the model name in gemini-key.json.";
  }

  String _buildPrompt({required String rawText, required String studentName}) {
    return '''
You are helping a FOLK spiritual guide turn their own rough notes about a
meeting with a student into a structured draft. The guide will read, edit and
approve everything you produce — you are not making any decision.

Student name: $studentName

Return ONLY a JSON object with exactly these keys:

- "interactionType": short label, e.g. "One-on-one meeting", "Phone call",
  "Group program", "Informal chat". "" if unclear.
- "interactionDateTime": ISO-8601 string if the notes state when it happened,
  otherwise "".
- "durationMinutes": integer minutes, or 0 if not stated.
- "themes": array of short strings, the topics actually discussed. [] if none.
- "studentConcerns": difficulties, doubts or struggles the student raised. ""
  if none.
- "personalRevelation": anything the student shared that shows trust or
  relationship depth. "" if none.
- "commitmentsMade": what the student or the guide agreed to do. "" if none.
- "followUpDate": ISO-8601 string if a next meeting or follow-up date is
  stated or clearly implied, otherwise "".
- "abcdeEvidence": free text noting anything relevant to Association, Books,
  Chanting, Devotional service or Expeditions. "" if none.
- "possibleLitEvidence": free text ONLY. Observations that might later inform
  the guide's private assessment of the student's receptivity, interest, or
  available time. Quote or paraphrase the evidence. "" if none.
- "temporaryCircumstances": exams, illness, travel, family situation — things
  that are true right now but will pass. "" if none.
- "recommendedNextAction": one concrete, realistic next step the guide could
  take. "" if the notes do not support one.
- "recommendedReasoning": why that action, grounded in what the notes say. ""
  if no action.
- "extractionConfidence": exactly one of "low", "medium", "high" — how well the
  notes supported this extraction.

Hard rules:
- Output JSON only. No markdown, no code fences, no commentary.
- Never invent facts. If the notes do not say it, use "" or 0 or [].
- NEVER output a numeric L, I or T score, and never rate the student on any
  scale. "possibleLitEvidence" is descriptive text, never a number.
- Do not give the student spiritual instruction or personal advice. Your
  "recommendedNextAction" is a suggestion to the guide, who decides.

The guide's notes:
"""
$rawText
"""
''';
  }

  /// Coerces whatever came back into the exact shape the review screen expects,
  /// so a missing or oddly-typed key can never crash the UI.
  Map<String, dynamic> _normalise(Map<String, dynamic> raw) {
    String str(String key) => (raw[key] ?? '').toString().trim();

    final themesRaw = raw['themes'];
    final themes = themesRaw is List
        ? themesRaw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];

    final durationRaw = raw['durationMinutes'];
    final duration = durationRaw is num
        ? durationRaw.toInt()
        : int.tryParse(durationRaw?.toString() ?? '') ?? 0;

    var confidence = str('extractionConfidence').toLowerCase();
    if (confidence != 'low' && confidence != 'medium' && confidence != 'high') {
      confidence = 'low';
    }

    return {
      'interactionType': str('interactionType'),
      'interactionDateTime': str('interactionDateTime'),
      'durationMinutes': duration,
      'themes': themes,
      'studentConcerns': str('studentConcerns'),
      'personalRevelation': str('personalRevelation'),
      'commitmentsMade': str('commitmentsMade'),
      'followUpDate': str('followUpDate'),
      'abcdeEvidence': str('abcdeEvidence'),
      'possibleLitEvidence': str('possibleLitEvidence'),
      'temporaryCircumstances': str('temporaryCircumstances'),
      'recommendedNextAction': str('recommendedNextAction'),
      'recommendedReasoning': str('recommendedReasoning'),
      'extractionConfidence': confidence,
    };
  }
}
