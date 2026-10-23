import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../Services/HierarchyApi.dart';
import '../Services/VoiceRecorder.dart';
import '../theme/GuideTheme.dart';
import '../utils/VoiceNote.dart';
import 'GuideWait.dart';

/// A mic for a text field: speak, get clean English text (Master Part 3).
///
///   idle        a "Speak" button
///   recording   a red dot, the time so far out of three minutes, Pause, Done and Cancel
///   paused      the time held, Resume, Done and Cancel (paused time is not counted)
///   processing  "Turning your voice into text…"
///   failed      what went wrong in words, with Retry when a retry could help
///
/// The text it produces goes to [onText] and is for the parent to put in its
/// field — appended after what is there, editable before anything is saved.
/// The recording itself is not kept: the file is deleted as soon as it is read,
/// the bytes are dropped after a success, and no raw transcript exists to show.
///
/// A recording stops by itself at [kMaxVoiceSeconds].
class VoiceNoteButton extends StatefulWidget {
  const VoiceNoteButton({
    super.key,
    required this.purpose,
    required this.onText,
    this.existingText,
    this.studentName = '',
    this.enabled = true,
  });

  final VoicePurpose purpose;

  /// Called with the clean text; the parent appends it to its field.
  final ValueChanged<String> onText;

  /// What the field holds right now, sent for context only.
  final String Function()? existingText;

  /// The student the note is about, so the model spells the name the way the
  /// app does.
  final String studentName;

  final bool enabled;

  @override
  State<VoiceNoteButton> createState() => _VoiceNoteButtonState();
}

enum _Phase { idle, recording, paused, processing, failed }

class _VoiceNoteButtonState extends State<VoiceNoteButton> {
  _Phase _phase = _Phase.idle;
  int _seconds = 0;
  Timer? _ticker;
  Object? _error;

  /// Kept only so Retry can send the same recording again after a connection
  /// failure. Dropped on success, on Cancel and on dispose.
  VoiceClip? _clip;

  @override
  void dispose() {
    _ticker?.cancel();
    _clip = null;
    // A guide who leaves mid-recording must not leave the mic open.
    if (_phase == _Phase.recording || _phase == _Phase.paused) {
      VoiceRecorder.instance.cancel();
    }
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _clip = null;
    });
    try {
      if (!await VoiceRecorder.instance.ensurePermission()) {
        throw const MicPermissionDenied();
      }
      await VoiceRecorder.instance.start();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _phase = _Phase.failed;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.recording;
      _seconds = 0;
    });
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_seconds >= kMaxVoiceSeconds) _finish();
    });
  }

  /// Holds the recording. The clock stops with it, so the three minutes are minutes of
  /// speech, not minutes of the guide thinking.
  Future<void> _pause() async {
    if (_phase != _Phase.recording) return;
    _ticker?.cancel();
    try {
      await VoiceRecorder.instance.pause();
    } catch (e) {
      if (!mounted) return;
      await VoiceRecorder.instance.cancel();
      setState(() {
        _error = e;
        _phase = _Phase.failed;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.paused);
  }

  Future<void> _resume() async {
    if (_phase != _Phase.paused) return;
    try {
      await VoiceRecorder.instance.resume();
    } catch (e) {
      if (!mounted) return;
      await VoiceRecorder.instance.cancel();
      setState(() {
        _error = e;
        _phase = _Phase.failed;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.recording);
    _startTicker();
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    await VoiceRecorder.instance.cancel();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _clip = null;
    });
  }

  Future<void> _finish() async {
    if (_phase != _Phase.recording && _phase != _Phase.paused) return;
    _ticker?.cancel();
    setState(() => _phase = _Phase.processing);
    try {
      final clip = await VoiceRecorder.instance.stop();
      if (clip == null) {
        throw HierarchyException(
            'failed-precondition',
            "I couldn't make that out. Please try again, a little closer to "
            'the phone and somewhere quieter.');
      }
      _clip = clip;
      await _send();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _phase = _Phase.failed;
      });
    }
  }

  Future<void> _send() async {
    final clip = _clip!;
    final text = await HierarchyApi.instance.voiceToEnglishText(
      audioBase64: base64Encode(clip.bytes),
      mimeType: clip.mimeType,
      durationSeconds: clip.seconds,
      purpose: widget.purpose.wire,
      studentName: widget.studentName,
      existingText: widget.existingText?.call() ?? '',
    );
    if (!mounted) return;
    // Success: the audio is no longer needed anywhere.
    _clip = null;
    setState(() => _phase = _Phase.idle);
    widget.onText(text);
  }

  Future<void> _retry() async {
    if (_error != null && canRetrySameClip(_error!) && _clip != null) {
      setState(() {
        _phase = _Phase.processing;
        _error = null;
      });
      try {
        await _send();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = e;
          _phase = _Phase.failed;
        });
      }
      return;
    }
    await _start();
  }

  void _dismiss() => setState(() {
        _phase = _Phase.idle;
        _error = null;
        _clip = null;
      });

  @override
  Widget build(BuildContext context) {
    final g = context.g;

    switch (_phase) {
      case _Phase.idle:
        return Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const ValueKey('voice-speak'),
            onPressed: widget.enabled ? _start : null,
            icon: const Icon(Icons.mic_none, size: 20),
            label: const Text('Speak'),
            style: TextButton.styleFrom(foregroundColor: g.brass),
          ),
        );

      case _Phase.recording:
      case _Phase.paused:
        final paused = _phase == _Phase.paused;
        return Container(
          key: ValueKey(paused ? 'voice-paused' : 'voice-recording'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: g.danger.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: g.danger.withValues(alpha: .35)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(paused ? Icons.pause_circle_filled : Icons.fiber_manual_record,
                      size: 14, color: paused ? g.mutedText : g.danger),
                  const SizedBox(width: 6),
                  Text(
                    '${paused ? 'Paused' : 'Recording'} ${formatElapsed(_seconds)} / '
                    '${formatElapsed(kMaxVoiceSeconds)}',
                    key: const ValueKey('voice-timer'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    key: const ValueKey('voice-cancel'),
                    onPressed: _cancel,
                    child: const Text('Cancel'),
                  ),
                  TextButton.icon(
                    key: ValueKey(paused ? 'voice-resume' : 'voice-pause'),
                    onPressed: paused ? _resume : _pause,
                    icon: Icon(paused ? Icons.mic : Icons.pause, size: 18),
                    label: Text(paused ? 'Resume' : 'Pause'),
                  ),
                  ElevatedButton.icon(
                    key: const ValueKey('voice-done'),
                    onPressed: _finish,
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Done'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: g.danger,
                        foregroundColor: g.onPrimary),
                  ),
                ],
              ),
            ],
          ),
        );

      case _Phase.processing:
        return Padding(
          key: const ValueKey('voice-processing'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 18, height: 18, child: GuideBusyDot()),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Turning your voice into text…',
                    style: TextStyle(fontSize: 13, color: g.mutedText)),
              ),
            ],
          ),
        );

      case _Phase.failed:
        return Container(
          key: const ValueKey('voice-failed'),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
          decoration: BoxDecoration(
            color: g.warning.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: g.warning.withValues(alpha: .35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                voiceFailureMessage(_error ?? ''),
                key: const ValueKey('voice-message'),
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  children: [
                    TextButton(
                      key: const ValueKey('voice-dismiss'),
                      onPressed: _dismiss,
                      child: const Text('Not now'),
                    ),
                    if (_error is! MicPermissionDenied)
                      TextButton(
                        key: const ValueKey('voice-retry'),
                        onPressed: _retry,
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }
}
